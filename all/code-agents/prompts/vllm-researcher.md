---
description: Launch the image-generation researcher as an interactive Fable background agent
---
Start an interactive **Fable** research background agent seeded with my request,
so I can switch to it, iterate on the spec, then come back to this (Opus) session
to implement. Do NOT do the research yourself.

Run this (my request — the text after the command, `$ARGUMENTS` — is the prompt):

    claude --bg --agent imagegen-researcher "$ARGUMENTS"

If `$ARGUMENTS` is empty, ask me for the research topic first, then launch.

Then report the background session id and remind me how to drive it:
- `claude agents` to list; `Space` peek, `Enter`/`→` attach, `←` detach, `Ctrl+T` pin.
- It runs on **Fable**, writes `techspec/<branch>/research.spec.md`, and may
  consult GPT‑5.6 via `codex exec`.
- When the spec is ready, detach and implement back here on Opus.
