#!/bin/sh
# Exit successfully when the captured pane text contains an active agent
# permission prompt. The pane's current command is the first argument, its
# direct child command lines are the optional second argument, and the captured
# text is read from stdin.

case "$1" in
  claude|codex|nvim|vim) ;;
  node)
    case "$2" in
      node\ */codex|node\ */codex\ *|*/node\ */codex|*/node\ */codex\ *) ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
esac

pane_text=$(cat)

case "$pane_text" in
  *"Do you want to proceed"* \
  | *"Would you like to proceed"* \
  | *"Would you like to run the following command?"* \
  | *"Esc to cancel"* \
  | *"requires confirmation for this command"* \
  | *"Do you want to allow Claude to fetch"*)
    exit 0
    ;;
esac

exit 1
