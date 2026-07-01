#!/usr/bin/env bash
# Re-authenticate the cloud CLIs, one at a time, in this order:
#   1. aws    — AWS SSO login          (covers every profile on the SSO session)
#   2. gcloud — user account login
#   3. adc    — gcloud Application Default Credentials login ("gcloud app")
#
# Each step is interactive (opens a browser). A failure (e.g. you cancel the
# browser flow) is reported but does NOT abort the rest — a summary prints at
# the end.
#
# Usage:
#   scripts/cloud-auth.sh                # run all three, in order
#   scripts/cloud-auth.sh aws            # run only the named step(s)
#   scripts/cloud-auth.sh gcloud adc
#
# Override the AWS SSO session name if it ever changes:
#   AWS_SSO_SESSION=other-session scripts/cloud-auth.sh aws
set -o pipefail

# Use the GLOBAL CLI binaries, not whatever is first on PATH — a project/worktree
# venv can shadow them (e.g. a .venv shipping aws-cli v1, which has no
# `sso login`). Resolving to the Homebrew/system install sidesteps that. The cd
# to $HOME is belt-and-suspenders for any cwd-relative config; note it does NOT
# deactivate a venv or change PATH, which is why the explicit binary matters.
cd "$HOME" || exit 1

AWS_SSO_SESSION="${AWS_SSO_SESSION:-seva-rog-wsl}"

# Prefer the global install over any venv/PATH shim.
resolve_bin() {
  for cand in "/opt/homebrew/bin/$1" "/usr/local/bin/$1" "/usr/bin/$1"; do
    [ -x "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  command -v "$1" 2>/dev/null
}
AWS_BIN=$(resolve_bin aws)
GCLOUD_BIN=$(resolve_bin gcloud)

ok_steps=""
failed_steps=""
skipped_steps=""

# run_step <label> <command...> — run a command, record the outcome, keep going.
run_step() {
  label="$1"
  shift
  printf '\n\033[1m=== %s ===\033[0m\n$ %s\n' "$label" "$*"
  if "$@"; then
    printf '\033[32m✓ %s ok\033[0m\n' "$label"
    ok_steps="${ok_steps:+$ok_steps, }$label"
  else
    rc=$?
    printf '\033[31m✗ %s failed (exit %d)\033[0m\n' "$label" "$rc"
    failed_steps="${failed_steps:+$failed_steps, }$label"
  fi
}

# require <resolved-bin> <label> — true if the CLI resolved; else record a skip.
require() {
  [ -n "$1" ] && [ -x "$1" ] && return 0
  printf '\n\033[33m- %s skipped: no global CLI binary found\033[0m\n' "$2"
  skipped_steps="${skipped_steps:+$skipped_steps, }$2"
  return 1
}

auth_aws() {
  require "$AWS_BIN" "aws" || return 0
  run_step "aws (SSO: $AWS_SSO_SESSION)" "$AWS_BIN" sso login --sso-session "$AWS_SSO_SESSION"
}

auth_gcloud() {
  require "$GCLOUD_BIN" "gcloud" || return 0
  # --quiet: auto-accept confirmation prompts (takes the default) so the browser
  # flow isn't gated behind a "continue? (Y/n)".
  run_step "gcloud (account login)" "$GCLOUD_BIN" auth login --quiet
}

auth_adc() {
  require "$GCLOUD_BIN" "adc" || return 0
  run_step "gcloud ADC (application-default)" "$GCLOUD_BIN" auth application-default login --quiet
}

# Resolve which steps to run: no args -> all three, in order.
steps="${*:-aws gcloud adc}"
for step in $steps; do
  case "$step" in
    aws)    auth_aws ;;
    gcloud) auth_gcloud ;;
    adc|app|gcloud-app) auth_adc ;;
    *) printf '\033[33m- unknown step "%s" (expected: aws | gcloud | adc)\033[0m\n' "$step" ;;
  esac
done

printf '\n\033[1m=== summary ===\033[0m\n'
[ -n "$ok_steps" ]      && printf '\033[32mok:      %s\033[0m\n' "$ok_steps"
[ -n "$skipped_steps" ] && printf '\033[33mskipped: %s\033[0m\n' "$skipped_steps"
[ -n "$failed_steps" ]  && printf '\033[31mfailed:  %s\033[0m\n' "$failed_steps"

[ -z "$failed_steps" ]
