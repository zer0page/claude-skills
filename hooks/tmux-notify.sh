#!/usr/bin/env bash
# tmux pane notification hook for Claude Code.
#
# Prepends a ❓ to the tmux window name when the agent stops (user's turn).
# Clears when the user submits a prompt. Multi-pane safe via per-pane
# @waiting user option (reference counting).
#
# Usage (called by Claude Code hooks, not directly):
#   tmux-notify.sh notify   # on Stop
#   tmux-notify.sh clear    # on UserPromptSubmit
set -euo pipefail

# Guard: silently exit if not running inside tmux.
[ -n "${TMUX_PANE:-}" ] || exit 0

MARKER="❓"
ACTION="${1:-}"

notify() {
  local pane="$TMUX_PANE"

  # Mark this pane as waiting.
  tmux set-option -p -t "$pane" @waiting 1 2>/dev/null || exit 0

  # Get the window id and name for this pane.
  local win name
  win=$(tmux display-message -t "$pane" -p '#{window_id}' 2>/dev/null) || exit 0
  name=$(tmux display-message -t "$pane" -p '#{window_name}' 2>/dev/null) || exit 0

  # Prepend marker if not already present.
  if [[ "$name" != "${MARKER}"* ]]; then
    tmux rename-window -t "$win" -- "${MARKER} ${name}" 2>/dev/null || true
  fi
}

clear_notify() {
  local pane="$TMUX_PANE"

  # Clear this pane's waiting flag.
  tmux set-option -p -t "$pane" @waiting 0 2>/dev/null || exit 0

  # Get the window id and name.
  local win name
  win=$(tmux display-message -t "$pane" -p '#{window_id}' 2>/dev/null) || exit 0
  name=$(tmux display-message -t "$pane" -p '#{window_name}' 2>/dev/null) || exit 0

  # Check if any pane in this window is still waiting (single tmux call).
  local waiting_flags
  waiting_flags=$(tmux list-panes -t "$win" -F '#{@waiting}' 2>/dev/null) || exit 0

  if echo "$waiting_flags" | grep -q '^1$'; then
    # At least one pane still waiting — keep the marker.
    return 0
  fi

  # No panes waiting — remove the marker.
  if [[ "$name" == "${MARKER} "* ]]; then
    tmux rename-window -t "$win" -- "${name#${MARKER} }" 2>/dev/null || true
  fi
}

case "$ACTION" in
  notify) notify ;;
  clear)  clear_notify ;;
  *)
    echo "Usage: tmux-notify.sh {notify|clear}" >&2
    exit 1
    ;;
esac
