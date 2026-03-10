#!/bin/sh
# Wrapper around tmux-resurrect save that skips saving during the first 30s
# after server start. This prevents the auto-save hooks (window-linked etc.)
# from overwriting a good save file before continuum has a chance to restore.

start_time=$(tmux display-message -p '#{start_time}' 2>/dev/null)
now=$(date +%s)
age=$((now - start_time))

if [ "$age" -lt 30 ]; then
  exit 0
fi

exec "$DOTS_HOME/all/tmux/plugins/tmux-resurrect/scripts/save.sh" quiet
