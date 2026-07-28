---
name: seva-review
description: Perform a careful, high-signal code review of the current Git changes or a user-specified diff, commit, branch, or file set. Use when the user invokes seva-review or asks for a thorough change review focused on material correctness, security, performance, error handling, edge cases, project conventions, and design simplification rather than style nits.
---

# Seva Review

Act as a senior engineer reviewing changes for real issues that matter. Review
only; do not edit files unless the user separately asks for fixes.

## Select the review scope

Use a user-specified diff, commit, branch, pull request, or file set when given.
Otherwise check these in order and use the first scope that has content:

1. `git diff --cached`
2. `git diff`
3. `git diff main..HEAD`, falling back to `git diff master..HEAD`

Read the complete changed files and the directly relevant surrounding code,
tests, and configuration before judging the diff. Inspect repository
instructions and conventions that apply to those files.

## Review the change

1. Infer the intended behavior and summarize it in one or two sentences.
2. Assess how the implementation achieves that intent and note clear benefits.
3. Look for material issues:
   - correctness bugs and logic errors;
   - missing error handling or important edge cases;
   - injection, authorization bypass, secret exposure, or other security risks;
   - performance regressions on meaningful or hot paths;
   - violations of existing project conventions;
   - missing or inadequate tests for changed behavior.
4. Identify design-level or implementation-level simplifications when they
   materially improve the change.

## Keep findings high-signal

- Flag only issues introduced or modified by the reviewed change.
- Skip style nits, formatting, and anything a normal linter should catch.
- Do not require backward compatibility unless the repository or request
  explicitly requires it.
- Verify each finding against the surrounding code before reporting it.
- Suggest a concrete fix or short code example for a localized issue. Explain
  the concern without prescribing a speculative rewrite for a larger design
  issue.
- Label findings as:
  - `critical`: definitely incorrect, data-loss-prone, or security-sensitive;
  - `important`: likely bug or significant maintainability/operability concern;
  - `suggestion`: worthwhile non-blocking improvement.
- Prefer no finding over a weak or hypothetical one.

## Report

Use this format:

```text
### Summary
<One or two sentences describing the change and overall assessment.>

### Findings
1. **[severity]** path/to/file:line — Short title
   Concise explanation and suggested fix.
```

Use a numbered list so findings can be referenced individually. Do not repeat
the number inside an item. If there are no findings, say that the change looks
good and briefly explain what was checked.
