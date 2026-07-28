#!/bin/sh
# Background daemon: maintains @agent_tally, a global "⛔N 💬N ✅N" count of the
# agent states that need you — blocked / waiting-for-input / done — rendered as
# the leading block of status-left (see tmux.conf). Working/thinking agents are
# intentionally not counted. It also owns a per-window @agent_visited flag used
# to split the "waiting for input" state.
#
# Per-window state is rendered directly by the window-status format (which
# colors each entry from its own @workmux_status + @agent_visited); this daemon
# AGGREGATES for the tally (a tmux format can't count across windows) and writes
# @agent_visited (a tmux format can't set options).
#
# States:
#   @workmux_status  @agent_visited  meaning                       glyph  fill
#   🤖 (working)      -               thinking                       🤖     light blue
#   ⛔ (waiting)      -               blocked on permission          ⛔     red
#   💬 (done)         0/unset         finished, you haven't looked   💬     yellow
#   💬 (done)         1               finished, you looked = done    ✅     green
#   (none)           -               idle / no agent                -      grey
#
# "Visited" = you focused the window while it was in the 💬 waiting state; we
# then demote it from yellow (needs you) to green ✅ (done). The flag resets
# whenever the window leaves 💬 (e.g. you type -> working), so the NEXT time it
# finishes it is yellow-unseen again.
#
# How it works:
#   - Launched from tmux.conf via `run-shell -b` (runs in background)
#   - Every 1s reads @workmux_status for every window (set by workmux from the
#     Claude Code hooks in ~/.claude/settings.json)
#   - Every few ticks, BACKFILLS empty @workmux_status options from
#     `workmux status --json` (workmux's persistent per-agent state) — the
#     hook-set option is ephemeral (wiped on tmux restart, auto-cleared by
#     workmux on focus), so without this idle/done agents would silently show
#     grey. Only blanks are filled; live hook-set values are never overwritten.
#   - The tally excludes windows any client is currently viewing
#   - Pushes a status refresh only when something changed, so the bar reflects
#     activity within ~1s without redrawing on every idle tick
#
# Single instance: kills previous instances (via pgrep) on startup.

WORKING_STATUS="${WORKING_STATUS:-🤖}"
BLOCKED_STATUS="${BLOCKED_STATUS:-⛔}"
INPUT_STATUS="${INPUT_STATUS:-💬}"
DONE_GLYPH="✅"   # derived "visited while waiting" state; not a workmux status
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
BLOCKING_PROMPT_CLASSIFIER="$SCRIPT_DIR/agent-blocking-prompt.sh"
PANE_CHILD_COMMANDS="$SCRIPT_DIR/agent-pane-child-commands.sh"

# Kill previous instances (exclude self)
for pid in $(pgrep -f "tmux-claude-status\.sh"); do
  [ "$pid" != "$$" ] && kill "$pid" 2>/dev/null
done

# Render one tally segment. A non-zero count gets the colored background fill;
# a zero count gets dim grey text and NO fill, so empty buckets don't draw the
# eye. Args: <bg-color> <glyph> <count>.
segment() {
  if [ "$3" -gt 0 ]; then
    printf '#[bg=%s,fg=colour16] %s%s ' "$1" "$2" "$3"
  else
    printf '#[default]#[fg=colour244] %s%s ' "$2" "$3"
  fi
}

# @workmux_status is an ephemeral tmux option — wiped on a tmux restart and
# auto-cleared by workmux on window focus — so an idle/done agent can silently
# lose its status and render grey. Every RESYNC_EVERY ticks we BACKFILL empty
# options from `workmux status --json` (workmux's persistent per-agent state,
# reporting working / waiting / done by pane_id). It only fills blanks — live,
# hook-set values are left untouched so we never race the hooks. Sets the global
# resync_changed=1 on any update.
RESYNC_EVERY=4
JQ=$(command -v jq 2>/dev/null)
WORKMUX_BIN=$(command -v workmux 2>/dev/null)

resync_from_workmux() {
  [ -n "$JQ" ] && [ -n "$WORKMUX_BIN" ] || return
  pane_map=$(tmux list-panes -a -F "#{pane_id} #{session_name}:#{window_index}" 2>/dev/null)
  # workmux status is repo-scoped; running it from each window's cwd covers
  # every repo (duplicates just re-set the same value). cwds may contain spaces,
  # so fetch per-window via display-message rather than word-splitting a list.
  for win in $(tmux list-windows -a -F "#{session_name}:#{window_index}" 2>/dev/null); do
    cwd=$(tmux display-message -t "$win" -p "#{pane_current_path}" 2>/dev/null)
    json=$(cd "$cwd" 2>/dev/null && "$WORKMUX_BIN" status --json 2>/dev/null) || continue
    case "$json" in \[*) ;; *) continue ;; esac
    lines=$(printf '%s' "$json" | "$JQ" -r '.[] | "\(.pane_id) \(.status)"' 2>/dev/null)
    [ -n "$lines" ] || continue
    OLDIFS=$IFS
    IFS='
'
    for line in $lines; do
      pane=${line%% *}
      st=${line#* }
      case "$st" in
        working) icon="$WORKING_STATUS" ;;
        waiting) icon="$BLOCKED_STATUS" ;;
        done)    icon="$INPUT_STATUS" ;;
        *) continue ;;
      esac
      twin=$(printf '%s\n' "$pane_map" | awk -v p="$pane" '$1==p{print $2; exit}')
      [ -n "$twin" ] || continue
      # Backfill ONLY when the option is empty (wiped by a restart or workmux's
      # focus-clear). Never overwrite a live, hook-set value — otherwise we race
      # the Claude hooks and the entry flickers between states.
      cur=$(tmux show -wqv -t "$twin" @workmux_status 2>/dev/null)
      if [ -z "$cur" ]; then
        tmux set -w -t "$twin" @workmux_status "$icon" 2>/dev/null
        resync_changed=1
      fi
    done
    IFS=$OLDIFS
  done
}

prev_tally="__init__"
tick=0

while true; do
  resync_changed=0
  tick=$((tick + 1))
  [ $((tick % RESYNC_EVERY)) -eq 1 ] && resync_from_workmux

  # Windows any client is currently viewing — excluded from the tally counts,
  # but still eligible to be marked visited below.
  active=$(tmux list-clients -F "#{session_name}:#{window_index}" 2>/dev/null)

  blocked=0
  awaiting_input=0
  done_seen=0
  changed=0
  for win in $(tmux list-windows -a -F "#{session_name}:#{window_index}" 2>/dev/null); do
    vals=$(tmux display-message -t "$win" -p "#{@workmux_status}|#{@agent_visited}|#{@agent_prev}" 2>/dev/null)
    status=${vals%%|*}
    rest=${vals#*|}
    visited=${rest%%|*}
    prev=${rest#*|}

    # Claude reports permission prompts through hooks. Codex does not, so
    # detect its confirmation dialog from the visible pane and temporarily
    # override the window state. Remember the previous state and restore it
    # only if our override is still present after the dialog disappears.
    codex_prompt_blocked=0
    pane_metadata=$(tmux display-message -t "$win" -p "#{pane_pid}|#{pane_current_command}" 2>/dev/null)
    pane_pid=${pane_metadata%%|*}
    pane_command=${pane_metadata#*|}
    pane_child_commands=
    if [ "$pane_command" = "node" ]; then
      pane_child_commands=$(sh "$PANE_CHILD_COMMANDS" "$pane_pid")
    fi
    case "$pane_command" in
      codex|node)
      if tmux capture-pane -t "$win" -p 2>/dev/null \
        | sh "$BLOCKING_PROMPT_CLASSIFIER" "$pane_command" "$pane_child_commands"; then
        codex_prompt_blocked=1
      fi
      ;;
    esac
    codex_prompt_marker=$(tmux show -wqv -t "$win" @agent_codex_prompt_blocked 2>/dev/null)
    codex_previous_status=$(tmux show -wqv -t "$win" @agent_codex_prompt_previous 2>/dev/null)

    if [ "$codex_prompt_blocked" = 1 ]; then
      if [ "$status" != "$BLOCKED_STATUS" ]; then
        if [ "$codex_prompt_marker" != 1 ]; then
          tmux set -w -t "$win" @agent_codex_prompt_previous "$status" 2>/dev/null
          tmux set -w -t "$win" @agent_codex_prompt_blocked 1 2>/dev/null
        fi
        tmux set -w -t "$win" @workmux_status "$BLOCKED_STATUS" 2>/dev/null
        status="$BLOCKED_STATUS"
        changed=1
      fi
    elif [ "$codex_prompt_marker" = 1 ]; then
      tmux set -wu -t "$win" @agent_codex_prompt_blocked 2>/dev/null
      tmux set -wu -t "$win" @agent_codex_prompt_previous 2>/dev/null
      if [ "$status" = "$BLOCKED_STATUS" ]; then
        if [ -n "$codex_previous_status" ]; then
          tmux set -w -t "$win" @workmux_status "$codex_previous_status" 2>/dev/null
        else
          tmux set -wu -t "$win" @workmux_status 2>/dev/null
        fi
        status="$codex_previous_status"
        changed=1
      fi
    fi

    is_active=0
    for a in $active; do
      [ "$win" = "$a" ] && { is_active=1; break; }
    done

    # Maintain the visited flag (= "you've seen this finished agent → done"):
    #   - genuine new activity (working/blocked) clears it
    #   - focusing it while it's waiting (💬) sets it
    #   - also catch workmux's own auto-clear-on-focus (sidebar/dashboard): if
    #     it wiped 💬 to empty between polls, prev==💬 on the focused window
    # We deliberately do NOT clear on a bare empty status, so "done" sticks.
    case "$status" in
      "$WORKING_STATUS"|"$BLOCKED_STATUS")
        if [ "$visited" = 1 ]; then
          tmux set -w -t "$win" @agent_visited 0 2>/dev/null
          visited=0; changed=1
        fi
        ;;
      "$INPUT_STATUS")
        if [ "$is_active" = 1 ] && [ "$visited" != 1 ]; then
          tmux set -w -t "$win" @agent_visited 1 2>/dev/null
          visited=1; changed=1
        fi
        ;;
      "")
        if [ "$is_active" = 1 ] && [ "$prev" = "$INPUT_STATUS" ] && [ "$visited" != 1 ]; then
          tmux set -w -t "$win" @agent_visited 1 2>/dev/null
          visited=1; changed=1
        fi
        ;;
    esac

    # Remember this tick's status for the next comparison.
    [ "$prev" != "$status" ] && tmux set -w -t "$win" @agent_prev "$status" 2>/dev/null

    # Count everything except the window you're viewing.
    [ "$is_active" = 1 ] && continue
    # Working/thinking is intentionally not tallied — we only flag what needs
    # you: blocked, waiting-for-input, done.
    if [ "$visited" = 1 ]; then
      done_seen=$((done_seen + 1))
    else
      case "$status" in
        "$BLOCKED_STATUS") blocked=$((blocked + 1)) ;;
        "$INPUT_STATUS")   awaiting_input=$((awaiting_input + 1)) ;;
      esac
    fi
  done

  tally="$(segment red "$BLOCKED_STATUS" "$blocked")$(segment yellow "$INPUT_STATUS" "$awaiting_input")$(segment green "$DONE_GLYPH" "$done_seen")#[default]"

  if [ "$tally" != "$prev_tally" ] || [ "$changed" = 1 ] || [ "$resync_changed" = 1 ]; then
    tmux set -g @agent_tally "$tally" 2>/dev/null
    tmux refresh-client -S 2>/dev/null
    prev_tally="$tally"
  fi

  sleep 1
done
