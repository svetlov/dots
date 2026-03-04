# Code Agents — Shared Conventions

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
- Reuse existing code whenever possible, as long as it doesn't hurt readability
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
- Python-first unless the spec states otherwise
- After any dependency modification or addition, run the appropriate environment sync for that ecosystem.

### Python
- Avoid using `hasattr` / `getattr` / `setattr` unless explicitly specified
- Use `pyproject.toml` and `uv` to manage python dependencies, do not touch `.venv` directory directly
- in general prefer `uv run python` instead of `python` for python code invocation

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

## Commits & PRs
- Do not include a "Test plan" section in commit messages or pull request descriptions.

## Error Handling

- Handle errors explicitly
- Do not swallow exceptions
- Prefer clear failure over silent degradation
- Match retry semantics exactly as specified
