import importlib.util
import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "claude_cache_analysis.py"
MODULE_SPEC = importlib.util.spec_from_file_location(
    "claude_cache_analysis",
    MODULE_PATH,
)
claude_cache_analysis = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(claude_cache_analysis)


def user_record(uuid, parent_uuid, timestamp, content, cwd):
    return {
        "type": "user",
        "uuid": uuid,
        "parentUuid": parent_uuid,
        "timestamp": timestamp,
        "cwd": cwd,
        "message": {"content": content},
    }


def assistant_record(
    uuid,
    parent_uuid,
    request_id,
    timestamp,
    cwd,
    *,
    input_tokens=1,
    output_tokens=1,
    cache_read_tokens=0,
    cache_create_5m_tokens=0,
    cache_create_1h_tokens=0,
    model="claude-opus-4-8",
):
    cache_create_tokens = cache_create_5m_tokens + cache_create_1h_tokens
    return {
        "type": "assistant",
        "uuid": uuid,
        "parentUuid": parent_uuid,
        "requestId": request_id,
        "sessionId": "session-1",
        "timestamp": timestamp,
        "cwd": cwd,
        "message": {
            "id": "message-{}".format(request_id),
            "model": model,
            "usage": {
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "cache_read_input_tokens": cache_read_tokens,
                "cache_creation_input_tokens": cache_create_tokens,
                "cache_creation": {
                    "ephemeral_5m_input_tokens": cache_create_5m_tokens,
                    "ephemeral_1h_input_tokens": cache_create_1h_tokens,
                },
            },
        },
    }


def write_jsonl(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as stream:
        for record in records:
            stream.write(json.dumps(record))
            stream.write("\n")


class CacheAnalysisTests(unittest.TestCase):
    def test_deduplicates_requests_and_attributes_causal_triggers(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            logs_directory = Path(temporary_directory) / "projects"
            project_directory = logs_directory / "project-a"
            main_log = project_directory / "session-1.jsonl"
            cwd = "/workspace/project-a"

            records = [
                user_record(
                    "human-1",
                    None,
                    "2026-07-23T09:00:00Z",
                    "secret human prompt",
                    cwd,
                ),
                assistant_record(
                    "assistant-1a",
                    "human-1",
                    "request-1",
                    "2026-07-23T09:00:01Z",
                    cwd,
                    input_tokens=2,
                    output_tokens=50,
                    cache_create_1h_tokens=100_000,
                ),
                assistant_record(
                    "assistant-1b",
                    "assistant-1a",
                    "request-1",
                    "2026-07-23T09:00:02Z",
                    cwd,
                    input_tokens=2,
                    output_tokens=60,
                    cache_create_1h_tokens=100_000,
                ),
                user_record(
                    "monitor-1",
                    "assistant-1b",
                    "2026-07-23T10:00:00Z",
                    (
                        "<task-notification><summary>Monitor event: "
                        '"training watch"</summary></task-notification>'
                    ),
                    cwd,
                ),
                assistant_record(
                    "assistant-2",
                    "monitor-1",
                    "request-2",
                    "2026-07-23T10:00:01Z",
                    cwd,
                    output_tokens=20,
                    cache_read_tokens=200_000,
                    cache_create_5m_tokens=1_000,
                ),
                user_record(
                    "tool-result-1",
                    "assistant-2",
                    "2026-07-23T10:00:02Z",
                    [{"type": "tool_result", "content": "internal result"}],
                    cwd,
                ),
                assistant_record(
                    "assistant-3",
                    "tool-result-1",
                    "request-3",
                    "2026-07-23T10:00:03Z",
                    cwd,
                    output_tokens=10,
                    cache_read_tokens=250_000,
                    cache_create_5m_tokens=500,
                ),
                user_record(
                    "agent-notification-1",
                    "assistant-3",
                    "2026-07-23T11:00:00Z",
                    (
                        "<task-notification><summary>Agent "
                        '"reviewer" finished</summary></task-notification>'
                    ),
                    cwd,
                ),
                assistant_record(
                    "assistant-4",
                    "agent-notification-1",
                    "request-4",
                    "2026-07-23T11:00:01Z",
                    cwd,
                    output_tokens=5,
                    cache_read_tokens=20_000,
                    cache_create_5m_tokens=100,
                ),
                assistant_record(
                    "old-assistant",
                    None,
                    "old-request",
                    "2026-07-22T10:00:00Z",
                    cwd,
                    cache_read_tokens=999_999,
                ),
            ]
            write_jsonl(main_log, records)

            subagent_log = (
                project_directory
                / "session-1"
                / "subagents"
                / "agent-test.jsonl"
            )
            write_jsonl(
                subagent_log,
                [
                    assistant_record(
                        "subagent-assistant",
                        None,
                        "request-5",
                        "2026-07-23T12:00:00Z",
                        cwd,
                        output_tokens=5,
                        cache_read_tokens=50_000,
                        cache_create_5m_tokens=200,
                    )
                ],
            )

            result = claude_cache_analysis.analyze_logs(
                logs_directory=logs_directory,
                start=datetime(2026, 7, 23, tzinfo=timezone.utc),
                end=datetime(2026, 7, 24, tzinfo=timezone.utc),
                top_limit=5,
            )

        self.assertEqual(result["requests"], 5)
        self.assertEqual(result["tokens"]["input"], 6)
        self.assertEqual(result["tokens"]["output"], 100)
        self.assertEqual(result["tokens"]["cache_read"], 520_000)
        self.assertEqual(result["tokens"]["cache_create"], 101_800)
        self.assertEqual(result["tokens"]["cache_create_5m"], 1_800)
        self.assertEqual(result["tokens"]["cache_create_1h"], 100_000)
        self.assertEqual(result["tokens"]["total"], 621_906)
        self.assertEqual(result["cache"]["large_context_requests"], 2)
        self.assertEqual(result["cache"]["full_recache_requests"], 1)
        self.assertAlmostEqual(
            result["cost"]["estimated_cache_read_usd"],
            0.26,
        )
        self.assertAlmostEqual(
            result["cost"]["estimated_cache_write_5m_usd"],
            0.01125,
        )
        self.assertAlmostEqual(
            result["cost"]["estimated_cache_write_1h_usd"],
            1.0,
        )
        self.assertAlmostEqual(
            result["cost"]["estimated_cache_usd"],
            1.27125,
        )
        self.assertEqual(result["cost"]["unpriced_requests"], 0)
        self.assertTrue(
            any(
                "Cache reads and writes" in finding
                for finding in result["findings"]
            )
        )

        by_trigger = {
            row["name"]: row for row in result["by_trigger"]
        }
        self.assertEqual(by_trigger["human"]["requests"], 1)
        self.assertEqual(by_trigger["monitor_notification"]["requests"], 2)
        self.assertEqual(
            by_trigger["subagent_completion_notification"]["requests"],
            1,
        )
        self.assertEqual(by_trigger["subagent"]["requests"], 1)
        self.assertEqual(result["top_sessions"][0]["project"], "project-a")
        self.assertNotIn("secret human prompt", json.dumps(result))

    def test_unknown_models_are_counted_but_not_assigned_a_cost(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            logs_directory = Path(temporary_directory) / "projects"
            log_path = logs_directory / "unknown-project" / "session.jsonl"
            write_jsonl(
                log_path,
                [
                    assistant_record(
                        "assistant",
                        None,
                        "unknown-request",
                        "2026-07-23T12:00:00Z",
                        "/workspace/unknown-project",
                        cache_read_tokens=10_000,
                        model="claude-future-unknown",
                    )
                ],
            )

            result = claude_cache_analysis.analyze_logs(
                logs_directory=logs_directory,
                start=datetime(2026, 7, 23, tzinfo=timezone.utc),
                end=datetime(2026, 7, 24, tzinfo=timezone.utc),
            )

        self.assertEqual(result["requests"], 1)
        self.assertEqual(result["cost"]["priced_requests"], 0)
        self.assertEqual(result["cost"]["unpriced_requests"], 1)
        self.assertEqual(result["cost"]["estimated_total_usd"], 0)

    def test_text_report_surfaces_cache_and_monitor_findings(self):
        result = {
            "window": {
                "label": "today",
                "start": "2026-07-23T00:00:00Z",
                "end": "2026-07-24T00:00:00Z",
            },
            "requests": 10,
            "tokens": {
                "input": 10,
                "output": 20,
                "cache_read": 2_000_000,
                "cache_create": 1_000_000,
                "cache_create_5m": 900_000,
                "cache_create_1h": 100_000,
                "total": 3_000_030,
            },
            "cache": {
                "read_share_percent": 66.7,
                "five_minute_write_percent": 90.0,
                "large_context_requests": 4,
                "full_recache_requests": 2,
            },
            "cost": {
                "estimated_total_usd": 8.0,
                "estimated_cache_usd": 7.0,
                "estimated_cache_read_usd": 1.0,
                "estimated_cache_write_5m_usd": 5.0,
                "estimated_cache_write_1h_usd": 1.0,
                "priced_requests": 10,
                "unpriced_requests": 0,
            },
            "by_trigger": [
                {
                    "name": "monitor_notification",
                    "requests": 7,
                    "estimated_cost_usd": 6.0,
                },
                {
                    "name": "human",
                    "requests": 3,
                    "estimated_cost_usd": 2.0,
                },
            ],
            "top_sessions": [
                {
                    "project": "expensive-project",
                    "session_id": "session-1",
                    "requests": 7,
                    "estimated_cost_usd": 6.0,
                }
            ],
        }

        output = claude_cache_analysis.render_cache_text(result)

        self.assertIn("Local traffic: today", output)
        self.assertIn("Cache read", output)
        self.assertIn("5-minute writes", output)
        self.assertIn("Full recaches", output)
        self.assertIn("Monitor notifications", output)
        self.assertIn("expensive-project", output)


if __name__ == "__main__":
    unittest.main()
