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

# Run from $HOME so the logins don't pick up any per-directory CLI config
# (e.g. a project-local gcloud config or env) from wherever this was invoked.
cd "$HOME" || exit 1

AWS_SSO_SESSION="${AWS_SSO_SESSION:-seva-rog-wsl}"

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

# require <cmd> <label> — true if the CLI exists; otherwise record a skip.
require() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  printf '\n\033[33m- %s skipped: `%s` not found on PATH\033[0m\n' "$2" "$1"
  skipped_steps="${skipped_steps:+$skipped_steps, }$2"
  return 1
}

auth_aws() {
  require aws "aws" || return 0
  run_step "aws (SSO: $AWS_SSO_SESSION)" aws sso login --sso-session "$AWS_SSO_SESSION"
}

auth_gcloud() {
  require gcloud "gcloud" || return 0
  run_step "gcloud (account login)" gcloud auth login
}

auth_adc() {
  require gcloud "adc" || return 0
  run_step "gcloud ADC (application-default)" gcloud auth application-default login
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
