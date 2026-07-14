---
description: Launch the ML architect as an interactive Fable background agent (plan mode)
---
Start an interactive **Fable** architect background agent seeded with my request,
so I can switch to it, refine and approve the plan, then come back to this (Opus)
session to implement. Do NOT plan yourself.

Run this (my goal — the text after the command, `$ARGUMENTS` — is the prompt):

    claude --bg --agent ml-architect "$ARGUMENTS"

If `$ARGUMENTS` is empty, ask me for the goal first, then launch.

Then report the background session id and remind me how to drive it:
- `claude agents` to list; `Space` peek, `Enter`/`→` attach, `←` detach, `Ctrl+T` pin.
- It runs on **Fable**, reads `techspec/<branch>/research.spec.md` if present,
  enters plan mode, and may consult GPT‑5.6 via `codex exec`.
- Approve the plan while attached, then detach and implement back here on Opus.
