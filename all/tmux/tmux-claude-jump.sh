#!/bin/sh
# Jump to next Claude window blocked on permissions, or back to origin.
#
# First press:  saves current window, jumps to first blocked Claude.
# Next presses: jumps to next blocked Claude (current is skipped as active).
# No blocked:   returns to saved origin, clears state.
#
# Bind: bind-key a run-shell '$DOTS_HOME/all/tmux/tmux-claude-jump.sh'

origin=$(tmux show -gqv @claude_jump_origin)
current=$(tmux display-message -p "#{session_name}:#{window_index}")

# Collect blocked windows (same detection as tmux-claude-status.sh)
blocked=""
for win in $(tmux list-windows -a -F "#{session_name}:#{window_index}"); do
    # Skip the window we're currently viewing
    [ "$win" = "$current" ] && continue

    cmd=$(tmux display-message -t "$win" -p "#{pane_current_command}" 2>/dev/null) || continue
    if [ "$cmd" = "claude" ] || [ "$cmd" = "nvim" ] || [ "$cmd" = "vim" ]; then
        pane=$(tmux capture-pane -t "$win" -p 2>/dev/null)
        echo "$pane" | grep -q "Do you want to proceed\|Would you like to proceed\|Esc to cancel\|requires confirmation for this command\|Do you want to allow Claude to fetch" || continue
    else
        continue
    fi
    blocked="$blocked $win"
done
blocked="${blocked# }"

if [ -z "$origin" ]; then
    # Not in a jump cycle — start one
    [ -z "$blocked" ] && exit 0
    tmux set -g @claude_jump_origin "$current"
    tmux select-window -t "${blocked%% *}"
else
    if [ -n "$blocked" ]; then
        # More blocked windows — jump to next
        tmux select-window -t "${blocked%% *}"
    else
        # All resolved — return to origin
        tmux select-window -t "$origin" 2>/dev/null
        tmux set -gu @claude_jump_origin
    fi
fi
