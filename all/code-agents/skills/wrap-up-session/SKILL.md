---
name: wrap-up-session
description: Audit and safely wrap up a Git coding session. Use when the user invokes wrap-up-session or asks to finish, close, clean up, or retire the current session or worktree; summarize uncommitted or unmerged work, recommend whether it should be committed, and remove only a clean, fully merged secondary worktree and its session branch. Do not use for broad branch cleanup, force deletion, or silently discarding changes.
---

# Wrap Up Session

Audit the current Git worktree, explain anything that remains, and clean up only
when the exact current session worktree is safe to remove.

## Interpret intent

- Treat `$wrap-up-session`, `/wrap-up-session`, or an unambiguous request to
  wrap up, close, remove, or clean up this session/worktree as cleanup intent.
- If this skill was selected for a status-only request such as "what is left?",
  audit and report only. Do not clean up.
- Treat a request to clean a dirty worktree as cleanup intent, not permission to
  discard its changes.

## Keep these safety boundaries

- Never run `git reset --hard`, `git clean`, `git stash drop`,
  `git worktree remove --force`, `git branch -D`, or an equivalent destructive
  command.
- Never delete the primary worktree, a detached HEAD, a worktree with an
  in-progress Git operation, uncommitted changes, or commits not fully merged
  into the resolved base.
- Limit automatic cleanup to the current secondary worktree and its attached
  branch. Age alone does not prove that another branch belongs to this session.
- Do not fetch, push, commit, stash, merge, or rebase unless the user separately
  asks for that action.
- Perform worktree cleanup as the last tool call. The working directory may no
  longer exist afterward.

## 1. Inspect the worktree

Resolve this skill's directory from the loaded `SKILL.md`, then run:

```text
python3 <skill-directory>/scripts/inspect_worktree.py --repository <current-directory>
```

Pass `--base <ref>` only when the user explicitly names the integration base.
The inspector otherwise prefers `branch.<name>.workmux-base`, then
`origin/HEAD`, then local `main` or `master`. It is read-only.

Use its JSON report to check:

- staged, unstaged, untracked, and conflicted paths;
- an in-progress merge, rebase, cherry-pick, revert, or bisect;
- commits ahead of the base;
- whether the branch is fully merged;
- whether this is a removable secondary worktree.

When changes exist, inspect `git diff --stat`, `git diff --cached --stat`, and
the relevant diffs or untracked files. Avoid displaying secrets, credentials,
large generated files, or binary content. Use the conversation's acceptance
criteria and test results to identify unfinished work; Git state alone cannot
show whether the task is semantically complete.

## 2. Give a short decision

Report no more than four compact bullets:

- `State`: ready, work remains, or cleanup is not applicable.
- `Remaining`: summarize the meaningful changes, unique commits, failed or
  missing validation, or active Git operation.
- `Commit`: say `commit now`, `finish first`, or `nothing to commit`, with one
  concrete reason. Recommend committing only when the changes are intentional,
  coherent, and validated enough to preserve.
- `Cleanup`: state the exact blocker or the exact worktree and branch eligible
  for removal.

If uncommitted work or unmerged commits exist, stop after this report. If the
user still wants the worktree removed, require them to choose how to preserve or
explicitly discard the listed work; never make that choice for them.

## 3. Revalidate and clean up

Proceed only when cleanup intent is explicit and the inspector reports
`cleanup.eligible: true`.

Run the guarded cleanup helper with the exact values from the report:

```text
python3 <skill-directory>/scripts/cleanup_worktree.py \
  --repository <worktree.path> \
  --expected-worktree <worktree.path> \
  --expected-branch <branch.name> \
  --expected-head <branch.head> \
  --expected-base <base.ref>
```

The helper reruns the audit, rejects changed state, removes the linked worktree
without force, rechecks merge ancestry, and deletes only the same branch at the
same commit.

For an additional branch, act only when the user names it explicitly. Verify
that no worktree has it checked out and that `git merge-base --is-ancestor`
proves it merged into the named base; then use `git branch -d`. If either check
fails, retain it. Delete explicitly named extra branches before running the
current-worktree cleanup helper.

After a successful helper call, do not run another tool. Reply with the removed
worktree path and branch. If branch deletion was safely refused, say that the
worktree was removed but the branch remains.
