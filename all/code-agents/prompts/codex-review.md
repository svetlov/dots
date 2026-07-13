---
description: Independent second-model review of uncommitted changes via codex CLI
---

Get an independent review of my changes from the **codex CLI** — a *different*
model (GPT-5.5) than you — then triage its findings for me. Fresh eyes from
another model catch blind spots you'd share with yourself.

Default target is **uncommitted** work (staged + unstaged + untracked — NOT
already-committed changes). If I passed arguments, use them verbatim as the
review scope instead (e.g. `--base origin/main`, `--commit <sha>`).

Steps:

1. Run the review non-interactively. Use `codex exec review` with
   `-o/--output-last-message` so the file gets ONLY the final review — the
   agentic trace (its git/sed exec calls, headers) goes to a separate log we
   don't read. It can take a minute:

   ```
   codex exec review --uncommitted -o /tmp/codex-review.md > /tmp/codex-review.log 2>&1
   ```

   If I passed arguments ($ARGUMENTS), use them as the review scope in place of
   `--uncommitted` (e.g. `--base origin/main`, `--commit <sha>`). Use the global
   `~/.local/bin/codex`, not a project venv. If `/tmp/codex-review.md` comes back
   empty, check `/tmp/codex-review.log` (likely "no changes to review") and tell me.

2. Read ONLY `/tmp/codex-review.md` — the clean review (a verdict line plus
   `[P#]` findings, each with `file:line` and rationale). Do not read the .log
   unless the review file is empty. Summarize for me: group into **real
   bugs/risks** vs **style/nits**, most important first, each with `file:line`
   and a one-line why. Drop anything that's clearly a false positive and say
   what you dropped.

3. Treat it as a second opinion, not gospel — call out anything you disagree
   with and why. Do **not** change any code yet; ask me which findings to
   address first.
