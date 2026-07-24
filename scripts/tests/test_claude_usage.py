import importlib.util
import json
import os
import tempfile
import textwrap
import unittest
from datetime import datetime, timezone
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "claude_usage.py"
MODULE_SPEC = importlib.util.spec_from_file_location("claude_usage", MODULE_PATH)
claude_usage = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(claude_usage)


def usage_config():
    fetched_at = datetime(2026, 7, 23, 11, 49, 17, tzinfo=timezone.utc)
    return {
        "oauthAccount": {
            "emailAddress": "secret@example.com",
            "accountUuid": "secret-account-id",
        },
        "cachedUsageUtilization": {
            "fetchedAtMs": int(fetched_at.timestamp() * 1000),
            "utilization": {
                "five_hour": {
                    "utilization": 0,
                    "resets_at": None,
                },
                "seven_day": {
                    "utilization": 100,
                    "resets_at": "2026-07-25T12:59:59.831800+00:00",
                },
                "extra_usage": {
                    "is_enabled": True,
                    "monthly_limit": 200000,
                    "used_credits": 162911,
                    "utilization": 81.4555,
                    "currency": "USD",
                    "decimal_places": 2,
                    "user_disabled": False,
                    "spend_limit_reached": False,
                },
                "limits": [
                    {
                        "kind": "session",
                        "group": "session",
                        "percent": 0,
                        "severity": "normal",
                        "resets_at": None,
                        "is_active": False,
                    },
                    {
                        "kind": "weekly_all",
                        "group": "weekly",
                        "percent": 100,
                        "severity": "critical",
                        "resets_at": "2026-07-25T12:59:59.831800+00:00",
                        "is_active": True,
                    },
                    {
                        "kind": "weekly_scoped",
                        "group": "weekly",
                        "percent": 42,
                        "severity": "normal",
                        "resets_at": "2026-07-25T12:59:59.832430+00:00",
                        "scope": {
                            "model": {
                                "display_name": "Fable",
                            }
                        },
                        "is_active": False,
                    },
                ],
                "spend": {
                    "used": {
                        "amount_minor": 162911,
                        "currency": "USD",
                        "exponent": 2,
                    },
                    "limit": {
                        "amount_minor": 200000,
                        "currency": "USD",
                        "exponent": 2,
                    },
                    "percent": 81,
                    "enabled": True,
                },
            },
        },
    }


class ReportTests(unittest.TestCase):
    def test_build_report_detects_credit_billing_without_leaking_secrets(self):
        config = usage_config()
        auth_status = {
            "loggedIn": True,
            "authMethod": "claude.ai",
            "apiProvider": "firstParty",
            "subscriptionType": "team",
            "email": "secret@example.com",
            "orgId": "secret-org-id",
            "token": "secret-auth-token",
        }
        environment = {
            "FORCE_PROMPT_CACHING_5M": "1",
        }
        now = datetime(2026, 7, 23, 11, 49, 20, tzinfo=timezone.utc)

        report = claude_usage.build_report(
            config=config,
            auth_status=auth_status,
            environment=environment,
            now=now,
        )

        self.assertTrue(report["status"]["using_extra_usage_now"])
        self.assertTrue(report["status"]["can_continue"])
        self.assertEqual(report["usage"]["weekly_all"]["percent"], 100)
        self.assertEqual(report["usage"]["fable"]["percent"], 42)
        self.assertAlmostEqual(report["extra_usage"]["spent"], 1629.11)
        self.assertAlmostEqual(report["extra_usage"]["limit"], 2000.00)
        self.assertEqual(report["extra_usage"]["remaining"], 370.89)
        self.assertEqual(report["extra_usage"]["currency"], "USD")
        self.assertEqual(report["authentication"]["method"], "claude.ai")
        self.assertEqual(report["authentication"]["subscription_type"], "team")
        self.assertFalse(report["authentication"]["api_key_environment_set"])
        self.assertTrue(report["cache_policy"]["force_5m"])
        self.assertFalse(report["cache_policy"]["enable_1h"])
        self.assertEqual(report["cache"]["age_seconds"], 3)

        serialized = json.dumps(report)
        self.assertNotIn("secret@example.com", serialized)
        self.assertNotIn("secret-account-id", serialized)
        self.assertNotIn("secret-org-id", serialized)
        self.assertNotIn("secret-auth-token", serialized)

    def test_api_key_environment_selects_api_billing_without_leaking_value(self):
        report = claude_usage.build_report(
            config=usage_config(),
            auth_status={
                "loggedIn": True,
                "authMethod": "claude.ai",
                "apiProvider": "firstParty",
                "subscriptionType": "team",
            },
            environment={"ANTHROPIC_API_KEY": "secret-api-key"},
            now=datetime(2026, 7, 23, 11, 49, 20, tzinfo=timezone.utc),
        )

        self.assertFalse(report["status"]["using_extra_usage_now"])
        self.assertEqual(report["status"]["billing_route"], "api_key")
        self.assertNotIn("secret-api-key", json.dumps(report))

    def test_extra_usage_is_not_active_before_weekly_limit_is_exhausted(self):
        config = usage_config()
        config["cachedUsageUtilization"]["utilization"]["seven_day"][
            "utilization"
        ] = 99
        weekly_limit = config["cachedUsageUtilization"]["utilization"]["limits"][1]
        weekly_limit["percent"] = 99
        weekly_limit["severity"] = "warning"
        weekly_limit["is_active"] = False

        report = claude_usage.build_report(
            config=config,
            auth_status={},
            environment={},
            now=datetime(2026, 7, 23, 11, 49, 20, tzinfo=timezone.utc),
        )

        self.assertFalse(report["status"]["using_extra_usage_now"])

    def test_spend_limit_prevents_continuing_on_extra_usage(self):
        config = usage_config()
        extra_usage = config["cachedUsageUtilization"]["utilization"]["extra_usage"]
        extra_usage["used_credits"] = 200000
        extra_usage["utilization"] = 100
        extra_usage["spend_limit_reached"] = True

        report = claude_usage.build_report(
            config=config,
            auth_status={},
            environment={},
            now=datetime(2026, 7, 23, 11, 49, 20, tzinfo=timezone.utc),
        )

        self.assertFalse(report["status"]["can_continue"])
        self.assertEqual(report["extra_usage"]["remaining"], 0)

    def test_text_report_leads_with_the_billing_state(self):
        report = claude_usage.build_report(
            config=usage_config(),
            auth_status={
                "loggedIn": True,
                "authMethod": "claude.ai",
                "apiProvider": "firstParty",
                "subscriptionType": "team",
            },
            environment={},
            now=datetime(2026, 7, 23, 11, 49, 20, tzinfo=timezone.utc),
        )

        output = claude_usage.render_text(report)

        self.assertIn("YES — using extra-usage credits", output)
        self.assertIn("$1,629.11 of $2,000.00", output)
        self.assertIn("$370.89", output)
        self.assertIn("100% used", output)
        self.assertIn("Claude Team", output)
        self.assertIn("zero model prompts", output)


class CcusageTests(unittest.TestCase):
    def test_summarize_ccusage_filters_current_week_to_claude_models(self):
        payload = {
            "weekly": [
                {
                    "period": "2026-07-13",
                    "modelBreakdowns": [
                        {
                            "modelName": "claude-opus-4-8",
                            "cost": 5,
                            "inputTokens": 1,
                            "outputTokens": 2,
                            "cacheCreationTokens": 3,
                            "cacheReadTokens": 4,
                        }
                    ],
                },
                {
                    "period": "2026-07-20",
                    "modelBreakdowns": [
                        {
                            "modelName": "claude-opus-4-8",
                            "cost": 12.5,
                            "inputTokens": 10,
                            "outputTokens": 20,
                            "cacheCreationTokens": 30,
                            "cacheReadTokens": 40,
                        },
                        {
                            "modelName": "gpt-5.6-sol",
                            "cost": 99,
                            "inputTokens": 100,
                            "outputTokens": 200,
                            "cacheCreationTokens": 300,
                            "cacheReadTokens": 400,
                        },
                    ],
                },
            ]
        }

        summary = claude_usage.summarize_ccusage(payload)

        self.assertEqual(summary["period"], "2026-07-20")
        self.assertEqual(summary["api_equivalent_cost"], 12.5)
        self.assertEqual(summary["input_tokens"], 10)
        self.assertEqual(summary["output_tokens"], 20)
        self.assertEqual(summary["cache_creation_tokens"], 30)
        self.assertEqual(summary["cache_read_tokens"], 40)
        self.assertEqual(summary["total_tokens"], 100)


class RefreshTests(unittest.TestCase):
    def test_refresh_uses_usage_slash_command_and_exits_without_a_prompt(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            config_path = temporary_path / ".claude.json"
            config = usage_config()
            config["cachedUsageUtilization"]["fetchedAtMs"] = 1
            config_path.write_text(json.dumps(config), encoding="utf-8")

            command_log_path = temporary_path / "commands.json"
            fake_claude_path = temporary_path / "fake-claude"
            fake_claude_path.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env python3
                    import json
                    import os
                    import sys
                    import time

                    print("Claude Code")
                    print('Try "something"')
                    sys.stdout.flush()

                    usage_command = sys.stdin.readline()
                    with open(os.environ["FAKE_COMMAND_LOG"], "w", encoding="utf-8") as stream:
                        json.dump([usage_command.strip()], stream)

                    with open(os.environ["FAKE_CONFIG"], encoding="utf-8") as stream:
                        config = json.load(stream)
                    config["cachedUsageUtilization"]["fetchedAtMs"] = int(time.time() * 1000)
                    with open(os.environ["FAKE_CONFIG"], "w", encoding="utf-8") as stream:
                        json.dump(config, stream)

                    print("Current week")
                    sys.stdout.flush()

                    exit_command = sys.stdin.readline()
                    with open(os.environ["FAKE_COMMAND_LOG"], encoding="utf-8") as stream:
                        commands = json.load(stream)
                    commands.append(exit_command.replace("\\x1b", "").strip())
                    with open(os.environ["FAKE_COMMAND_LOG"], "w", encoding="utf-8") as stream:
                        json.dump(commands, stream)
                    """
                ),
                encoding="utf-8",
            )
            fake_claude_path.chmod(0o755)
            environment = os.environ.copy()
            environment["FAKE_CONFIG"] = str(config_path)
            environment["FAKE_COMMAND_LOG"] = str(command_log_path)

            result = claude_usage.refresh_usage_cache(
                claude_binary=str(fake_claude_path),
                config_path=config_path,
                working_directory=temporary_path,
                environment=environment,
                timeout_seconds=5,
            )

            self.assertTrue(result.refreshed, result.message)
            commands = json.loads(command_log_path.read_text(encoding="utf-8"))
            self.assertEqual(commands, ["/usage", "/exit"])


if __name__ == "__main__":
    unittest.main()
