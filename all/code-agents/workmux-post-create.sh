#!/usr/bin/env bash
# Workmux post_create hook: bring a new worktree to a working dev state.
#
# Runs in the new worktree's directory. Workmux exports:
#   WM_HANDLE, WM_WORKTREE_PATH, WM_PROJECT_ROOT, WM_CONFIG_DIR
#
# Steps (each best-effort — failures don't abort worktree creation):
#   1. uv sync --group dev
#      Fall back to plain `uv sync` if the project has no `dev` group
#      (PEP 735 dependency-groups). Other uv errors (network, lockfile,
#      disk) are surfaced.
#   2. Install git pre-commit hooks. `make hooks` takes precedence; falls
#      back to `pre-commit install` when .pre-commit-config.yaml exists.

set -u  # not -e: we want to keep going on individual failures
set -o pipefail

# Step 1: dependencies
if [ -f pyproject.toml ] && command -v uv >/dev/null 2>&1; then
    # Capture stderr so we can decide whether to surface or fall back.
    if uv_err=$(uv sync --group dev 2>&1 >/dev/null); then
        :   # success
    else
        rc=$?
        if printf '%s' "$uv_err" | grep -qF 'Group `dev` is not defined'; then
            # No dev group declared in this repo — sync main deps only.
            uv sync || true
        else
            # Real failure — surface it without aborting the worktree.
            printf '%s\n' "$uv_err" >&2
            printf 'workmux-post-create: uv sync --group dev exited %d\n' "$rc" >&2
        fi
    fi
fi

# Step 2: pre-commit hooks
if make -n hooks >/dev/null 2>&1; then
    make hooks || true
elif [ -f .pre-commit-config.yaml ] && command -v pre-commit >/dev/null 2>&1; then
    pre-commit install || true
fi
