---
name: wrap-up-session
description: Audit and safely wrap up a Git coding session. Use when the user invokes wrap-up-session or asks to finish, close, clean up, or retire the current session or worktree; summarize uncommitted or unmerged work, recommend whether it should be committed, and remove a clean secondary worktree and session branch when merged, approved, or explicitly forced. Do not use for broad branch cleanup or silently discarding changes.
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
- Treat an explicit instruction to force the wrap-up or skip the checks as a
  force request (see step 3). Never infer it from an ordinary wrap-up request or
  fall back to it after cleanup is blocked or declined — it requires its own
  explicit instruction every time.

## Keep these safety boundaries

- Never run `git reset --hard`, `git clean`, `git stash drop`,
  `git worktree remove --force`, `git branch -D`, or an equivalent destructive
  command, except through the cleanup helper's own `--force` flag on an
  explicit force request.
- Never delete the primary worktree, forced or not: there is no session to wrap
  up there.
- Outside a force request, never delete a detached HEAD, a worktree with an
  in-progress Git operation, uncommitted changes, or unique commits not
  integrated into the resolved base. Treat patch-equivalent commits as a
  squash merge only after separate explicit approval.
- Limit automatic cleanup to the current secondary worktree and its attached
  branch. Age alone does not prove that another branch belongs to this session.
- Fetch only the selected remote integration base as part of the audit. Do not
  push, commit, stash, merge, or rebase unless the user separately asks.
- Perform worktree cleanup as the last tool call. The working directory may no
  longer exist afterward.

## 1. Inspect the worktree

Resolve this skill's directory from the loaded `SKILL.md`, then run:

```text
python3 <skill-directory>/scripts/inspect_worktree.py \
  --repository <current-directory> \
  --refresh-remote
```

Pass `--base <ref>` only when the user explicitly names the integration base.
The inspector otherwise prefers `branch.<name>.workmux-base`, then
`origin/HEAD`, then local `main` or `master`. When the selected base is a
remote-tracking branch such as `origin/main`, it fetches only that remote branch
before comparing. If the fetch fails, report that the comparison may be stale
and do not clean up. Local bases remain read-only and network-free.

Use its JSON report to check:

- staged, unstaged, untracked, and conflicted paths;
- an in-progress merge, rebase, cherry-pick, revert, or bisect;
- commits ahead of the base;
- whether the remote base was current, updated, or could not be refreshed;
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

On an explicit force request, still report this before cleaning up, then skip
the rest of this step: don't wait on `cleanup.requires_approval` or ask the
squash-merge question below.

If `cleanup.requires_approval` is true, do not describe cleanup as rejected or
blocked. Immediately before asking, run this exact standalone command:

```text
workmux set-window-status waiting
```

Do not wrap it in shell conditionals or combine it with other commands. If
workmux is unavailable, continue without retrying. Then ask exactly one concise
question and stop:

```text
Cleanup: This branch appears squash-merged into <base>: its changes are present
under different commit IDs. Allow cleanup of worktree <path> and branch <branch>?
```

Do not infer approval from the original wrap-up request. Continue only after the
user explicitly confirms this squash-merge cleanup.

If uncommitted work or genuinely unmerged unique commits exist, stop after the
report. If the user still wants the worktree removed, require them to choose how
to preserve or explicitly discard the listed work; never make that choice for
them.

## 3. Revalidate and clean up

Proceed when cleanup intent is explicit and either:

- the inspector reports `cleanup.eligible: true`; or
- it reports `cleanup.requires_approval: true` and the user subsequently gives
  explicit squash-merge cleanup approval; or
- the user made an explicit force request.

Run the guarded cleanup helper with the exact values from the report:

```text
python3 <skill-directory>/scripts/cleanup_worktree.py \
  --repository <worktree.path> \
  --expected-worktree <worktree.path> \
  --expected-branch <branch.name> \
  --expected-head <branch.head> \
  --expected-base <base.ref>
```

Add exactly one of these flags, matching the case above:

- `--allow-patch-equivalent` for an approved squash merge — this alone does not
  bypass any other blocker.
- `--force` for an explicit force request — this skips every other blocker
  (uncommitted changes, unmerged commits, an in-progress operation, a locked
  worktree, an unresolved or unrefreshable base) and removes the worktree and
  branch regardless. It still refuses the primary worktree and still verifies
  it is removing the exact worktree, branch, head, and base from the report.
  Omit `--expected-branch` only when `branch.detached` is true; the helper then
  removes the worktree without deleting a branch.

The helper reruns the audit, rejects changed state, removes the linked worktree
(with force only when `--force` was given), rechecks merge ancestry or patch
equivalence unless forced, and deletes only the same branch at the same commit.

For an additional branch, act only when the user names it explicitly. Verify
that no worktree has it checked out and that `git merge-base --is-ancestor`
proves it merged into the named base; then use `git branch -d`. If either check
fails, retain it. Delete explicitly named extra branches before running the
current-worktree cleanup helper.

After a successful helper call, do not run another tool. Reply with the removed
worktree path and branch, and on a force request, state plainly what was
discarded (uncommitted changes, unique commits, an unfinished operation). If
branch deletion was safely refused, say that the worktree was removed but the
branch remains.
