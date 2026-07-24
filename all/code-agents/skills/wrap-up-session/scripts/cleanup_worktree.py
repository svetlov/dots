#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys
from pathlib import Path

from inspect_worktree import GitCommandError, inspect_repository


class CleanupError(RuntimeError):
    pass


def run_git(repository_path, arguments, *, check=True):
    result = subprocess.run(
        ["git", *arguments],
        cwd=repository_path,
        capture_output=True,
        text=True,
    )
    if check and result.returncode != 0:
        message = result.stderr.strip() or "git command failed"
        raise CleanupError(message)
    return result


def require_equal(label, actual, expected):
    if actual != expected:
        raise CleanupError(
            "{} changed: expected {!r}, found {!r}".format(
                label,
                expected,
                actual,
            )
        )


def cleanup_repository(
    repository_path,
    expected_worktree,
    expected_branch,
    expected_head,
    expected_base,
):
    try:
        report = inspect_repository(
            repository_path=repository_path,
            explicit_base=expected_base,
        )
    except GitCommandError as error:
        raise CleanupError(str(error)) from error

    actual_worktree = str(Path(report["worktree"]["path"]).resolve())
    validated_worktree = str(
        Path(expected_worktree).expanduser().resolve()
    )
    require_equal("worktree path", actual_worktree, validated_worktree)
    require_equal("branch", report["branch"]["name"], expected_branch)
    require_equal("branch HEAD", report["branch"]["head"], expected_head)
    require_equal("base", report["base"]["ref"], expected_base)

    if not report["cleanup"]["eligible"]:
        raise CleanupError(
            "cleanup is blocked: {}".format(
                ", ".join(report["cleanup"]["blockers"])
            )
        )

    primary_worktree = report["worktree"]["primary_path"]
    branch_reference = "refs/heads/{}".format(expected_branch)

    branch_format_result = run_git(
        primary_worktree,
        ["check-ref-format", "--branch", expected_branch],
        check=False,
    )
    if branch_format_result.returncode != 0:
        raise CleanupError("branch name is not a valid local branch")

    current_head = run_git(
        primary_worktree,
        ["rev-parse", "--verify", branch_reference],
    ).stdout.strip()
    require_equal("branch HEAD", current_head, expected_head)

    ancestry_result = run_git(
        primary_worktree,
        [
            "merge-base",
            "--is-ancestor",
            expected_head,
            expected_base,
        ],
        check=False,
    )
    if ancestry_result.returncode != 0:
        raise CleanupError("branch tip is no longer merged into the base")

    run_git(
        primary_worktree,
        ["worktree", "remove", actual_worktree],
    )

    current_head_result = run_git(
        primary_worktree,
        ["rev-parse", "--verify", branch_reference],
        check=False,
    )
    if current_head_result.returncode != 0:
        raise CleanupError(
            "worktree was removed, but the branch disappeared unexpectedly"
        )
    if current_head_result.stdout.strip() != expected_head:
        raise CleanupError(
            "worktree was removed, but the branch moved and was retained"
        )

    final_ancestry_result = run_git(
        primary_worktree,
        [
            "merge-base",
            "--is-ancestor",
            expected_head,
            expected_base,
        ],
        check=False,
    )
    if final_ancestry_result.returncode != 0:
        raise CleanupError(
            "worktree was removed, but the branch is no longer merged and was retained"
        )

    delete_result = run_git(
        primary_worktree,
        ["update-ref", "-d", branch_reference, expected_head],
        check=False,
    )
    if delete_result.returncode != 0:
        message = delete_result.stderr.strip() or "atomic branch deletion failed"
        raise CleanupError(
            "worktree was removed, but the branch was retained: {}".format(
                message
            )
        )

    return {
        "worktree": actual_worktree,
        "branch": expected_branch,
        "head": expected_head,
        "base": expected_base,
        "worktree_removed": True,
        "branch_deleted": True,
    }


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Safely remove one validated, merged Git worktree."
    )
    parser.add_argument("--repository", required=True)
    parser.add_argument("--expected-worktree", required=True)
    parser.add_argument("--expected-branch", required=True)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--expected-base", required=True)
    return parser.parse_args()


def main():
    arguments = parse_arguments()
    try:
        result = cleanup_repository(
            repository_path=arguments.repository,
            expected_worktree=arguments.expected_worktree,
            expected_branch=arguments.expected_branch,
            expected_head=arguments.expected_head,
            expected_base=arguments.expected_base,
        )
    except CleanupError as error:
        print("cleanup refused: {}".format(error), file=sys.stderr)
        return 2

    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
