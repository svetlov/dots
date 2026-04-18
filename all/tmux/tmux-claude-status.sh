#!/bin/sh
# Background daemon: shows a red status bar when any Claude instance (in a
# non-active window) is waiting for user permission.
#
# How it works:
#   - Launched from tmux.conf via `run-shell -b` (runs in background)
#   - Every 1s, iterates all tmux windows looking for Claude permission prompts
#   - Detected by grepping the visible pane content for "Do you want to proceed"
#     or "Esc to cancel" — these appear in Claude's tool-approval dialogs
#   - Windows currently viewed by any client are skipped (no point alerting
#     about something you're already looking at)
#   - Each blocked window gets its own red status line at the top of the screen
#   - When no windows are blocked, the status bar is hidden completely
#
# Multi-line status:
#   tmux's `status` option accepts "on"/"off" or a number >= 2 for multi-line.
#   "status 1" is invalid in tmux 3.4 (treated as truthy -> "on" but errors),
#   so we use "status on" for 1 line and "status N" for N >= 2.
#
# status-format vs status-left:
#   The daemon writes directly to status-format[0..N] because status-format
#   fully controls what each status line renders. The default status-format[0]
#   (set in tmux.conf) is "#[align=left]#{E:status-left}" — this is restored
#   when no claudes are blocked so the status bar can function normally if
#   re-enabled.
#
# Single instance:
#   On startup, kills any previous instances found via pgrep (excluding self).
#   This handles tmux.conf re-sourcing cleanly without needing lock files.

# Kill previous instances (exclude self)
for pid in $(pgrep -f "tmux-claude-status\.sh"); do
  [ "$pid" != "$$" ] && kill "$pid" 2>/dev/null
done

while true; do
  # list-clients gives us the active window for each attached client,
  # so we can skip those — no need to alert about a window you're viewing
  active=$(tmux list-clients -F "#{session_name}:#{window_index}" 2>/dev/null)
  [ -z "$active" ] && { sleep 1; continue; }

  i=0
  for win in $(tmux list-windows -a -F "#{session_name}:#{window_index}"); do
    # Skip windows active in any client
    skip=0
    for a in $active; do
      [ "$win" = "$a" ] && skip=1 && break
    done
    [ $skip -eq 1 ] && continue

    # Check panes running claude directly, or nvim with @claude_nvim_blocked
    cmd=$(tmux display-message -t "$win" -p "#{pane_current_command}" 2>/dev/null)
    if [ "$cmd" = "claude" ] || [ "$cmd" = "nvim" ] || [ "$cmd" = "vim" ]; then
      # Capture full visible pane content and look for permission dialog markers
      pane=$(tmux capture-pane -t "$win" -p 2>/dev/null)
      if ! echo "$pane" | grep -q "Do you want to proceed\|Would you like to proceed\|Esc to cancel\|requires confirmation for this command\|Do you want to allow Claude to fetch"; then
        continue
      fi
    else
      continue
    fi

    # Format matches ctrl+b w window list for consistency
    label=$(tmux display-message -t "$win" -p "#{session_name}:#{window_index} #{?@custom_name,#{@custom_name} | ,}#{pane_title} (#{pane_current_command})" 2>/dev/null)
    tmux set -gq "status-format[$i]" "#[align=left] [?] $label " 2>/dev/null
    i=$((i + 1))
  done

  # Clear any status-format lines left over from a previous iteration
  # (e.g. a window was unblocked or switched to)
  j=$i
  while [ $j -lt 10 ]; do
    tmux set -gqu "status-format[$j]" 2>/dev/null
    j=$((j + 1))
  done

  if [ $i -gt 1 ]; then
    # Multiple blocked windows: multi-line status bar
    tmux set -g status "$i" 2>/dev/null
  elif [ $i -eq 1 ]; then
    # Single blocked window: "status on" (not "status 1" — see note above)
    tmux set -g status on 2>/dev/null
  else
    # Nothing blocked: restore default format and hide status bar
    tmux set -g "status-format[0]" "#[align=left]#{E:status-left}" 2>/dev/null
    tmux set -g status off 2>/dev/null
  fi

  sleep 1
done
