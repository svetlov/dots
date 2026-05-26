#!/usr/bin/env bash
# PreToolUse hook: wraps long-running docker commands with tee
# so stdout+stderr are saved to /tmp/claude-docker-logs/
set -euo pipefail

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command')

# Extract the docker subcommand (first arg after "docker" or "docker-compose")
# Handle: docker run, docker compose up, docker-compose build, etc.
subcmd=""
if [[ "$cmd" =~ ^docker[[:space:]]+compose[[:space:]]+([a-z]+) ]]; then
  subcmd="compose-${BASH_REMATCH[1]}"
elif [[ "$cmd" =~ ^docker-compose[[:space:]]+([a-z]+) ]]; then
  subcmd="compose-${BASH_REMATCH[1]}"
elif [[ "$cmd" =~ ^docker[[:space:]]+([a-z]+) ]]; then
  subcmd="${BASH_REMATCH[1]}"
fi

# Only wrap subcommands that are typically long-running
case "$subcmd" in
  run|exec|build|compose-up|compose-run|compose-build|compose-exec)
    ;;
  *)
    # Short command (ps, images, inspect, logs, etc.) — pass through
    exit 0
    ;;
esac

# Already has tee in it — don't double-wrap
if [[ "$cmd" == *"| tee "* ]] || [[ "$cmd" == *"|tee "* ]]; then
  exit 0
fi

logdir="/tmp/claude-docker-logs"
mkdir -p "$logdir"
timestamp=$(date +%Y%m%d-%H%M%S)
logfile="${logdir}/docker-${subcmd}-${timestamp}.log"

# Wrap: redirect stderr to stdout, pipe through tee
wrapped_cmd="{ ${cmd} ; } 2>&1 | tee ${logfile}"

# Return updatedInput to rewrite the command
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "updatedInput": {
      "command": $(printf '%s' "$wrapped_cmd" | jq -Rs .)
    },
    "additionalContext": "Docker output is being saved to ${logfile}"
  }
}
EOF
