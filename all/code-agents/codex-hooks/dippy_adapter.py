#!/usr/bin/env python3

import argparse
import json
import logging
import subprocess
import sys
from pathlib import Path


DEFAULT_DIPPY_BIN = (
    Path.home() / ".local" / "share" / "dippy" / "bin" / "dippy-hook"
)
DIPPY_TIMEOUT_SECONDS = 5


def run_dippy(dippy_bin, payload):
    try:
        result = subprocess.run(
            [str(dippy_bin)],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            timeout=DIPPY_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.SubprocessError) as error:
        logging.warning("event=dippy_unavailable error=%s", error)
        return None

    if result.returncode != 0:
        logging.warning(
            "event=dippy_failed exit_code=%s",
            result.returncode,
        )
        return None

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        logging.warning("event=dippy_invalid_output error=%s", error)
        return None


def adapt_decision(dippy_output):
    if not dippy_output:
        return {}

    hook_output = dippy_output.get("hookSpecificOutput", {})
    decision = hook_output.get("permissionDecision")
    if decision != "deny":
        return {}

    reason = hook_output.get("permissionDecisionReason")
    if not reason:
        reason = "Dippy denied this command"
    return {
        "decision": "block",
        "reason": reason,
    }


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Adapt Dippy denials to Codex PreToolUse blocks."
    )
    parser.add_argument(
        "--dippy-bin",
        type=Path,
        default=DEFAULT_DIPPY_BIN,
    )
    return parser.parse_args()


def main():
    logging.basicConfig(
        level=logging.WARNING,
        format="level=%(levelname)s %(message)s",
    )
    arguments = parse_arguments()
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as error:
        logging.warning("event=invalid_hook_input error=%s", error)
        print("{}")
        return 0

    decision = adapt_decision(
        run_dippy(arguments.dippy_bin, payload)
    )
    print(json.dumps(decision))
    return 0


if __name__ == "__main__":
    sys.exit(main())
