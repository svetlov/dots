import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CLASSIFIER_PATH = (
    REPOSITORY_ROOT / "all" / "tmux" / "agent-blocking-prompt.sh"
)
PANE_CHILD_COMMANDS_PATH = (
    REPOSITORY_ROOT / "all" / "tmux" / "agent-pane-child-commands.sh"
)
WINDOW_LIST_PATH = REPOSITORY_ROOT / "all" / "tmux" / "tmux-window-list.sh"
STATUS_DAEMON_PATH = (
    REPOSITORY_ROOT / "all" / "tmux" / "tmux-claude-status.sh"
)


def classify(pane_command, pane_text, foreground_command=""):
    return subprocess.run(
        [
            "sh",
            str(CLASSIFIER_PATH),
            pane_command,
            foreground_command,
        ],
        input=pane_text,
        capture_output=True,
        text=True,
    )


class BlockingPromptTests(unittest.TestCase):
    def test_reads_full_child_command_for_generic_node_pane(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            fake_bin = Path(temporary_directory)
            fake_pgrep = fake_bin / "pgrep"
            fake_ps = fake_bin / "ps"
            fake_pgrep.write_text(
                "#!/bin/sh\nprintf '456\\n'\n",
                encoding="utf-8",
            )
            fake_ps.write_text(
                "#!/bin/sh\nprintf 'node /Users/example/.local/bin/codex\\n'\n",
                encoding="utf-8",
            )
            fake_pgrep.chmod(0o755)
            fake_ps.chmod(0o755)
            environment = os.environ.copy()
            environment["PATH"] = (
                f"{fake_bin}{os.pathsep}{environment['PATH']}"
            )

            result = subprocess.run(
                ["sh", str(PANE_CHILD_COMMANDS_PATH), "123"],
                capture_output=True,
                env=environment,
                text=True,
            )

        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            result.stdout,
            "node /Users/example/.local/bin/codex\n",
        )

    def test_detects_codex_command_confirmation(self):
        result = classify(
            "codex",
            (
                "  Would you like to run the following command?\n"
                "\n"
                "  $ git commit -m example\n"
            ),
        )

        self.assertEqual(result.returncode, 0)

    def test_detects_node_wrapped_codex_command_confirmation(self):
        result = classify(
            "node",
            "Would you like to run the following command?\n",
            "node /Users/example/.local/bin/codex",
        )

        self.assertEqual(result.returncode, 0)

    def test_ignores_node_processes_that_are_not_codex(self):
        result = classify(
            "node",
            "Would you like to run the following command?\n",
            "node /Users/example/project/server.js",
        )

        self.assertEqual(result.returncode, 1)

    def test_preserves_existing_claude_permission_detection(self):
        result = classify(
            "claude",
            "Do you want to proceed?\n  1. Yes\n  2. No\n",
        )

        self.assertEqual(result.returncode, 0)

    def test_regular_codex_output_is_not_blocked(self):
        result = classify(
            "codex",
            "Working on the requested change\nesc to interrupt\n",
        )

        self.assertEqual(result.returncode, 1)

    def test_ignores_prompt_text_in_non_agent_panes(self):
        result = classify(
            "zsh",
            "Would you like to run the following command?\n",
        )

        self.assertEqual(result.returncode, 1)

    def test_classifier_is_wired_into_picker_and_status_daemon(self):
        window_list = WINDOW_LIST_PATH.read_text(encoding="utf-8")
        status_daemon = STATUS_DAEMON_PATH.read_text(encoding="utf-8")

        self.assertIn("agent-blocking-prompt.sh", window_list)
        self.assertIn('"codex"', window_list)
        self.assertIn(
            '[ "$cmd" = "vim" ] || [ "$cmd" = "node" ]; then',
            window_list,
        )
        self.assertIn("agent-blocking-prompt.sh", status_daemon)
        self.assertIn("@agent_codex_prompt_blocked", status_daemon)


if __name__ == "__main__":
    unittest.main()
