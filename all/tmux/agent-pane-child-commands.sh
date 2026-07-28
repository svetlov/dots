#!/bin/sh
# Print the command lines of a tmux pane shell's direct child processes.
# tmux exposes the shell PID, while pane_current_command may only report a
# generic runtime such as "node".

pane_pid=$1

case "$pane_pid" in
  ""|*[!0-9]*) exit 1 ;;
esac

child_pids=$(pgrep -P "$pane_pid" 2>/dev/null) || exit 1

for child_pid in $child_pids; do
  case "$child_pid" in
    ""|*[!0-9]*) continue ;;
  esac
  ps -o command= -p "$child_pid" 2>/dev/null
done
