#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys
from pathlib import Path


STATUS_IGNORED = {".", " ", "?"}


class GitCommandError(RuntimeError):
    pass


def run_git(repository_path, arguments, *, check=True, text=True):
    try:
        result = subprocess.run(
            ["git", *arguments],
            cwd=repository_path,
            capture_output=True,
            text=text,
        )
    except FileNotFoundError as error:
        raise GitCommandError("git is not installed or not on PATH") from error

    if check and result.returncode != 0:
        standard_error = result.stderr
        if not text:
            standard_error = standard_error.decode(
                "utf-8",
                errors="replace",
            )
        message = standard_error.strip() or "git command failed"
        raise GitCommandError(message)
    return result


def git_text(repository_path, *arguments):
    return run_git(repository_path, list(arguments)).stdout.strip()


def resolve_path(repository_path, raw_path):
    path = Path(raw_path)
    if not path.is_absolute():
        path = Path(repository_path) / path
    return path.resolve()


def parse_worktrees(output):
    worktrees = []
    current = {}
    for line in output.splitlines():
        if not line:
            if current:
                worktrees.append(current)
                current = {}
            continue
        key, separator, value = line.partition(" ")
        current[key] = value if separator else True
    if current:
        worktrees.append(current)
    return worktrees


def collect_worktree(repository_path):
    root = Path(
        git_text(repository_path, "rev-parse", "--show-toplevel")
    ).resolve()
    git_directory = resolve_path(
        repository_path,
        git_text(repository_path, "rev-parse", "--git-dir"),
    )
    common_directory = resolve_path(
        repository_path,
        git_text(repository_path, "rev-parse", "--git-common-dir"),
    )
    worktrees = parse_worktrees(
        git_text(repository_path, "worktree", "list", "--porcelain")
    )
    if not worktrees:
        raise GitCommandError("git did not report a primary worktree")

    primary_path = Path(worktrees[0]["worktree"]).resolve()
    current_entry = None
    for worktree in worktrees:
        if Path(worktree["worktree"]).resolve() == root:
            current_entry = worktree
            break
    if current_entry is None:
        raise GitCommandError("current worktree is missing from git worktree list")

    return {
        "path": str(root),
        "primary_path": str(primary_path),
        "is_primary": root == primary_path,
        "git_directory": str(git_directory),
        "common_directory": str(common_directory),
        "locked": bool(current_entry.get("locked", False)),
    }


def resolve_commit(repository_path, reference):
    result = run_git(
        repository_path,
        ["rev-parse", "--verify", "--quiet", "{}^{{commit}}".format(reference)],
        check=False,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def base_result(repository_path, reference, source):
    return {
        "ref": reference,
        "source": source,
        "head": resolve_commit(repository_path, reference),
    }


def resolve_base(repository_path, branch_name, explicit_base):
    if explicit_base:
        return base_result(repository_path, explicit_base, "explicit")

    if branch_name:
        workmux_result = run_git(
            repository_path,
            [
                "config",
                "--get",
                "branch.{}.workmux-base".format(branch_name),
            ],
            check=False,
        )
        if workmux_result.returncode == 0 and workmux_result.stdout.strip():
            return base_result(
                repository_path,
                workmux_result.stdout.strip(),
                "workmux",
            )

    remote_default = run_git(
        repository_path,
        [
            "symbolic-ref",
            "--quiet",
            "--short",
            "refs/remotes/origin/HEAD",
        ],
        check=False,
    )
    if remote_default.returncode == 0 and remote_default.stdout.strip():
        candidate = base_result(
            repository_path,
            remote_default.stdout.strip(),
            "origin-default",
        )
        if candidate["head"]:
            return candidate

    for reference in ("main", "master"):
        candidate = base_result(repository_path, reference, "conventional")
        if candidate["head"]:
            return candidate

    return {"ref": None, "source": "unresolved", "head": None}


def decode_path(raw_value):
    return raw_value.decode("utf-8", errors="surrogateescape")


def parse_status(output):
    raw_records = output.split(b"\0")
    changes = []
    record_index = 0

    while record_index < len(raw_records):
        raw_record = raw_records[record_index]
        record_index += 1
        if not raw_record:
            continue

        record = decode_path(raw_record)
        record_type = record[0]
        original_path = None

        if record_type == "1":
            fields = record.split(" ", 8)
            if len(fields) != 9:
                raise GitCommandError("could not parse ordinary status record")
            status = fields[1]
            path = fields[8]
            kind = "ordinary"
        elif record_type == "2":
            fields = record.split(" ", 9)
            if len(fields) != 10 or record_index >= len(raw_records):
                raise GitCommandError("could not parse renamed status record")
            status = fields[1]
            path = fields[9]
            original_path = decode_path(raw_records[record_index])
            record_index += 1
            kind = "renamed"
        elif record_type == "u":
            fields = record.split(" ", 10)
            if len(fields) != 11:
                raise GitCommandError("could not parse unmerged status record")
            status = fields[1]
            path = fields[10]
            kind = "unmerged"
        elif record_type == "?":
            status = "??"
            path = record[2:]
            kind = "untracked"
        elif record_type == "!":
            continue
        else:
            raise GitCommandError(
                "unsupported git status record type: {}".format(record_type)
            )

        change = {
            "path": path,
            "kind": kind,
            "index_status": status[0],
            "worktree_status": status[1],
        }
        if original_path is not None:
            change["original_path"] = original_path
        changes.append(change)

    staged_count = sum(
        change["kind"] != "untracked"
        and change["index_status"] not in STATUS_IGNORED
        for change in changes
    )
    unstaged_count = sum(
        change["kind"] != "untracked"
        and change["worktree_status"] not in STATUS_IGNORED
        for change in changes
    )
    untracked_count = sum(
        change["kind"] == "untracked" for change in changes
    )
    conflicted_count = sum(
        change["kind"] == "unmerged" for change in changes
    )

    return {
        "clean": not changes,
        "change_count": len(changes),
        "staged_count": staged_count,
        "unstaged_count": unstaged_count,
        "untracked_count": untracked_count,
        "conflicted_count": conflicted_count,
        "changes": changes,
    }


def collect_status(repository_path):
    result = run_git(
        repository_path,
        ["status", "--porcelain=v2", "-z", "--untracked-files=all"],
        text=False,
    )
    return parse_status(result.stdout)


def git_path_exists(repository_path, name):
    raw_path = git_text(repository_path, "rev-parse", "--git-path", name)
    return resolve_path(repository_path, raw_path).exists()


def collect_operations(repository_path):
    operation_paths = [
        ("rebase", ("rebase-merge", "rebase-apply")),
        ("merge", ("MERGE_HEAD",)),
        ("cherry-pick", ("CHERRY_PICK_HEAD",)),
        ("revert", ("REVERT_HEAD",)),
        ("bisect", ("BISECT_LOG",)),
    ]
    operations = []
    for operation, paths in operation_paths:
        if any(git_path_exists(repository_path, path) for path in paths):
            operations.append(operation)
    return operations


def collect_branch(repository_path):
    branch_result = run_git(
        repository_path,
        ["symbolic-ref", "--quiet", "--short", "HEAD"],
        check=False,
    )
    branch_name = None
    if branch_result.returncode == 0:
        branch_name = branch_result.stdout.strip()
    return {
        "name": branch_name,
        "head": git_text(repository_path, "rev-parse", "HEAD"),
        "detached": branch_name is None,
    }


def collect_commits(repository_path, base):
    if not base["head"]:
        return {
            "ahead_of_base": None,
            "behind_base": None,
            "ahead": [],
            "ahead_truncated": False,
        }

    counts = git_text(
        repository_path,
        "rev-list",
        "--left-right",
        "--count",
        "{}...HEAD".format(base["ref"]),
    ).split()
    behind_count = int(counts[0])
    ahead_count = int(counts[1])

    log_result = git_text(
        repository_path,
        "log",
        "--max-count=20",
        "--format=%H%x09%h%x09%s",
        "{}..HEAD".format(base["ref"]),
    )
    ahead = []
    for line in log_result.splitlines():
        full_head, short_head, subject = line.split("\t", 2)
        ahead.append(
            {
                "head": full_head,
                "short_head": short_head,
                "subject": subject,
            }
        )

    return {
        "ahead_of_base": ahead_count,
        "behind_base": behind_count,
        "ahead": ahead,
        "ahead_truncated": ahead_count > len(ahead),
    }


def collect_integration(repository_path, branch, base):
    if branch["detached"]:
        return {"status": "unknown", "reason": "detached HEAD"}
    if not base["head"]:
        return {"status": "unknown", "reason": "base ref is unavailable"}

    merged_result = run_git(
        repository_path,
        ["merge-base", "--is-ancestor", branch["head"], base["ref"]],
        check=False,
    )
    if merged_result.returncode == 0:
        return {"status": "merged", "reason": "branch tip is in base history"}
    if merged_result.returncode not in (0, 1):
        return {"status": "unknown", "reason": "merge ancestry check failed"}

    cherry_result = run_git(
        repository_path,
        ["cherry", base["ref"], branch["head"]],
        check=False,
    )
    if cherry_result.returncode != 0:
        return {"status": "unknown", "reason": "patch comparison failed"}

    cherry_lines = [
        line for line in cherry_result.stdout.splitlines() if line.strip()
    ]
    if cherry_lines and all(line.startswith("- ") for line in cherry_lines):
        return {
            "status": "patch-equivalent",
            "reason": "commits appear applied with different commit IDs",
        }
    return {"status": "unmerged", "reason": "branch has unique commits"}


def cleanup_blockers(worktree, branch, base, status, operations, integration):
    blockers = []
    if worktree["is_primary"]:
        blockers.append("primary worktree")
    if worktree["locked"]:
        blockers.append("worktree is locked")
    if status["change_count"]:
        blockers.append("uncommitted changes")
    if operations:
        blockers.append("Git operation in progress")
    if branch["detached"]:
        blockers.append("detached HEAD")
    if not base["head"]:
        blockers.append("base ref is unavailable")
    if integration["status"] == "unmerged":
        blockers.append("branch is not merged")
    elif integration["status"] == "patch-equivalent":
        blockers.append("branch is only patch-equivalent to base")
    elif integration["status"] == "unknown" and base["head"]:
        blockers.append("branch integration is unknown")
    return blockers


def inspect_repository(repository_path, explicit_base=None):
    repository = Path(repository_path).expanduser().resolve()
    if not repository.is_dir():
        raise GitCommandError(
            "repository path is not a directory: {}".format(repository)
        )

    inside_result = run_git(
        repository,
        ["rev-parse", "--is-inside-work-tree"],
        check=False,
    )
    if inside_result.returncode != 0 or inside_result.stdout.strip() != "true":
        raise GitCommandError("current directory is not inside a Git worktree")

    worktree = collect_worktree(repository)
    branch = collect_branch(repository)
    base = resolve_base(repository, branch["name"], explicit_base)
    status = collect_status(repository)
    operations = collect_operations(repository)
    commits = collect_commits(repository, base)
    integration = collect_integration(repository, branch, base)
    blockers = cleanup_blockers(
        worktree,
        branch,
        base,
        status,
        operations,
        integration,
    )

    return {
        "worktree": worktree,
        "branch": branch,
        "base": base,
        "status": status,
        "operations": operations,
        "commits": commits,
        "integration": integration,
        "cleanup": {
            "eligible": not blockers,
            "blockers": blockers,
        },
    }


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Inspect whether a Git worktree is safe to wrap up."
    )
    parser.add_argument(
        "--repository",
        default=".",
        help="Path inside the worktree to inspect.",
    )
    parser.add_argument(
        "--base",
        help="Explicit integration base ref.",
    )
    return parser.parse_args()


def main():
    arguments = parse_arguments()
    try:
        report = inspect_repository(
            repository_path=arguments.repository,
            explicit_base=arguments.base,
        )
    except GitCommandError as error:
        print("inspection failed: {}".format(error), file=sys.stderr)
        return 2

    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
