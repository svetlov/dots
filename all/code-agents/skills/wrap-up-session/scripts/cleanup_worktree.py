#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys
from pathlib import Path

from inspect_worktree import (
    PATCH_EQUIVALENT_APPROVAL,
    GitCommandError,
    inspect_repository,
)


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


def collect_integration_status(repository_path, head, base):
    ancestry_result = run_git(
        repository_path,
        ["merge-base", "--is-ancestor", head, base],
        check=False,
    )
    if ancestry_result.returncode == 0:
        return "merged"
    if ancestry_result.returncode != 1:
        raise CleanupError("merge ancestry check failed")

    cherry_result = run_git(
        repository_path,
        ["cherry", base, head],
        check=False,
    )
    if cherry_result.returncode != 0:
        raise CleanupError("patch comparison failed")
    cherry_lines = [
        line for line in cherry_result.stdout.splitlines() if line.strip()
    ]
    if cherry_lines and all(line.startswith("- ") for line in cherry_lines):
        return "patch-equivalent"
    return "unmerged"


def require_allowed_integration(status, allow_patch_equivalent, message):
    if status == "merged":
        return
    if status == "patch-equivalent" and allow_patch_equivalent:
        return
    if status == "patch-equivalent":
        raise CleanupError(PATCH_EQUIVALENT_APPROVAL)
    raise CleanupError(message)


def cleanup_repository(
    repository_path,
    expected_worktree,
    expected_branch,
    expected_head,
    expected_base,
    allow_patch_equivalent=False,
    force=False,
):
    try:
        report = inspect_repository(
            repository_path=repository_path,
            explicit_base=expected_base,
            refresh_remote=True,
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

    if report["worktree"]["is_primary"]:
        raise CleanupError("primary worktree cannot be removed")

    if not force:
        if report["cleanup"]["requires_approval"] and not allow_patch_equivalent:
            raise CleanupError(PATCH_EQUIVALENT_APPROVAL)

        blockers = list(report["cleanup"]["blockers"])
        if (
            allow_patch_equivalent
            and report["integration"]["status"] == "patch-equivalent"
        ):
            blockers = [
                blocker
                for blocker in blockers
                if blocker != PATCH_EQUIVALENT_APPROVAL
            ]
        if blockers:
            raise CleanupError(
                "cleanup is blocked: {}".format(
                    ", ".join(blockers)
                )
            )

    primary_worktree = report["worktree"]["primary_path"]
    branch_reference = (
        "refs/heads/{}".format(expected_branch) if expected_branch else None
    )

    if branch_reference:
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

        integration_status = collect_integration_status(
            primary_worktree,
            expected_head,
            expected_base,
        )
        if not force:
            require_allowed_integration(
                integration_status,
                allow_patch_equivalent,
                "branch tip is no longer merged into the base",
            )

    run_git(
        primary_worktree,
        ["worktree", "remove"]
        + (["--force"] if force else [])
        + [actual_worktree],
    )

    if not branch_reference:
        return {
            "worktree": actual_worktree,
            "branch": None,
            "head": expected_head,
            "base": expected_base,
            "integration": None,
            "worktree_removed": True,
            "branch_deleted": False,
        }

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

    final_integration_status = collect_integration_status(
        primary_worktree,
        expected_head,
        expected_base,
    )
    if not force:
        require_allowed_integration(
            final_integration_status,
            allow_patch_equivalent,
            (
                "worktree was removed, but the branch is no longer integrated "
                "and was retained"
            ),
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
        "integration": final_integration_status,
        "worktree_removed": True,
        "branch_deleted": True,
    }


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Safely remove one validated, merged Git worktree."
    )
    parser.add_argument("--repository", required=True)
    parser.add_argument("--expected-worktree", required=True)
    parser.add_argument(
        "--expected-branch",
        default=None,
        help="Omit only when HEAD is detached and there is no branch to delete.",
    )
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--expected-base", required=True)
    parser.add_argument(
        "--allow-patch-equivalent",
        action="store_true",
        help="Allow cleanup after separate approval of a squash merge.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help=(
            "Skip every non-primary-worktree safety blocker (uncommitted "
            "changes, unmerged commits, an in-progress Git operation, a "
            "locked worktree, unresolved integration) and force-remove the "
            "worktree and branch regardless."
        ),
    )
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
            allow_patch_equivalent=arguments.allow_patch_equivalent,
            force=arguments.force,
        )
    except CleanupError as error:
        print("cleanup refused: {}".format(error), file=sys.stderr)
        return 2

    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
