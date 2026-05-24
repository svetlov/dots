#!/bin/sh
# Jump to next workmux window in "waiting" state (permission prompt pending),
# then return to origin once all are handled.
#
# Detection uses workmux's @workmux_status user option, which is written by
# Claude Code hooks via `workmux set-window-status` (see ~/.claude/settings.json).
# The "waiting" icon defaults to 💬; override WAITING_ICON if you've customized
# workmux's status_icons config.
#
# First press:  saves current window, jumps to first waiting window.
# Next presses: jumps to next waiting window (current is skipped as active).
# No waiting:   returns to saved origin, clears state.
#
# Bind: bind-key g run-shell '$DOTS_HOME/all/tmux/tmux-claude-jump.sh'

WAITING_ICON="${WAITING_ICON:-💬}"

origin=$(tmux show -gqv @claude_jump_origin)
current=$(tmux display-message -p "#{session_name}:#{window_index}")

# Collect waiting windows by reading per-window @workmux_status
blocked=""
for win in $(tmux list-windows -a -F "#{session_name}:#{window_index}"); do
    [ "$win" = "$current" ] && continue
    status=$(tmux show -wqv -t "$win" @workmux_status 2>/dev/null)
    [ "$status" = "$WAITING_ICON" ] && blocked="$blocked $win"
done
blocked="${blocked# }"

if [ -z "$origin" ]; then
    [ -z "$blocked" ] && exit 0
    tmux set -g @claude_jump_origin "$current"
    tmux select-window -t "${blocked%% *}"
else
    if [ -n "$blocked" ]; then
        tmux select-window -t "${blocked%% *}"
    else
        tmux select-window -t "$origin" 2>/dev/null
        tmux set -gu @claude_jump_origin
    fi
fi
