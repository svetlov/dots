---
description: Spawn the IR/ranking researcher (Fable) inline via the Agent tool
---
Spawn our **IR/ranking researcher** inline via the Agent tool — it runs on Fable
(per its definition) and streams in this session, no manual attach. Do NOT do
the research yourself.

Use the Agent tool with `subagent_type: "ir-researcher"`. Pass my request
(`$ARGUMENTS`) as the prompt. If I gave nothing, spawn it anyway with a prompt
like "Introduce yourself and ask what I want to research" — never refuse to start.

The agent researches on Fable, may consult GPT‑5.6 via `codex exec`, and writes
`techspec/<branch>/research.spec.md`. Relay its output to me. For my follow-ups,
continue the SAME agent via `SendMessage` (don't spawn a new one). When the spec
is ready, I implement here on Opus.
