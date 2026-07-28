#!/bin/sh
# Fuzzy window switcher for tmux with Claude status indicators
# Usage: tmux-window-list.sh <current_session:window> <fzf-tmux-path>
#
# Indicators:
#   [?] (red) - permission prompt, needs user action
#   [>]       - user's turn, Claude is idle
#   [*]       - Claude is thinking/working

CUR="$1"
FZF_TMUX="${2:-fzf-tmux}"
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
BLOCKING_PROMPT_CLASSIFIER="$SCRIPT_DIR/agent-blocking-prompt.sh"
PANE_CHILD_COMMANDS="$SCRIPT_DIR/agent-pane-child-commands.sh"

RED='\033[31m'
RST='\033[0m'

# Build window list with Claude status indicators
list=$(tmux list-windows -a -F "#{session_name}:#{window_index} #{?@custom_name,#{@custom_name} | ,}#{pane_title} (#{pane_current_command})" | while IFS= read -r line; do
  win=$(echo "$line" | cut -d' ' -f1)
  pane_metadata=$(tmux display-message -t "$win" -p "#{pane_pid}|#{pane_current_command}" 2>/dev/null)
  pane_pid=${pane_metadata%%|*}
  cmd=${pane_metadata#*|}
  if [ "$cmd" = "claude" ] || [ "$cmd" = "codex" ] || [ "$cmd" = "nvim" ] || [ "$cmd" = "vim" ] || [ "$cmd" = "node" ]; then
    child_commands=
    [ "$cmd" = "node" ] && child_commands=$(sh "$PANE_CHILD_COMMANDS" "$pane_pid")
    tail=$(tmux capture-pane -t "$win" -p 2>/dev/null)
    if printf '%s\n' "$tail" | sh "$BLOCKING_PROMPT_CLASSIFIER" "$cmd" "$child_commands"; then
      printf "${RED}[?]${RST} %s\n" "$line"
    elif echo "$tail" | grep -q "esc to interrupt"; then
      printf "[*] %s\n" "$line"
    elif echo "$tail" | grep -qE "[0-9]+ (bash|read|edit|write|task|glob|grep)"; then
      printf "[*] %s\n" "$line"
    elif echo "$tail" | grep -q "❯\|? for shortcuts"; then
      printf "[>] %s\n" "$line"
    else
      printf "    %s\n" "$line"
    fi
  else
    printf "    %s\n" "$line"
  fi
done)

# Find position of current window
POS=$(echo "$list" | grep -n "$CUR " | cut -d: -f1)

# Run fzf and switch to selected window
echo "$list" | "$FZF_TMUX" -p 80%,60% \
  --layout=reverse --sync --ansi \
  --bind "load:pos($POS)" \
  --color=current-fg:white,current-bg:blue,current-hl:yellow \
  | sed 's/\[.\] //' | sed 's/^    //' | cut -d' ' -f1 \
  | xargs -r tmux select-window -t
