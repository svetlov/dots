import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CODE_AGENTS_ROOT = REPOSITORY_ROOT / "all" / "code-agents"
RULES_PATH = CODE_AGENTS_ROOT / "codex-rules" / "dippy.rules"
ADAPTER_PATH = (
    CODE_AGENTS_ROOT / "codex-hooks" / "dippy_adapter.py"
)
HOOKS_PATH = CODE_AGENTS_ROOT / "codex-hooks.json"
INSTALLER_PATH = REPOSITORY_ROOT / "install.py"
DIPPY_CONFIG_PATH = CODE_AGENTS_ROOT / "dippy-config"


def execpolicy_decision(*command):
    result = subprocess.run(
        [
            "codex",
            "execpolicy",
            "check",
            "--rules",
            str(RULES_PATH),
            "--",
            *command,
        ],
        capture_output=True,
        check=True,
        text=True,
    )
    return json.loads(result.stdout).get("decision")


def run_adapter(temporary_directory, decision):
    fake_dippy = Path(temporary_directory) / "dippy-hook"
    fake_dippy.write_text(
        (
            "#!/bin/sh\n"
            "cat >/dev/null\n"
            "printf '%s\\n' "
            f"'{{\"hookSpecificOutput\":{{"
            f"\"permissionDecision\":\"{decision}\","
            "\"permissionDecisionReason\":\"test reason\"}}'\n"
        ),
        encoding="utf-8",
    )
    fake_dippy.chmod(0o755)
    payload = {
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": "example"},
    }
    return subprocess.run(
        [
            sys.executable,
            str(ADAPTER_PATH),
            "--dippy-bin",
            str(fake_dippy),
        ],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
    )


class CodexPolicyTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("codex"), "Codex CLI is unavailable")
    def test_rules_allow_read_only_commands(self):
        self.assertEqual(
            execpolicy_decision("git", "status", "--short"),
            "allow",
        )
        self.assertEqual(
            execpolicy_decision("kubectl", "get", "pods"),
            "allow",
        )
        self.assertEqual(
            execpolicy_decision("gh", "pr", "view", "123"),
            "allow",
        )
        self.assertEqual(
            execpolicy_decision(
                "workmux",
                "set-window-status",
                "waiting",
            ),
            "allow",
        )

    @unittest.skipUnless(shutil.which("codex"), "Codex CLI is unavailable")
    def test_rules_do_not_allow_mutating_variants(self):
        self.assertEqual(
            execpolicy_decision("git", "branch", "-D", "feature"),
            "forbidden",
        )
        self.assertIsNone(
            execpolicy_decision("gh", "api", "-X", "POST", "/repos/x/y"),
        )
        self.assertIsNone(
            execpolicy_decision("gcloud", "storage", "cp", "a", "b"),
        )
        self.assertIsNone(
            execpolicy_decision("workmux", "remove", "session"),
        )

    def test_claude_dippy_policy_allows_workmux_status_updates(self):
        dippy_config = DIPPY_CONFIG_PATH.read_text(encoding="utf-8")

        self.assertIn(
            "allow workmux set-window-status waiting",
            dippy_config,
        )

    def test_dippy_adapter_blocks_denials(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            result = run_adapter(temporary_directory, "deny")

        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            json.loads(result.stdout),
            {
                "decision": "block",
                "reason": "test reason",
            },
        )

    def test_dippy_adapter_defers_allow_and_ask_decisions_to_codex(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            allow_result = run_adapter(temporary_directory, "allow")
            ask_result = run_adapter(temporary_directory, "ask")

        self.assertEqual(allow_result.returncode, 0)
        self.assertEqual(json.loads(allow_result.stdout), {})
        self.assertEqual(ask_result.returncode, 0)
        self.assertEqual(json.loads(ask_result.stdout), {})

    def test_installer_preserves_personal_rules_and_installs_policy(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            home_directory = Path(temporary_directory) / "home"
            codex_directory = home_directory / ".codex"
            rules_directory = codex_directory / "rules"
            rules_directory.mkdir(parents=True)
            personal_rules = rules_directory / "default.rules"
            personal_rules.write_text(
                'prefix_rule(pattern=["personal"], decision="allow")\n',
                encoding="utf-8",
            )
            existing_hooks = codex_directory / "hooks.json"
            existing_hooks.write_text('{"hooks": {}}\n', encoding="utf-8")
            environment = os.environ.copy()
            environment["HOME"] = str(home_directory)

            subprocess.run(
                [
                    sys.executable,
                    str(INSTALLER_PATH),
                    "install",
                    "code-agents",
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )

            installed_rules = rules_directory / "dippy.rules"
            installed_adapter = (
                codex_directory / "hooks" / "dippy_adapter.py"
            )

            self.assertTrue(installed_rules.is_symlink())
            self.assertEqual(installed_rules.resolve(), RULES_PATH.resolve())
            self.assertEqual(
                personal_rules.read_text(encoding="utf-8"),
                'prefix_rule(pattern=["personal"], decision="allow")\n',
            )
            self.assertTrue(installed_adapter.is_symlink())
            self.assertEqual(
                installed_adapter.resolve(),
                ADAPTER_PATH.resolve(),
            )
            self.assertTrue(existing_hooks.is_symlink())
            self.assertEqual(existing_hooks.resolve(), HOOKS_PATH.resolve())
            hooks_backup = codex_directory / "hooks.json.old.0"
            self.assertEqual(
                hooks_backup.read_text(encoding="utf-8"),
                '{"hooks": {}}\n',
            )


if __name__ == "__main__":
    unittest.main()
