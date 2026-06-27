#!/bin/sh
# Wrapper around tmux-resurrect save that:
# 1. Skips saving during the first 30s after server start (let restore run)
# 2. Throttles saves to at most once per 60s

now=$(date +%s)

# Resolve the tmux binary — run-shell hooks may run with a minimal PATH that
# lacks the Homebrew prefix (/opt/homebrew, /usr/local) where tmux lives on
# macOS. A bare `tmux` that fails to resolve would silently disable saving.
TMUX_BIN=$(command -v tmux 2>/dev/null)
for candidate in "$TMUX_BIN" /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux; do
  if [ -x "$candidate" ]; then
    TMUX_BIN="$candidate"
    break
  fi
done

# Skip if restore hasn't finished yet
restore_done=$("$TMUX_BIN" show-option -gqv @auto-restore-done 2>/dev/null)
if [ "$restore_done" != "1" ]; then
  exit 0
fi

start_time=$("$TMUX_BIN" display-message -p '#{start_time}' 2>/dev/null)
# If start_time is empty or non-numeric, default to 0 (allows save)
case "$start_time" in
  ''|*[!0-9]*) start_time=$now ;;  # can't determine age → assume just started
esac
if [ "$((now - start_time))" -lt 30 ]; then
  exit 0
fi

last_save=$("$TMUX_BIN" show-option -gqv @resurrect-last-save-time 2>/dev/null)
if [ -n "$last_save" ] && [ "$((now - last_save))" -lt 60 ]; then
  exit 0
fi

"$TMUX_BIN" set-option -gq @resurrect-last-save-time "$now"
# Don't exec — we want to inspect the exit code and fail loudly if the save
# bombs, rather than letting a broken save silently mean "no persistence".
if ! "$DOTS_HOME/all/tmux/plugins/tmux-resurrect/scripts/save.sh" quiet; then
  "$TMUX_BIN" set-option -gq @resurrect-save-error "save failed at $now"
  "$TMUX_BIN" display-message -d 0 "⛔ tmux-resurrect SAVE failed — sessions will NOT persist on restart"
  exit 1
fi
