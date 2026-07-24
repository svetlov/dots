#!/usr/bin/env python3
"""Report Claude Code plan limits and extra-usage billing without model calls."""

import argparse
import errno
import json
import os
import pty
import select
import shutil
import struct
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any, Dict, Mapping, Optional, Sequence

try:
    from claude_cache_analysis import analyze_logs, render_cache_text
except ModuleNotFoundError:
    from scripts.claude_cache_analysis import analyze_logs, render_cache_text

try:
    import fcntl
    import termios
except ImportError:  # pragma: no cover - the PTY refresh is Unix-only
    fcntl = None
    termios = None


DEFAULT_CONFIG_PATH = Path.home() / ".claude.json"
DEFAULT_LOGS_DIRECTORY = Path.home() / ".claude" / "projects"
DEFAULT_REFRESH_TIMEOUT_SECONDS = 20.0
RECENT_CACHE_SECONDS = 30
EXIT_TIMEOUT_SECONDS = 5.0
PTY_ROWS = 24
PTY_COLUMNS = 80


class DiagnosticError(RuntimeError):
    """Raised when the diagnostic cannot produce a trustworthy result."""


@dataclass(frozen=True)
class RefreshResult:
    refreshed: bool
    message: str


def load_json(path: Path) -> Dict[str, Any]:
    try:
        with path.open(encoding="utf-8") as stream:
            value = json.load(stream)
    except FileNotFoundError as error:
        raise DiagnosticError("Claude usage cache not found: {}".format(path)) from error
    except json.JSONDecodeError as error:
        raise DiagnosticError("Claude usage cache is invalid JSON: {}".format(path)) from error

    if not isinstance(value, dict):
        raise DiagnosticError("Claude usage cache must contain a JSON object")
    return value


def _load_fetched_at_ms(path: Path) -> int:
    try:
        config = load_json(path)
    except DiagnosticError:
        return 0
    usage_cache = config.get("cachedUsageUtilization")
    if not isinstance(usage_cache, dict):
        return 0
    fetched_at_ms = usage_cache.get("fetchedAtMs")
    if isinstance(fetched_at_ms, (int, float)):
        return int(fetched_at_ms)
    return 0


def _set_pty_size(file_descriptor: int) -> None:
    if fcntl is None or termios is None:
        return
    window_size = struct.pack("HHHH", PTY_ROWS, PTY_COLUMNS, 0, 0)
    fcntl.ioctl(file_descriptor, termios.TIOCSWINSZ, window_size)


def _read_pty(file_descriptor: int) -> bytes:
    try:
        return os.read(file_descriptor, 8192)
    except OSError as error:
        if error.errno == errno.EIO:
            return b""
        raise


def _drain_until_exit(
    process: subprocess.Popen,
    master_file_descriptor: int,
    timeout_seconds: float,
) -> bool:
    deadline = time.monotonic() + timeout_seconds
    while process.poll() is None and time.monotonic() < deadline:
        readable, _, _ = select.select([master_file_descriptor], [], [], 0.1)
        if readable:
            _read_pty(master_file_descriptor)
    return process.poll() is not None


def _close_claude_session(
    process: subprocess.Popen,
    master_file_descriptor: int,
) -> None:
    if process.poll() is not None:
        return

    os.write(master_file_descriptor, b"\x1b")
    time.sleep(0.15)
    os.write(master_file_descriptor, b"/exit\r")
    if _drain_until_exit(process, master_file_descriptor, EXIT_TIMEOUT_SECONDS):
        return

    # This only cleans up the child created by this diagnostic. No unrelated
    # Claude process is inspected or signalled.
    os.write(master_file_descriptor, b"\x03")
    if _drain_until_exit(process, master_file_descriptor, 1.0):
        return
    process.terminate()
    try:
        process.wait(timeout=1.0)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=1.0)


def refresh_usage_cache(
    claude_binary: str,
    config_path: Path,
    working_directory: Path,
    environment: Mapping[str, str],
    timeout_seconds: float = DEFAULT_REFRESH_TIMEOUT_SECONDS,
) -> RefreshResult:
    """Refresh Claude's local usage cache through the zero-token /usage command."""

    previous_fetched_at_ms = _load_fetched_at_ms(config_path)
    refresh_started_at_ms = int(time.time() * 1000)
    master_file_descriptor, slave_file_descriptor = pty.openpty()
    _set_pty_size(slave_file_descriptor)

    child_environment = dict(environment)
    child_environment.setdefault("TERM", "xterm-256color")
    process = subprocess.Popen(
        [claude_binary, "--safe-mode"],
        stdin=slave_file_descriptor,
        stdout=slave_file_descriptor,
        stderr=slave_file_descriptor,
        cwd=str(working_directory),
        env=child_environment,
        close_fds=True,
    )
    os.close(slave_file_descriptor)

    usage_command_sent = False
    output = bytearray()
    deadline = time.monotonic() + timeout_seconds
    refreshed = False
    message = "Claude /usage did not refresh the local cache"

    try:
        while time.monotonic() < deadline:
            readable, _, _ = select.select([master_file_descriptor], [], [], 0.1)
            if readable:
                chunk = _read_pty(master_file_descriptor)
                if chunk:
                    output.extend(chunk)
                    if len(output) > 32768:
                        del output[:-16384]

            output_text = output.decode("utf-8", errors="ignore")
            startup_elapsed = timeout_seconds - max(0.0, deadline - time.monotonic())
            prompt_is_ready = "Try" in output_text or startup_elapsed >= 2.0
            if not usage_command_sent and prompt_is_ready:
                os.write(master_file_descriptor, b"/usage\r")
                usage_command_sent = True

            if usage_command_sent:
                fetched_at_ms = _load_fetched_at_ms(config_path)
                cache_changed = fetched_at_ms > previous_fetched_at_ms
                cache_is_current = fetched_at_ms >= refresh_started_at_ms - 5000
                if cache_changed and cache_is_current:
                    refreshed = True
                    message = "live usage cache refreshed through /usage"
                    break

            if process.poll() is not None:
                message = "Claude exited before /usage refreshed the local cache"
                break
    finally:
        _close_claude_session(process, master_file_descriptor)
        os.close(master_file_descriptor)

    return RefreshResult(refreshed=refreshed, message=message)


def read_auth_status(claude_binary: str) -> Dict[str, Any]:
    """Read Claude auth metadata; stdout is captured and never printed raw."""

    try:
        result = subprocess.run(
            [claude_binary, "auth", "status", "--json"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {}

    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}
    return payload if isinstance(payload, dict) else {}


def _find_limit(limits: Sequence[Any], kind: str) -> Dict[str, Any]:
    for limit in limits:
        if isinstance(limit, dict) and limit.get("kind") == kind:
            return limit
    return {}


def _minor_units_to_number(amount: Any, decimal_places: Any) -> float:
    try:
        amount_decimal = Decimal(str(amount))
        places = int(decimal_places)
    except (ValueError, TypeError):
        return 0.0
    scale = Decimal(10) ** places
    return float(amount_decimal / scale)


def _number(value: Any, default: float = 0.0) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    return default


def _boolean_environment_flag(environment: Mapping[str, str], name: str) -> bool:
    value = environment.get(name)
    return value is not None and value != ""


def _isoformat_utc(date_time: datetime) -> str:
    return date_time.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def build_report(
    config: Mapping[str, Any],
    auth_status: Mapping[str, Any],
    environment: Mapping[str, str],
    now: datetime,
    refresh_result: Optional[RefreshResult] = None,
    ccusage_summary: Optional[Mapping[str, Any]] = None,
    local_usage: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    usage_cache = config.get("cachedUsageUtilization")
    if not isinstance(usage_cache, dict):
        raise DiagnosticError("cachedUsageUtilization is missing from Claude config")
    utilization = usage_cache.get("utilization")
    if not isinstance(utilization, dict):
        raise DiagnosticError("Claude usage utilization is missing from the cache")

    fetched_at_ms_value = usage_cache.get("fetchedAtMs")
    if not isinstance(fetched_at_ms_value, (int, float)):
        raise DiagnosticError("Claude usage cache has no refresh timestamp")
    fetched_at_ms = int(fetched_at_ms_value)
    fetched_at = datetime.fromtimestamp(fetched_at_ms / 1000, tz=timezone.utc)
    age_seconds = max(0, int((now.timestamp() * 1000 - fetched_at_ms) / 1000))

    raw_limits = utilization.get("limits")
    limits = raw_limits if isinstance(raw_limits, list) else []
    weekly_limit = _find_limit(limits, "weekly_all")
    fable_limit = _find_limit(limits, "weekly_scoped")

    five_hour = utilization.get("five_hour")
    if not isinstance(five_hour, dict):
        five_hour = {}
    seven_day = utilization.get("seven_day")
    if not isinstance(seven_day, dict):
        seven_day = {}
    extra_usage = utilization.get("extra_usage")
    if not isinstance(extra_usage, dict):
        extra_usage = {}

    weekly_percent = _number(
        weekly_limit.get("percent"),
        _number(seven_day.get("utilization")),
    )
    weekly_reset = weekly_limit.get("resets_at") or seven_day.get("resets_at")
    weekly_exhausted = weekly_percent >= 100 or (
        weekly_limit.get("is_active") is True
        and weekly_limit.get("severity") == "critical"
    )

    decimal_places = extra_usage.get("decimal_places", 2)
    spent = _minor_units_to_number(
        extra_usage.get("used_credits", 0),
        decimal_places,
    )
    spending_limit = _minor_units_to_number(
        extra_usage.get("monthly_limit", 0),
        decimal_places,
    )
    try:
        money_decimal_places = int(decimal_places)
    except (ValueError, TypeError):
        money_decimal_places = 2
    remaining = round(
        max(0.0, spending_limit - spent),
        money_decimal_places,
    )
    extra_usage_enabled = (
        extra_usage.get("is_enabled") is True
        and extra_usage.get("user_disabled") is not True
    )
    spend_limit_reached = extra_usage.get("spend_limit_reached") is True

    api_key_environment_set = _boolean_environment_flag(
        environment, "ANTHROPIC_API_KEY"
    )
    auth_token_environment_set = _boolean_environment_flag(
        environment, "ANTHROPIC_AUTH_TOKEN"
    )
    third_party_provider = any(
        _boolean_environment_flag(environment, name)
        for name in (
            "CLAUDE_CODE_USE_BEDROCK",
            "CLAUDE_CODE_USE_VERTEX",
            "CLAUDE_CODE_USE_FOUNDRY",
        )
    )
    auth_method = auth_status.get("authMethod")
    if (
        api_key_environment_set
        or auth_token_environment_set
        or auth_method in ("apiKey", "api_key")
    ):
        billing_route = "api_key"
    elif third_party_provider:
        billing_route = "third_party_provider"
    elif auth_method == "claude.ai":
        billing_route = "subscription"
    else:
        billing_route = "unknown"

    using_extra_usage_now = (
        billing_route == "subscription"
        and weekly_exhausted
        and extra_usage_enabled
        and not spend_limit_reached
    )
    can_continue = (
        not weekly_exhausted
        or billing_route in ("api_key", "third_party_provider")
        or (extra_usage_enabled and not spend_limit_reached)
    )

    report: Dict[str, Any] = {
        "generated_at": _isoformat_utc(now),
        "status": {
            "billing_route": billing_route,
            "weekly_included_limit_exhausted": weekly_exhausted,
            "using_extra_usage_now": using_extra_usage_now,
            "can_continue": can_continue,
        },
        "authentication": {
            "logged_in": auth_status.get("loggedIn") is True,
            "method": auth_method,
            "api_provider": auth_status.get("apiProvider"),
            "subscription_type": auth_status.get("subscriptionType"),
            "api_key_environment_set": api_key_environment_set,
            "auth_token_environment_set": auth_token_environment_set,
            "third_party_provider_environment_set": third_party_provider,
        },
        "usage": {
            "five_hour": {
                "percent": _number(five_hour.get("utilization")),
                "resets_at": five_hour.get("resets_at"),
            },
            "weekly_all": {
                "percent": weekly_percent,
                "resets_at": weekly_reset,
                "active_limit": weekly_limit.get("is_active") is True,
                "severity": weekly_limit.get("severity"),
            },
            "fable": {
                "percent": _number(fable_limit.get("percent")),
                "resets_at": fable_limit.get("resets_at"),
                "active_limit": fable_limit.get("is_active") is True,
            },
        },
        "extra_usage": {
            "enabled": extra_usage_enabled,
            "spent": spent,
            "limit": spending_limit,
            "remaining": remaining,
            "percent": _number(extra_usage.get("utilization")),
            "currency": extra_usage.get("currency"),
            "spend_limit_reached": spend_limit_reached,
        },
        "cache": {
            "fetched_at": _isoformat_utc(fetched_at),
            "age_seconds": age_seconds,
            "refresh_attempted": refresh_result is not None,
            "refresh_succeeded": (
                refresh_result.refreshed if refresh_result is not None else None
            ),
            "refresh_message": (
                refresh_result.message if refresh_result is not None else None
            ),
        },
        "cache_policy": {
            "force_5m": _boolean_environment_flag(
                environment, "FORCE_PROMPT_CACHING_5M"
            ),
            "enable_1h": _boolean_environment_flag(
                environment, "ENABLE_PROMPT_CACHING_1H"
            ),
        },
    }
    if ccusage_summary is not None:
        report["ccusage"] = dict(ccusage_summary)
    if local_usage is not None:
        report["local_usage"] = dict(local_usage)
    return report


def _format_percent(value: Any) -> str:
    number = _number(value)
    if number.is_integer():
        return "{}%".format(int(number))
    return "{:.1f}%".format(number)


def _format_money(value: Any, currency: Any) -> str:
    amount = _number(value)
    if currency == "USD":
        return "${:,.2f}".format(amount)
    return "{} {:,.2f}".format(currency or "currency", amount)


def _format_reset(value: Any) -> str:
    if not isinstance(value, str) or not value:
        return "not reported"
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return value
    local = parsed.astimezone()
    return local.strftime("%Y-%m-%d %H:%M %Z")


def render_text(report: Mapping[str, Any]) -> str:
    status = report["status"]
    authentication = report["authentication"]
    usage = report["usage"]
    extra_usage = report["extra_usage"]
    cache = report["cache"]
    cache_policy = report["cache_policy"]

    if status["using_extra_usage_now"]:
        billing_line = "YES — using extra-usage credits"
    elif status["billing_route"] == "api_key":
        billing_line = "NO — API-key billing is active"
    elif status["billing_route"] == "third_party_provider":
        billing_line = "NO — third-party provider billing is active"
    elif (
        status["weekly_included_limit_exhausted"]
        and extra_usage["spend_limit_reached"]
    ):
        billing_line = "NO — the extra-usage spend limit has been reached"
    elif status["weekly_included_limit_exhausted"] and not extra_usage["enabled"]:
        billing_line = "NO — weekly allowance exhausted; extra usage is disabled"
    elif status["billing_route"] == "unknown":
        billing_line = "UNKNOWN — authentication route could not be confirmed"
    else:
        billing_line = "NO — included plan allowance is still available"

    subscription_type = authentication.get("subscription_type")
    if isinstance(subscription_type, str) and subscription_type:
        account = "Claude {}".format(subscription_type.title())
    else:
        account = "Claude account type unknown"

    force_5m = cache_policy["force_5m"]
    enable_1h = cache_policy["enable_1h"]
    if force_5m:
        cache_policy_text = "FORCE_PROMPT_CACHING_5M is set"
    elif enable_1h:
        cache_policy_text = "ENABLE_PROMPT_CACHING_1H is set"
    else:
        cache_policy_text = "no prompt-cache TTL override"

    lines = [
        "Billing now: {}".format(billing_line),
        "Account: {} (method: {}; provider: {})".format(
            account,
            authentication.get("method") or "unknown",
            authentication.get("api_provider") or "unknown",
        ),
        "Weekly, all models: {} used; resets {}".format(
            _format_percent(usage["weekly_all"]["percent"]),
            _format_reset(usage["weekly_all"]["resets_at"]),
        ),
        "Five-hour/session: {} used; resets {}".format(
            _format_percent(usage["five_hour"]["percent"]),
            _format_reset(usage["five_hour"]["resets_at"]),
        ),
        "Weekly, Fable: {} used; resets {}".format(
            _format_percent(usage["fable"]["percent"]),
            _format_reset(usage["fable"]["resets_at"]),
        ),
        "Extra usage: {} of {} ({}); {} remaining".format(
            _format_money(extra_usage["spent"], extra_usage["currency"]),
            _format_money(extra_usage["limit"], extra_usage["currency"]),
            _format_percent(extra_usage["percent"]),
            _format_money(extra_usage["remaining"], extra_usage["currency"]),
        ),
        "Usage cache: {} ({}s old; {})".format(
            cache["fetched_at"],
            cache["age_seconds"],
            cache.get("refresh_message") or "cached read",
        ),
        "Prompt caching: {}".format(cache_policy_text),
        "Safety: /usage and /exit only; zero model prompts submitted.",
    ]

    ccusage = report.get("ccusage")
    if isinstance(ccusage, dict):
        lines.extend(
            [
                "ccusage, local Claude week {}: {} API-equivalent".format(
                    ccusage["period"],
                    _format_money(ccusage["api_equivalent_cost"], "USD"),
                ),
                (
                    "Note: ccusage is an API-price estimate for the local week; "
                    "extra usage is the account billing-period spend."
                ),
            ]
        )
    local_usage = report.get("local_usage")
    if isinstance(local_usage, dict):
        lines.extend(["", render_cache_text(local_usage)])
    return "\n".join(lines)


def summarize_ccusage(payload: Mapping[str, Any]) -> Dict[str, Any]:
    raw_weeks = payload.get("weekly")
    if not isinstance(raw_weeks, list) or not raw_weeks:
        raise DiagnosticError("ccusage returned no weekly rows")
    weeks = [week for week in raw_weeks if isinstance(week, dict)]
    if not weeks:
        raise DiagnosticError("ccusage returned no valid weekly rows")
    current_week = max(weeks, key=lambda week: str(week.get("period", "")))
    raw_breakdowns = current_week.get("modelBreakdowns")
    breakdowns = raw_breakdowns if isinstance(raw_breakdowns, list) else []
    claude_breakdowns = [
        breakdown
        for breakdown in breakdowns
        if isinstance(breakdown, dict)
        and str(breakdown.get("modelName", "")).startswith("claude-")
    ]
    if not claude_breakdowns:
        raise DiagnosticError("ccusage current week has no Claude model data")

    def sum_field(field: str) -> float:
        return sum(_number(breakdown.get(field)) for breakdown in claude_breakdowns)

    input_tokens = int(sum_field("inputTokens"))
    output_tokens = int(sum_field("outputTokens"))
    cache_creation_tokens = int(sum_field("cacheCreationTokens"))
    cache_read_tokens = int(sum_field("cacheReadTokens"))
    return {
        "period": current_week.get("period"),
        "api_equivalent_cost": sum_field("cost"),
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "cache_creation_tokens": cache_creation_tokens,
        "cache_read_tokens": cache_read_tokens,
        "total_tokens": (
            input_tokens
            + output_tokens
            + cache_creation_tokens
            + cache_read_tokens
        ),
    }


def read_ccusage() -> Dict[str, Any]:
    ccusage_binary = shutil.which("ccusage")
    if ccusage_binary:
        command = [ccusage_binary, "weekly", "--json", "--offline"]
    else:
        npx_binary = shutil.which("npx")
        if not npx_binary:
            raise DiagnosticError("neither ccusage nor npx is installed")
        command = [
            npx_binary,
            "ccusage@latest",
            "weekly",
            "--json",
            "--offline",
        ]

    try:
        result = subprocess.run(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise DiagnosticError("ccusage could not be executed") from error
    if result.returncode != 0:
        raise DiagnosticError(
            "ccusage failed: {}".format(result.stderr.strip() or "unknown error")
        )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise DiagnosticError("ccusage did not return valid JSON") from error
    if not isinstance(payload, dict):
        raise DiagnosticError("ccusage JSON must contain an object")
    return summarize_ccusage(payload)


def _cache_age_seconds(config: Mapping[str, Any], now: datetime) -> Optional[int]:
    usage_cache = config.get("cachedUsageUtilization")
    if not isinstance(usage_cache, dict):
        return None
    fetched_at_ms = usage_cache.get("fetchedAtMs")
    if not isinstance(fetched_at_ms, (int, float)):
        return None
    return max(0, int((now.timestamp() * 1000 - fetched_at_ms) / 1000))


def _positive_float(value: str) -> float:
    number = float(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


def _positive_integer(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


def _local_analysis_window(
    now: datetime,
    hours: Optional[float],
) -> tuple:
    local_now = now.astimezone()
    if hours is not None:
        unit = "hour" if hours == 1 else "hours"
        label = "last {:g} {}".format(hours, unit)
        return local_now - timedelta(hours=hours), local_now, label
    local_midnight = local_now.replace(hour=0, minute=0, second=0, microsecond=0)
    return local_midnight, local_now, "today"


def parse_arguments(arguments: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Show Claude plan limits and extra-usage billing without sending "
            "a model prompt."
        )
    )
    parser.add_argument(
        "--no-refresh",
        action="store_true",
        help="read the existing local usage cache without opening Claude /usage",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="emit a redacted machine-readable report",
    )
    parser.add_argument(
        "--ccusage",
        action="store_true",
        help="include the local week's Claude API-equivalent ccusage estimate",
    )
    parser.add_argument(
        "--hours",
        type=_positive_float,
        help="analyze local cache traffic over the last N hours instead of today",
    )
    parser.add_argument(
        "--top-sessions",
        type=_positive_integer,
        default=5,
        help="number of expensive sessions to show (default: 5)",
    )
    parser.add_argument(
        "--no-log-analysis",
        action="store_true",
        help="skip local JSONL cache and trigger analysis",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG_PATH,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--logs-directory",
        type=Path,
        default=DEFAULT_LOGS_DIRECTORY,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--refresh-timeout",
        type=float,
        default=DEFAULT_REFRESH_TIMEOUT_SECONDS,
        help=argparse.SUPPRESS,
    )
    return parser.parse_args(arguments)


def main(arguments: Optional[Sequence[str]] = None) -> int:
    options = parse_arguments(arguments)
    config_path = options.config.expanduser()
    claude_binary = shutil.which("claude")
    if not claude_binary:
        print("error: Claude Code is not installed or not on PATH", file=sys.stderr)
        return 1

    refresh_result: Optional[RefreshResult] = None
    refresh_failed = False
    try:
        initial_config = load_json(config_path)
        initial_age_seconds = _cache_age_seconds(
            initial_config,
            datetime.now(timezone.utc),
        )
        if not options.no_refresh:
            if (
                initial_age_seconds is not None
                and initial_age_seconds <= RECENT_CACHE_SECONDS
            ):
                refresh_result = RefreshResult(
                    refreshed=True,
                    message="usage cache was already fresh",
                )
            else:
                script_root = Path(__file__).resolve().parent.parent
                refresh_result = refresh_usage_cache(
                    claude_binary=claude_binary,
                    config_path=config_path,
                    working_directory=script_root,
                    environment=os.environ,
                    timeout_seconds=options.refresh_timeout,
                )
                refresh_failed = not refresh_result.refreshed

        config = load_json(config_path)
        auth_status = read_auth_status(claude_binary)
        ccusage_summary = read_ccusage() if options.ccusage else None
        report_time = datetime.now(timezone.utc)
        local_usage = None
        if not options.no_log_analysis:
            analysis_start, analysis_end, window_label = _local_analysis_window(
                report_time,
                options.hours,
            )
            local_usage = analyze_logs(
                logs_directory=options.logs_directory.expanduser(),
                start=analysis_start,
                end=analysis_end,
                top_limit=options.top_sessions,
                window_label=window_label,
            )
        report = build_report(
            config=config,
            auth_status=auth_status,
            environment=os.environ,
            now=report_time,
            refresh_result=refresh_result,
            ccusage_summary=ccusage_summary,
            local_usage=local_usage,
        )
    except DiagnosticError as error:
        print("error: {}".format(error), file=sys.stderr)
        return 1

    if options.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(render_text(report))
    if refresh_failed:
        print(
            "warning: live refresh failed; values above may be stale",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
