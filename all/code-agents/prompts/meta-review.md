---
description: Ensemble review — Opus (seva-review) + codex (GPT-5.5) in parallel, merged by cross-model agreement
---

Run our two independent reviewers **in parallel** on the same changeset, then
synthesize their findings labeled by cross-model agreement. This is the
heavyweight pass (a full Opus review AND a codex review) — use it before a
big/risky merge, not for routine diffs. It does NOT modify code.

## Scope (same for both lanes)

Default: **uncommitted** changes (staged + unstaged + untracked). If I passed
arguments ($ARGUMENTS), use them as the scope for BOTH lanes. Translate once and
give each lane the matching diff:

| scope            | codex arg           | git diff for the Opus lane                 |
|------------------|---------------------|--------------------------------------------|
| (default)        | `--uncommitted`     | `git diff HEAD` + untracked files          |
| `--base <b>`     | `--base <b>`        | `git diff <b>...HEAD`                       |
| `--commit <sha>` | `--commit <sha>`    | `git show <sha>`                            |

Keeping both on the SAME changeset is what makes the agreement labels meaningful.

## Run both lanes in parallel

Spawn BOTH subagents in a single message so they run concurrently:

- **Lane A — Opus (house review):** the subagent reads
  `~/.claude/commands/seva-review.md` and follows its *Review process*, *Rules*,
  and *Output format* — but reviews EXACTLY the scope above (ignore that file's
  "Get the diff" auto-detection; use the git command from the table). It returns
  its findings as a list of `severity | file:line | title | why`.

- **Lane B — codex (GPT-5.5):** the subagent runs
  ```
  codex exec review <scope> -o /tmp/codex-review.md > /tmp/codex-review.log 2>&1
  ```
  with the global `~/.local/bin/codex`, then returns the contents of
  `/tmp/codex-review.md` verbatim (the clean `[P#]` findings). If that file is
  empty, it reports what `/tmp/codex-review.log` says (usually "no changes").

## Synthesize

When both return, merge into ONE ranked list:

- Dedupe findings that point at the same issue/location across the two lanes.
- Label each: **[both]** (Opus + codex agree — highest confidence), **[opus]**,
  or **[codex]** (single-model — worth a look, likelier noise or taste).
- Rank **[both]** first, then by severity.
- Where the lanes DISAGREE (one flags something the other implicitly passed on),
  say so — that's a judgement call worth surfacing.

Present the merged list. Do **not** change any code — ask me which findings to
address first.
