# Code Agents — Shared Conventions

## ABSOLUTE RULE #1: Answer questions IMMEDIATELY

If the user asks something, answering them is the ONLY goal. Stop
IMMEDIATELY — mid-task, mid-debug, mid-anything. No other goals exist until
the question is answered: no fixes, no relaunches, no monitors, no memory
writes, no "one more tool call". The reply containing the answer is plain
text with ZERO tool calls (except the minimal read needed to know the
answer, after which stop and answer). There is NOTHING more important than
this. Work resumes only after the answer stands alone and the user responds.

## Multi-Stage Pipeline

The staging pipeline is **off by default**. It activates when a stage-specific prompt is invoked (e.g. `/websearch-research`, `/mlplan`). Each of these prompts contains the phrase **"activate custom code pipeline"** — that's the signal. If you don't see it, skip the pipeline and just use `/plan` and code directly.

| Stage | Role | Prompt | Responsibility |
|-------|------|--------|----------------|
| 1 | **Researcher** | `websearch-research`, `vllm-researcher` | Explore directions, ground in literature. Produces `research.spec.md`. |
| 2 | **Architect** | `mlplan` | ML infrastructure planning (auto-enters plan mode). |

Implementation happens after plan approval — no separate skill needed.

## Research Artifact Path

When Stage 1 is used, research output lives under:

```
techspec/<git-branch>/research.spec.md
```

## Plan Mode

After Stage 1 research concludes (or anytime without the pipeline), the user invokes `/plan` to transition into implementation planning. The conversation history plus `research.spec.md` (if it exists) provide full context — no need to duplicate implementation details in the research artifact.

## Coding Standards

### General
- Prefer explicit, readable code
- Avoid clever abstractions
- Reuse existing code whenever possible, as long as it doesn't hurt readability. Prefer upgrading a maintained library over reimplementing its functionality.
- Keep implementations as simple as possible
- Keep functions short and focused — extract helpers instead of growing monolithic functions
- Each function should do one thing at one level of abstraction
- Follow existing project conventions
- Match existing logging, error handling, and config styles
- Respect async vs sync boundaries
- Avoid unnecessary concurrency
- Separate core and dev dependencies
- Avoid global / static state unless already established or explicitly mentioned
- Avoid unnamed constants; use named constants for magic numbers/strings
- No abbreviated variable names — use full descriptive names (`in_batch_negatives_k`, not `ibn_k`)
- No global variables for input/output paths — use function arguments, CLI args, or pass through `main()`. Global constants as defaults are OK.
- Python-first unless the spec states otherwise
- After any dependency modification or addition, run the appropriate environment sync for that ecosystem.
- When edits create orphans, remove imports/variables/functions that **your changes** made unused. Don't delete pre-existing dead code — flag it instead.

### Python
- Avoid using `hasattr` / `getattr` / `setattr` unless explicitly specified
- Use `pyproject.toml` and `uv` to manage python dependencies, do not touch `.venv` directory directly
- in general prefer `uv run python` instead of `python` for python code invocation
- Never use `.to_arrow()` on vortex files — it loads everything into memory (OOM risk) and has broken `string_view` pyarrow integration. Use `.to_batches()` and iterate instead.

### Rust
- Do not use `.unwrap` unless it's mentioned explicitly
- Use `Cargo.toml` to manage rust dependencies

### Performance
- Only optimize what the spec explicitly calls out
- If performance targets are stated, validate them
- If regressions appear, report them immediately
- Optimizations must justify their complexity — don't micro-optimize code that runs infrequently or isn't on a hot path

## Tests & Validation

Tests must:
- Be deterministic
- Cover specified edge cases
- Fail loudly when assumptions break

Test execution defaults (unless the task specifies otherwise):
- Do not ask the user to run test suites; either run them yourself or state why you cannot.
- Use the default test timeout configured in project config (e.g., `pyproject.toml`, `Cargo.toml`) — do not invent a timeout.
- Run tests in failfast mode.
- Run tests in parallel when the test framework supports it.

Every task must end with running the relevant tests.

When a task maps to a verifiable behavior, convert it into a test-first goal so success is checkable without supervision:
- "Fix bug X" → write a failing test that reproduces X, then make it pass.
- "Add validation" → write tests for invalid inputs, then make them pass.
- "Refactor X" → ensure tests pass before *and* after.

Strong success criteria let you loop independently; weak ones ("make it work") force back-and-forth.

## Commits & PRs
- Do not include a "Test plan" section in commit messages or pull request descriptions.
- Keep PRs reviewable by a human: aim for ~500 LOC of meaningful code (excluding configs, tests, docs, and boilerplate). Not a hard limit, but if a PR grows well past this, split it.
- PR descriptions should include a list of core files changed (skip tests, configs, docs, and boilerplate).

## Error Handling

- Handle errors explicitly
- Do not swallow exceptions
- Prefer clear failure over silent degradation
- Match retry semantics exactly as specified

## Safety

- **When an agreed-upon solution doesn't work**, stop and discuss options. Do not silently escalate to a bigger change — the user approved X, not Y.
- **Never delete non-recoverable data** (S3 objects, checkpoints, database rows, git history) without explicit confirmation. List exactly what will be deleted and wait for approval.
- **Never change parameters of a running job** (cancel + relaunch with different params) without discussion and explicit approval.
- **Implement exactly what was asked** — don't substitute a simpler approximation and call it done. Before marking an instruction as addressed, re-read the original request and verify each part is actually implemented.
- **Never send signals to background processes** (`kill -USR1`, `kill -SIGTERM`, etc.) to check state. Use `ps`, log files, `nvidia-smi`, or `/proc/<pid>/status` instead.
- **Don't state uncertain things confidently.** If you're not sure, either verify first or say so explicitly ("probably X, worth checking"). Never present a guess as a fact.
- **Surface assumptions before implementing.** If the request has multiple plausible interpretations, present them — don't pick silently. If a simpler approach exists, say so. Push back when warranted. Better to ask than to build the wrong thing.

## Logging

- Prefer `logging` / `structlog` / `loguru` over `print` for new code
- Keep logs machine-readable: structured key=value pairs, timestamps, source context
- No rich/fancy formatting or emojis in logs

## Efficiency

- **Long-running commands**: run in background (`run_in_background: true`) when expected to take >1 minute. Never pipe long-running output through `head`/`tail`/`grep` — redirect to a file first, then read it.
- **Progress logging**: for operations that take >10 seconds, log what's starting, periodic progress if possible, and elapsed time when done.
- **Intermediate results**: for long-running scripts where a crash would lose significant work, save results incrementally (per-iteration with flush), not just at the end. Use judgment — don't add overhead for scripts that finish quickly.
- **Research**: for quick factual lookups, checking local code or docs is fine. For broader questions (best practices, library capabilities, design alternatives), use web search — and for complex topics, do both web and code exploration.
