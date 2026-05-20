#!/bin/sh
# Background daemon: writes a "💬 W1, W2" prefix into the @waiting_prefix
# tmux user option whenever any non-active window has a workmux "waiting"
# status. tmux.conf references #{@waiting_prefix} at the start of status-left
# so the indicator appears on the left edge of the bar (and is empty when
# nothing's waiting).
#
# How it works:
#   - Launched from tmux.conf via `run-shell -b` (runs in background)
#   - Every 1s, iterates all tmux windows reading @workmux_status (set by
#     workmux from a Claude Code stop/notify hook in ~/.claude/settings.json)
#   - Windows currently viewed by any client are skipped
#   - WAITING_ICON env var matches workmux's status_icons.waiting (default 💬)
#
# Single instance:
#   On startup, kills any previous instances found via pgrep (excluding self).

WAITING_ICON="${WAITING_ICON:-💬}"
PREFIX_STYLE="#[bg=red,fg=white,bold]"
RESET_STYLE="#[default]"

# Kill previous instances (exclude self)
for pid in $(pgrep -f "tmux-claude-status\.sh"); do
  [ "$pid" != "$$" ] && kill "$pid" 2>/dev/null
done

while true; do
  # list-clients gives us the active window for each attached client,
  # so we can skip those — no need to alert about a window you're viewing
  active=$(tmux list-clients -F "#{session_name}:#{window_index}" 2>/dev/null)
  [ -z "$active" ] && { sleep 1; continue; }

  labels=""
  count=0
  for win in $(tmux list-windows -a -F "#{session_name}:#{window_index}"); do
    skip=0
    for a in $active; do
      [ "$win" = "$a" ] && skip=1 && break
    done
    [ $skip -eq 1 ] && continue

    status=$(tmux show -wqv -t "$win" @workmux_status 2>/dev/null)
    [ "$status" = "$WAITING_ICON" ] || continue

    name=$(tmux display-message -t "$win" -p "#{window_index}:#W" 2>/dev/null)
    labels="${labels:+$labels, }$name"
    count=$((count + 1))
  done

  if [ $count -gt 0 ]; then
    tmux set -g @waiting_prefix "$PREFIX_STYLE $WAITING_ICON $labels $RESET_STYLE" 2>/dev/null
  else
    tmux set -g @waiting_prefix "" 2>/dev/null
  fi

  sleep 1
done
