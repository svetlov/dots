#!/usr/bin/env python3
"""Analyze Claude Code JSONL usage locally, with no API requests."""

import json
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


LARGE_CACHE_READ_TOKENS = 150_000
FULL_RECACHE_TOKENS = 100_000
FULL_RECACHE_MAX_READ_RATIO = 0.10
TOKENS_PER_MILLION = 1_000_000

# USD per million tokens. Unknown/future model families remain unpriced instead
# of silently borrowing a rate that may be wrong.
MODEL_RATES = {
    "opus_4": {
        "input": 5.0,
        "output": 25.0,
        "cache_read": 0.50,
        "cache_create_5m": 6.25,
        "cache_create_1h": 10.0,
    },
    "fable_5": {
        "input": 10.0,
        "output": 50.0,
        "cache_read": 1.0,
        "cache_create_5m": 12.50,
        "cache_create_1h": 20.0,
    },
    "sonnet": {
        "input": 3.0,
        "output": 15.0,
        "cache_read": 0.30,
        "cache_create_5m": 3.75,
        "cache_create_1h": 6.0,
    },
    "haiku_4_5": {
        "input": 1.0,
        "output": 5.0,
        "cache_read": 0.10,
        "cache_create_5m": 1.25,
        "cache_create_1h": 2.0,
    },
}

TRIGGER_LABELS = {
    "human": "Human prompts",
    "monitor_notification": "Monitor notifications",
    "subagent_completion_notification": "Subagent completion notifications",
    "subagent": "Subagent requests",
    "background_task_notification": "Background-task notifications",
    "task_notification": "Other task notifications",
    "unattributed": "Unattributed/internal",
}

TOKEN_FIELDS = (
    "input",
    "output",
    "cache_read",
    "cache_create",
    "cache_create_5m",
    "cache_create_1h",
)

COST_FIELDS = (
    "estimated_total_usd",
    "estimated_cache_usd",
    "estimated_cache_read_usd",
    "estimated_cache_write_5m_usd",
    "estimated_cache_write_1h_usd",
)


def _empty_tokens() -> Dict[str, int]:
    return {field: 0 for field in TOKEN_FIELDS}


def _empty_cost() -> Dict[str, float]:
    return {field: 0.0 for field in COST_FIELDS}


def _number(value: Any) -> int:
    if isinstance(value, (int, float)):
        return int(value)
    return 0


def _parse_timestamp(value: Any) -> Optional[datetime]:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed


def _isoformat(date_time: datetime) -> str:
    return date_time.isoformat().replace("+00:00", "Z")


def _extract_text(record: Mapping[str, Any]) -> str:
    message = record.get("message")
    if not isinstance(message, dict):
        return ""
    content = message.get("content")
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    text_parts = []
    for block in content:
        if (
            isinstance(block, dict)
            and block.get("type") == "text"
            and isinstance(block.get("text"), str)
        ):
            text_parts.append(block["text"])
    return "\n".join(text_parts)


def _user_trigger(record: Mapping[str, Any]) -> Optional[str]:
    if record.get("type") != "user":
        return None
    text = _extract_text(record).strip()
    if not text or text.startswith("<system-reminder>"):
        return None
    if "<task-notification>" not in text:
        return "human"
    if "<summary>Monitor event:" in text or "<summary>Monitor \"" in text:
        return "monitor_notification"
    if "<summary>Agent \"" in text or "<summary>Dynamic workflow " in text:
        return "subagent_completion_notification"
    if "<summary>Background command " in text:
        return "background_task_notification"
    return "task_notification"


def _usage_from_record(record: Mapping[str, Any]) -> Optional[Dict[str, int]]:
    message = record.get("message")
    if not isinstance(message, dict):
        return None
    usage = message.get("usage")
    if not isinstance(usage, dict):
        return None
    cache_creation = usage.get("cache_creation")
    if not isinstance(cache_creation, dict):
        cache_creation = {}
    return {
        "input": _number(usage.get("input_tokens")),
        "output": _number(usage.get("output_tokens")),
        "cache_read": _number(usage.get("cache_read_input_tokens")),
        "cache_create": _number(usage.get("cache_creation_input_tokens")),
        "cache_create_5m": _number(
            cache_creation.get("ephemeral_5m_input_tokens")
        ),
        "cache_create_1h": _number(
            cache_creation.get("ephemeral_1h_input_tokens")
        ),
    }


def _merge_maximum_usage(
    existing: Mapping[str, int],
    candidate: Mapping[str, int],
) -> Dict[str, int]:
    return {
        field: max(existing.get(field, 0), candidate.get(field, 0))
        for field in TOKEN_FIELDS
    }


def _model_rates(model: Any) -> Optional[Mapping[str, float]]:
    if not isinstance(model, str):
        return None
    normalized = model.replace("[1m]", "")
    if normalized.startswith("claude-opus-4-"):
        return MODEL_RATES["opus_4"]
    if normalized.startswith("claude-fable-5"):
        return MODEL_RATES["fable_5"]
    if normalized.startswith("claude-sonnet-4-") or normalized.startswith(
        "claude-sonnet-5"
    ):
        return MODEL_RATES["sonnet"]
    if normalized.startswith("claude-haiku-4-5"):
        return MODEL_RATES["haiku_4_5"]
    return None


def _request_cost(
    tokens: Mapping[str, int],
    model: Any,
) -> Optional[Dict[str, float]]:
    rates = _model_rates(model)
    if rates is None:
        return None
    unclassified_cache_create = max(
        0,
        tokens["cache_create"]
        - tokens["cache_create_5m"]
        - tokens["cache_create_1h"],
    )
    cache_create_5m = tokens["cache_create_5m"] + unclassified_cache_create
    read_cost = tokens["cache_read"] * rates["cache_read"] / TOKENS_PER_MILLION
    write_5m_cost = (
        cache_create_5m * rates["cache_create_5m"] / TOKENS_PER_MILLION
    )
    write_1h_cost = (
        tokens["cache_create_1h"]
        * rates["cache_create_1h"]
        / TOKENS_PER_MILLION
    )
    cache_cost = read_cost + write_5m_cost + write_1h_cost
    total_cost = (
        cache_cost
        + tokens["input"] * rates["input"] / TOKENS_PER_MILLION
        + tokens["output"] * rates["output"] / TOKENS_PER_MILLION
    )
    return {
        "estimated_total_usd": total_cost,
        "estimated_cache_usd": cache_cost,
        "estimated_cache_read_usd": read_cost,
        "estimated_cache_write_5m_usd": write_5m_cost,
        "estimated_cache_write_1h_usd": write_1h_cost,
    }


def _trace_trigger(
    parent_uuid: Any,
    nodes: Mapping[str, Mapping[str, Any]],
) -> str:
    current_uuid = parent_uuid if isinstance(parent_uuid, str) else None
    visited = set()
    while current_uuid and current_uuid not in visited:
        visited.add(current_uuid)
        node = nodes.get(current_uuid)
        if node is None:
            break
        trigger = node.get("trigger")
        if isinstance(trigger, str):
            return trigger
        parent = node.get("parent_uuid")
        current_uuid = parent if isinstance(parent, str) else None
    return "unattributed"


def _request_key(record: Mapping[str, Any]) -> Optional[str]:
    for value in (
        record.get("requestId"),
        record.get("message", {}).get("id")
        if isinstance(record.get("message"), dict)
        else None,
        record.get("uuid"),
    ):
        if isinstance(value, str) and value:
            return value
    return None


def _project_name(cwd: Any, log_path: Path) -> str:
    if isinstance(cwd, str) and cwd:
        return Path(cwd).name
    return log_path.parent.name


def _read_log(
    log_path: Path,
    is_subagent: bool,
) -> Tuple[List[Dict[str, Any]], int]:
    nodes: Dict[str, Dict[str, Any]] = {}
    requests: Dict[str, Dict[str, Any]] = {}
    invalid_lines = 0
    try:
        stream = log_path.open(encoding="utf-8")
    except OSError:
        return [], 1

    with stream:
        for line in stream:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                invalid_lines += 1
                continue
            if not isinstance(record, dict):
                continue
            record_uuid = record.get("uuid")
            if isinstance(record_uuid, str):
                nodes[record_uuid] = {
                    "parent_uuid": record.get("parentUuid"),
                    "trigger": _user_trigger(record),
                }
            if record.get("type") != "assistant":
                continue
            tokens = _usage_from_record(record)
            request_key = _request_key(record)
            timestamp = _parse_timestamp(record.get("timestamp"))
            if tokens is None or request_key is None or timestamp is None:
                continue
            if not any(
                tokens[field]
                for field in ("input", "output", "cache_read", "cache_create")
            ):
                continue
            message = record.get("message")
            model = message.get("model") if isinstance(message, dict) else None
            candidate = {
                "request_key": request_key,
                "timestamp": timestamp,
                "parent_uuid": record.get("parentUuid"),
                "session_id": record.get("sessionId")
                or record.get("session_id")
                or log_path.stem,
                "cwd": record.get("cwd"),
                "project": _project_name(record.get("cwd"), log_path),
                "model": model,
                "tokens": tokens,
                "is_subagent": is_subagent,
            }
            existing = requests.get(request_key)
            if existing is None:
                requests[request_key] = candidate
                continue
            existing["tokens"] = _merge_maximum_usage(
                existing["tokens"],
                tokens,
            )
            if timestamp < existing["timestamp"]:
                existing.update(
                    {
                        "timestamp": timestamp,
                        "parent_uuid": record.get("parentUuid"),
                        "cwd": record.get("cwd"),
                        "project": _project_name(record.get("cwd"), log_path),
                    }
                )

    for request in requests.values():
        request["trigger"] = (
            "subagent"
            if request["is_subagent"]
            else _trace_trigger(request["parent_uuid"], nodes)
        )
    return list(requests.values()), invalid_lines


def _add_tokens(total: Dict[str, int], tokens: Mapping[str, int]) -> None:
    for field in TOKEN_FIELDS:
        total[field] += tokens.get(field, 0)


def _add_cost(total: Dict[str, float], cost: Mapping[str, float]) -> None:
    for field in COST_FIELDS:
        total[field] += cost.get(field, 0.0)


def _group_row(
    groups: Dict[Any, Dict[str, Any]],
    key: Any,
    values: Mapping[str, Any],
) -> Dict[str, Any]:
    if key not in groups:
        groups[key] = {
            **values,
            "requests": 0,
            "tokens": _empty_tokens(),
            "cost": _empty_cost(),
        }
    return groups[key]


def _flatten_group(row: Mapping[str, Any]) -> Dict[str, Any]:
    tokens = row["tokens"]
    cost = row["cost"]
    return {
        **{
            key: value
            for key, value in row.items()
            if key not in ("tokens", "cost")
        },
        "cache_read_tokens": tokens["cache_read"],
        "cache_create_tokens": tokens["cache_create"],
        **{field: round(cost[field], 6) for field in COST_FIELDS},
    }


def _top_cache_events(
    requests: Iterable[Mapping[str, Any]],
    field: str,
    limit: int,
) -> List[Dict[str, Any]]:
    rows = sorted(
        requests,
        key=lambda request: request["tokens"][field],
        reverse=True,
    )[:limit]
    return [
        {
            "project": request["project"],
            "session_id": request["session_id"],
            "trigger": request["trigger"],
            "model": request["model"],
            "tokens": request["tokens"][field],
        }
        for request in rows
        if request["tokens"][field] > 0
    ]


def _build_findings(
    cache_read_share: float,
    five_minute_write_share: float,
    total_cost: Mapping[str, float],
    by_trigger: Sequence[Mapping[str, Any]],
    full_recache_count: int,
) -> List[str]:
    findings = []
    estimated_total_cost = total_cost["estimated_total_usd"]
    estimated_cache_cost = total_cost["estimated_cache_usd"]
    cache_cost_share = (
        100.0 * estimated_cache_cost / estimated_total_cost
        if estimated_total_cost
        else 0.0
    )
    monitor_row = next(
        (
            row
            for row in by_trigger
            if row.get("name") == "monitor_notification"
        ),
        None,
    )
    monitor_cost_share = (
        100.0 * monitor_row["estimated_total_usd"] / estimated_total_cost
        if monitor_row is not None and estimated_total_cost
        else 0.0
    )
    if monitor_cost_share >= 25:
        findings.append(
            "Monitor notifications account for {:.1f}% of estimated cost.".format(
                monitor_cost_share
            )
        )
    if five_minute_write_share >= 80:
        findings.append(
            "{:.1f}% of cache writes use the 5-minute tier; notification gaps "
            "longer than five minutes can force expensive recaches.".format(
                five_minute_write_share
            )
        )
    if cache_cost_share >= 75:
        findings.append(
            "Cache reads and writes account for {:.1f}% of estimated cost.".format(
                cache_cost_share
            )
        )
    if full_recache_count:
        findings.append(
            "{} request(s) rebuilt at least 100K cache tokens with little or no "
            "cache reuse.".format(full_recache_count)
        )
    if not findings and cache_read_share:
        findings.append(
            "No dominant cache anomaly crossed the diagnostic thresholds."
        )
    return findings


def analyze_logs(
    logs_directory: Path,
    start: datetime,
    end: datetime,
    top_limit: int = 5,
    window_label: Optional[str] = None,
) -> Dict[str, Any]:
    """Analyze unique Claude requests whose first record falls in [start, end)."""

    unique_requests: Dict[str, Dict[str, Any]] = {}
    files_scanned = 0
    invalid_lines = 0
    if logs_directory.exists():
        for log_path in logs_directory.rglob("*.jsonl"):
            try:
                if log_path.stat().st_mtime < start.timestamp():
                    continue
            except OSError:
                continue
            is_subagent = "subagents" in log_path.parts
            requests, file_invalid_lines = _read_log(log_path, is_subagent)
            files_scanned += 1
            invalid_lines += file_invalid_lines
            for request in requests:
                request_key = request["request_key"]
                existing = unique_requests.get(request_key)
                if existing is None:
                    unique_requests[request_key] = request
                else:
                    existing["tokens"] = _merge_maximum_usage(
                        existing["tokens"],
                        request["tokens"],
                    )

    requests = [
        request
        for request in unique_requests.values()
        if start <= request["timestamp"] < end
    ]
    total_tokens = _empty_tokens()
    total_cost = _empty_cost()
    priced_requests = 0
    trigger_groups: Dict[str, Dict[str, Any]] = {}
    session_groups: Dict[Any, Dict[str, Any]] = {}
    model_groups: Dict[Any, Dict[str, Any]] = {}

    for request in requests:
        tokens = request["tokens"]
        _add_tokens(total_tokens, tokens)
        cost = _request_cost(tokens, request["model"])
        if cost is not None:
            priced_requests += 1
            _add_cost(total_cost, cost)
        else:
            cost = _empty_cost()

        trigger_row = _group_row(
            trigger_groups,
            request["trigger"],
            {"name": request["trigger"]},
        )
        session_key = request["session_id"]
        session_row = _group_row(
            session_groups,
            session_key,
            {
                "session_id": request["session_id"],
                "project": request["project"],
                "cwd": request["cwd"],
            },
        )
        model_row = _group_row(
            model_groups,
            request["model"],
            {"model": request["model"]},
        )
        for row in (trigger_row, session_row, model_row):
            row["requests"] += 1
            _add_tokens(row["tokens"], tokens)
            _add_cost(row["cost"], cost)

    context_tokens = (
        total_tokens["input"]
        + total_tokens["cache_read"]
        + total_tokens["cache_create"]
    )
    cache_read_share = (
        100.0 * total_tokens["cache_read"] / context_tokens
        if context_tokens
        else 0.0
    )
    five_minute_write_share = (
        100.0 * total_tokens["cache_create_5m"] / total_tokens["cache_create"]
        if total_tokens["cache_create"]
        else 0.0
    )
    rounded_cache_read_share = round(cache_read_share, 2)
    rounded_five_minute_write_share = round(five_minute_write_share, 2)
    full_recaches = [
        request
        for request in requests
        if request["tokens"]["cache_create"] >= FULL_RECACHE_TOKENS
        and request["tokens"]["cache_read"]
        <= request["tokens"]["cache_create"] * FULL_RECACHE_MAX_READ_RATIO
    ]
    large_context_requests = [
        request
        for request in requests
        if request["tokens"]["cache_read"] >= LARGE_CACHE_READ_TOKENS
    ]

    by_trigger = sorted(
        (_flatten_group(row) for row in trigger_groups.values()),
        key=lambda row: (
            row["estimated_total_usd"],
            row["cache_create_tokens"],
            row["cache_read_tokens"],
        ),
        reverse=True,
    )
    top_sessions = sorted(
        (_flatten_group(row) for row in session_groups.values()),
        key=lambda row: (
            row["estimated_total_usd"],
            row["cache_create_tokens"],
            row["cache_read_tokens"],
        ),
        reverse=True,
    )[:top_limit]
    by_model = sorted(
        (_flatten_group(row) for row in model_groups.values()),
        key=lambda row: row["estimated_total_usd"],
        reverse=True,
    )
    findings = _build_findings(
        cache_read_share=rounded_cache_read_share,
        five_minute_write_share=rounded_five_minute_write_share,
        total_cost=total_cost,
        by_trigger=by_trigger,
        full_recache_count=len(full_recaches),
    )
    total_token_count = (
        total_tokens["input"]
        + total_tokens["output"]
        + total_tokens["cache_read"]
        + total_tokens["cache_create"]
    )

    return {
        "window": {
            "label": window_label
            or "{} to {}".format(_isoformat(start), _isoformat(end)),
            "start": _isoformat(start),
            "end": _isoformat(end),
        },
        "files_scanned": files_scanned,
        "invalid_lines": invalid_lines,
        "requests": len(requests),
        "tokens": {
            **total_tokens,
            "total": total_token_count,
        },
        "cache": {
            "read_share_percent": rounded_cache_read_share,
            "five_minute_write_percent": rounded_five_minute_write_share,
            "large_context_requests": len(large_context_requests),
            "full_recache_requests": len(full_recaches),
        },
        "cost": {
            **{field: round(total_cost[field], 6) for field in COST_FIELDS},
            "priced_requests": priced_requests,
            "unpriced_requests": len(requests) - priced_requests,
        },
        "by_trigger": by_trigger,
        "top_sessions": top_sessions,
        "by_model": by_model,
        "findings": findings,
        "largest_cache_reads": _top_cache_events(
            requests,
            "cache_read",
            top_limit,
        ),
        "largest_recaches": _top_cache_events(
            full_recaches,
            "cache_create",
            top_limit,
        ),
    }


def _format_tokens(value: Any) -> str:
    number = float(value) if isinstance(value, (int, float)) else 0.0
    for suffix, divisor in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if abs(number) >= divisor:
            return "{:.2f}{}".format(number / divisor, suffix)
    return str(int(number))


def _format_cost(value: Any) -> str:
    number = float(value) if isinstance(value, (int, float)) else 0.0
    return "${:,.2f}".format(number)


def render_cache_text(report: Mapping[str, Any]) -> str:
    tokens = report["tokens"]
    cache = report["cache"]
    cost = report["cost"]
    lines = [
        "Local traffic: {} ({} unique requests; {} tokens)".format(
            report["window"]["label"],
            report["requests"],
            _format_tokens(tokens["total"]),
        ),
        "Cache read: {} ({:.1f}% of context; est. {})".format(
            _format_tokens(tokens["cache_read"]),
            cache["read_share_percent"],
            _format_cost(cost["estimated_cache_read_usd"]),
        ),
        (
            "Cache writes: {} — 5-minute writes {} ({:.1f}%), "
            "1-hour writes {} (est. {} total)"
        ).format(
            _format_tokens(tokens["cache_create"]),
            _format_tokens(tokens["cache_create_5m"]),
            cache["five_minute_write_percent"],
            _format_tokens(tokens["cache_create_1h"]),
            _format_cost(
                cost["estimated_cache_write_5m_usd"]
                + cost["estimated_cache_write_1h_usd"]
            ),
        ),
        "Estimated cache cost: {} of {} total".format(
            _format_cost(cost["estimated_cache_usd"]),
            _format_cost(cost["estimated_total_usd"]),
        ),
        "Large rereads (>=150K): {} | Full recaches (>=100K): {}".format(
            cache["large_context_requests"],
            cache["full_recache_requests"],
        ),
    ]
    findings = report.get("findings")
    if isinstance(findings, list) and findings:
        lines.append("Findings:")
        lines.extend("  - {}".format(finding) for finding in findings)
    lines.append("Trigger attribution:")
    for row in report["by_trigger"]:
        lines.append(
            "  {}: {} req | read {} | write {} | est. {}".format(
                TRIGGER_LABELS.get(row["name"], row["name"]),
                row["requests"],
                _format_tokens(row.get("cache_read_tokens", 0)),
                _format_tokens(row.get("cache_create_tokens", 0)),
                _format_cost(
                    row.get(
                        "estimated_total_usd",
                        row.get("estimated_cost_usd", 0),
                    )
                ),
            )
        )
    lines.append("Top sessions:")
    for row in report["top_sessions"]:
        lines.append(
            "  {} [{}]: {} req | read {} | write {} | est. {}".format(
                row["project"],
                str(row["session_id"])[:8],
                row["requests"],
                _format_tokens(row.get("cache_read_tokens", 0)),
                _format_tokens(row.get("cache_create_tokens", 0)),
                _format_cost(
                    row.get(
                        "estimated_total_usd",
                        row.get("estimated_cost_usd", 0),
                    )
                ),
            )
        )
    if cost["unpriced_requests"]:
        lines.append(
            "Pricing warning: {} request(s) used an unknown model and are excluded "
            "from cost estimates.".format(cost["unpriced_requests"])
        )
    lines.append(
        "Cost note: estimates use known API token rates; actual plan credits may differ."
    )
    return "\n".join(lines)
