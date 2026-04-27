#!/bin/sh
# Restore @custom_name for all panes from saved file.
# Called via @resurrect-hook-pre-restore-pane-processes.

LOG="/tmp/tmux-restore-pane-names.log"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

NAMES_FILE="$HOME/.local/share/tmux/resurrect/pane_names.txt"
log "=== restore hook fired ==="
log "NAMES_FILE=$NAMES_FILE exists=$([ -f "$NAMES_FILE" ] && echo yes || echo no)"

[ -f "$NAMES_FILE" ] || { log "no names file, exiting"; exit 0; }

log "contents: $(cat "$NAMES_FILE")"
log "current panes: $(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}' 2>&1)"

while IFS= read -r line; do
  pane=$(echo "$line" | cut -d' ' -f1)
  name=$(echo "$line" | cut -d' ' -f2-)
  result=$(tmux set -t "$pane" -p @custom_name "$name" 2>&1)
  log "set '$pane' -> '$name' result='$result'"
done < "$NAMES_FILE"

log "verify: $(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} name=#{@custom_name}' 2>&1)"
log "=== restore hook done ==="
