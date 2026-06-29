#!/bin/sh
# Background daemon: maintains @agent_tally, a global "🤖N ⛔N 💬N" count of
# every window's agent state — thinking / blocked / waiting-for-input —
# rendered as the leading block of status-left (see tmux.conf).
#
# The per-window state itself is rendered directly by the window-status format
# (which colors each entry from its own @workmux_status); this daemon only
# AGGREGATES it, because a tmux format string can't count across windows.
#
# How it works:
#   - Launched from tmux.conf via `run-shell -b` (runs in background)
#   - Every 1s, reads @workmux_status for every window (set by workmux from a
#     Claude Code stop/notify hook in ~/.claude/settings.json)
#   - Pushes a status refresh only when the tally changes, so the bar reflects
#     agent activity within ~1s without redrawing on every idle tick
#
# *_STATUS env vars are the literal @workmux_status values to match and display.
# Colors mirror tmux.conf's window list.
#
# Single instance: kills previous instances (via pgrep) on startup.

# workmux writes one of these literal emoji to each window's @workmux_status
# (from the Claude Code hooks). They're configured in workmux.yaml to match our
# scheme, so the value we match on IS the glyph we display:
#
#   @workmux_status   our meaning               fill
#   🤖 (working)       thinking                   green
#   ⛔ (waiting)       blocked on permission      red
#   💬 (done)          waiting for your input     yellow
WORKING_STATUS="${WORKING_STATUS:-🤖}"
BLOCKED_STATUS="${BLOCKED_STATUS:-⛔}"
INPUT_STATUS="${INPUT_STATUS:-💬}"

# Kill previous instances (exclude self)
for pid in $(pgrep -f "tmux-claude-status\.sh"); do
  [ "$pid" != "$$" ] && kill "$pid" 2>/dev/null
done

# Render one tally segment. A non-zero count gets the colored background fill;
# a zero count gets dim grey text and NO fill, so empty buckets don't draw the
# eye. Args: <bg-color> <glyph> <count>.
segment() {
  if [ "$3" -gt 0 ]; then
    printf '#[bg=%s,fg=colour16] %s%s ' "$1" "$2" "$3"
  else
    printf '#[default]#[fg=colour244] %s%s ' "$2" "$3"
  fi
}

prev_tally="__init__"

while true; do
  # Windows any client is currently viewing — excluded from the tally, since
  # you can already see their state on screen (the bar's current-window block).
  active=$(tmux list-clients -F "#{session_name}:#{window_index}" 2>/dev/null)

  thinking=0
  blocked=0
  awaiting_input=0
  for win in $(tmux list-windows -a -F "#{session_name}:#{window_index}" 2>/dev/null); do
    skip=0
    for a in $active; do
      [ "$win" = "$a" ] && { skip=1; break; }
    done
    [ "$skip" = 1 ] && continue

    case "$(tmux show -wqv -t "$win" @workmux_status 2>/dev/null)" in
      "$WORKING_STATUS") thinking=$((thinking + 1)) ;;
      "$BLOCKED_STATUS") blocked=$((blocked + 1)) ;;
      "$INPUT_STATUS")   awaiting_input=$((awaiting_input + 1)) ;;
    esac
  done

  tally="$(segment green "$WORKING_STATUS" "$thinking")$(segment red "$BLOCKED_STATUS" "$blocked")$(segment yellow "$INPUT_STATUS" "$awaiting_input")#[default]"

  if [ "$tally" != "$prev_tally" ]; then
    tmux set -g @agent_tally "$tally" 2>/dev/null
    tmux refresh-client -S 2>/dev/null
    prev_tally="$tally"
  fi

  sleep 1
done
