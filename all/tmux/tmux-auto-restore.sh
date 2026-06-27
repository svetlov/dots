#!/bin/bash
# Direct tmux session restore on server start.
# Bypasses tmux-continuum (which silently fails) and runs tmux-resurrect
# restore directly with full logging.

LOG="/tmp/tmux-auto-restore.log"
FAIL_MARKER="/tmp/tmux-auto-restore.FAILED"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

# Fail LOUD. This whole mechanism rotted silently for months because broken
# paths just `exit 0`'d into the void. So on any real error, surface it through
# every channel available: the log, a marker file (visible even with no usable
# tmux, e.g. picked up by a shell prompt hook), a sticky tmux option, and an
# on-screen message that stays until dismissed.
fail() {
  msg="$1"
  log "FATAL: $msg"
  printf '%s tmux restore FAILED: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" > "$FAIL_MARKER"
  if [ -n "$TMUX_BIN" ] && [ -x "$TMUX_BIN" ]; then
    "$TMUX_BIN" set-option -gq @auto-restore-error "$msg"
    # -d 0 = stay until a key is pressed (loud, not a 750ms flash).
    "$TMUX_BIN" display-message -d 0 "⛔ tmux restore FAILED: $msg — see $LOG"
  fi
  exit 1
}

# Clear any stale failure marker from a previous boot before we start.
rm -f "$FAIL_MARKER"

# Resolve the tmux binary. Homebrew installs to /opt/homebrew or /usr/local on
# macOS, NOT /usr/bin — hardcoding /usr/bin/tmux silently breaks every option
# read/write below (including the @auto-restore-done flag). Prefer PATH, then
# known install locations.
TMUX_BIN=$(command -v tmux 2>/dev/null)
for candidate in "$TMUX_BIN" /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux; do
  if [ -x "$candidate" ]; then
    TMUX_BIN="$candidate"
    break
  fi
done
# No usable tmux means every option read/write below is a no-op — the exact
# silent-failure class that hid this bug. Bail loudly (fail() handles the
# no-tmux case via the marker file).
if [ -z "$TMUX_BIN" ] || [ ! -x "$TMUX_BIN" ]; then
  fail "no usable tmux binary found on PATH or in /opt/homebrew, /usr/local, /usr/bin"
fi

# Single-run lock. flock is Linux-only (absent on macOS), so use a portable
# mkdir-based lock instead — an atomic create that doubles as the guard.
LOCK="/tmp/tmux-auto-restore.lock.d"
if ! mkdir "$LOCK" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "=== auto-restore triggered ==="

# Guard: only restore once per server lifetime
already=$("$TMUX_BIN" show-option -gqv @auto-restore-done 2>/dev/null)
if [ "$already" = "1" ]; then
  log "already restored this server, skipping"
  exit 0
fi
# Guard: only restore within 60s of server start
start_time=$("$TMUX_BIN" display-message -p -F '#{start_time}' 2>/dev/null)
now=$(date +%s)
if [ -n "$start_time" ] && [ "$((now - start_time))" -gt 60 ]; then
  log "server too old (${start_time}, diff=$((now - start_time))s), skipping"
  exit 0
fi

# Wait for TPM to finish setting resurrect options
sleep 2

# Find the restore script — try tmux option first, then fallback paths
restore_script=$("$TMUX_BIN" show-option -gqv '@resurrect-restore-script-path' 2>/dev/null)
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
  fail "no tmux-resurrect restore script found (checked @resurrect-restore-script-path, \$DOTS_HOME, ~/.tmux)"
fi

log "restore script: $restore_script"

# Find and validate save file
resurrect_dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
if [ -d "$HOME/.tmux/resurrect" ]; then
  resurrect_dir="$HOME/.tmux/resurrect"
fi
last_file="$resurrect_dir/last"

if [ ! -f "$last_file" ]; then
  # Cold start: nothing to restore yet. Enable saves anyway, otherwise the
  # save wrapper (which gates on @auto-restore-done) never runs and no save
  # file is ever created — a permanent deadlock on a fresh machine.
  log "no save file at $last_file — nothing to restore; enabling saves"
  "$TMUX_BIN" set-option -gq @auto-restore-done 1
  exit 0
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
    log "no non-empty save files found — enabling saves"
    "$TMUX_BIN" set-option -gq @auto-restore-done 1
    exit 0
  fi
fi

log "restoring from: $actual_file ($(wc -l < "$actual_file") lines)"

# Run restore — stderr goes to log, stdout left alone for tmux display-message
"$restore_script" 2>> "$LOG"
status=$?
log "restore exit code: $status"

if [ "$status" -ne 0 ]; then
  # Do NOT enable saves: a partial/failed restore must not overwrite the good
  # save file. Leave it intact for a retry and shout about it.
  fail "restore script exited $status (save file preserved for retry) — see $LOG"
fi

# Mark restore as complete — saves are now allowed
"$TMUX_BIN" set-option -gq @auto-restore-done 1

log "=== auto-restore finished ==="
