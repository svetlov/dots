---
description: Spawn the ML architect (Fable) inline via the Agent tool
---
Spawn our **ML architect** inline via the Agent tool — it runs on Fable (per its
definition) and streams in this session, no manual attach. Do NOT plan yourself.

Use the Agent tool with `subagent_type: "ml-architect"`. Pass my goal
(`$ARGUMENTS`) as the prompt. If I gave nothing, spawn it anyway with a prompt
like "Introduce yourself and ask what to plan" — never refuse to start.

The architect reads `techspec/<branch>/research.spec.md` if present, plans on
Fable, and may consult GPT‑5.6 via `codex exec`. A subagent can't drive this
session's plan mode, so it returns a **plan draft**; when it does, present that
draft for my approval (enter plan mode / ExitPlanMode). For my follow-ups,
continue the SAME agent via `SendMessage` (don't spawn a new one). After I
approve, implement here on Opus.
