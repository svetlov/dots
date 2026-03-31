#!/bin/sh
# Wrapper around tmux-resurrect save that:
# 1. Skips saving during the first 30s after server start (let restore run)
# 2. Throttles saves to at most once per 60s

now=$(date +%s)

# Skip if restore hasn't finished yet
restore_done=$(tmux show-option -gqv @auto-restore-done 2>/dev/null)
if [ "$restore_done" != "1" ]; then
  exit 0
fi

start_time=$(tmux display-message -p '#{start_time}' 2>/dev/null)
# If start_time is empty or non-numeric, default to 0 (allows save)
case "$start_time" in
  ''|*[!0-9]*) start_time=0 ;;
esac
if [ "$((now - start_time))" -lt 30 ]; then
  exit 0
fi

last_save=$(tmux show-option -gqv @resurrect-last-save-time 2>/dev/null)
if [ -n "$last_save" ] && [ "$((now - last_save))" -lt 60 ]; then
  exit 0
fi

tmux set-option -gq @resurrect-last-save-time "$now"
exec "$DOTS_HOME/all/tmux/plugins/tmux-resurrect/scripts/save.sh" quiet
