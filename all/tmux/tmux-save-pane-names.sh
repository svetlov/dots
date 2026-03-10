#!/bin/sh
# Save @custom_name for all panes to a file alongside resurrect saves.
# Called via @resurrect-hook-post-save-all.

NAMES_FILE="$HOME/.local/share/tmux/resurrect/pane_names.txt"
> "$NAMES_FILE"

for pane in $(tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index}"); do
  name=$(tmux display-message -t "$pane" -p "#{@custom_name}" 2>/dev/null)
  [ -n "$name" ] && echo "$pane $name" >> "$NAMES_FILE"
done
exit 0
