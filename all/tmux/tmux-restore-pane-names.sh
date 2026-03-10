#!/bin/sh
# Restore @custom_name for all panes from saved file.
# Called via @resurrect-hook-pre-restore-pane-processes.

NAMES_FILE="$HOME/.local/share/tmux/resurrect/pane_names.txt"
[ -f "$NAMES_FILE" ] || exit 0

while IFS= read -r line; do
  pane=$(echo "$line" | cut -d' ' -f1)
  name=$(echo "$line" | cut -d' ' -f2-)
  tmux set -t "$pane" -p @custom_name "$name" 2>/dev/null
done < "$NAMES_FILE"
