#!/bin/bash
# Direct tmux session restore on server start.
# Bypasses tmux-continuum (which silently fails) and runs tmux-resurrect
# restore directly with full logging.

LOG="/tmp/tmux-auto-restore.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

# Atomic lock — prevents concurrent runs
LOCK="/tmp/tmux-auto-restore.lock"
exec 200>"$LOCK"
if ! flock -n 200; then
  exit 0
fi

log "=== auto-restore triggered ==="

# Guard: only restore once per server lifetime
already=$(/usr/bin/tmux show-option -gqv @auto-restore-done 2>/dev/null)
if [ "$already" = "1" ]; then
  log "already restored this server, skipping"
  exit 0
fi
# Set immediately — before any sleep
/usr/bin/tmux set-option -gq @auto-restore-done 1

# Guard: only restore within 60s of server start
start_time=$(/usr/bin/tmux display-message -p -F '#{start_time}' 2>/dev/null)
now=$(date +%s)
if [ -n "$start_time" ] && [ "$((now - start_time))" -gt 60 ]; then
  log "server too old (${start_time}, diff=$((now - start_time))s), skipping"
  exit 0
fi

# Wait for TPM to finish setting resurrect options
sleep 2

# Find the restore script — try tmux option first, then fallback paths
restore_script=$(/usr/bin/tmux show-option -gqv '@resurrect-restore-script-path' 2>/dev/null)
if [ -z "$restore_script" ] || [ ! -x "$restore_script" ]; then
  for candidate in \
    "$DOTS_HOME/all/tmux/plugins/tmux-resurrect/scripts/restore.sh" \
    "$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh"; do
    if [ -x "$candidate" ]; then
      restore_script="$candidate"
      break
    fi
  done
fi

if [ -z "$restore_script" ] || [ ! -x "$restore_script" ]; then
  log "ERROR: no restore script found"
  exit 1
fi

log "restore script: $restore_script"

# Find and validate save file
resurrect_dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
if [ -d "$HOME/.tmux/resurrect" ]; then
  resurrect_dir="$HOME/.tmux/resurrect"
fi
last_file="$resurrect_dir/last"

if [ ! -f "$last_file" ]; then
  log "ERROR: no save file at $last_file"
  exit 1
fi

# Resolve the symlink to the actual file
actual_file="$resurrect_dir/$(readlink "$last_file" 2>/dev/null)"
if [ ! -s "$actual_file" ]; then
  log "ERROR: save file is empty: $actual_file"
  # Try to find the most recent non-empty save file
  actual_file=""
  for f in $(ls -t "$resurrect_dir"/tmux_resurrect_*.txt 2>/dev/null); do
    if [ -s "$f" ]; then
      actual_file="$f"
      log "found non-empty fallback: $f"
      # Fix the symlink so resurrect reads the right file
      ln -sf "$(basename "$f")" "$last_file"
      break
    fi
  done
  if [ -z "$actual_file" ]; then
    log "ERROR: no non-empty save files found"
    exit 1
  fi
fi

log "restoring from: $actual_file ($(wc -l < "$actual_file") lines)"

# Run restore — stderr goes to log, stdout left alone for tmux display-message
"$restore_script" 2>> "$LOG"
status=$?
log "restore exit code: $status"
log "=== auto-restore finished ==="
