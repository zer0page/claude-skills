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

  # Skip if already waiting (avoids redundant tmux calls on repeated Stop events).
  local cur
  cur=$(tmux display-message -t "$pane" -p '#{@waiting}' 2>/dev/null) || exit 0
  [ "$cur" != "1" ] || return 0

  tmux set-option -p -t "$pane" @waiting 1 2>/dev/null || exit 0

  local win name
  win=$(tmux display-message -t "$pane" -p '#{window_id}' 2>/dev/null) || exit 0
  name=$(tmux display-message -t "$pane" -p '#{window_name}' 2>/dev/null) || exit 0

  if [[ "$name" != "${MARKER}"* ]]; then
    tmux rename-window -t "$win" -- "${MARKER} ${name}" 2>/dev/null || true
  fi
}

clear_notify() {
  local pane="$TMUX_PANE"

  # Skip if this pane wasn't waiting (avoids unnecessary tmux calls on every prompt).
  local cur
  cur=$(tmux display-message -t "$pane" -p '#{@waiting}' 2>/dev/null) || exit 0
  [ "$cur" = "1" ] || return 0

  tmux set-option -p -t "$pane" @waiting 0 2>/dev/null || exit 0

  local win name
  win=$(tmux display-message -t "$pane" -p '#{window_id}' 2>/dev/null) || exit 0
  name=$(tmux display-message -t "$pane" -p '#{window_name}' 2>/dev/null) || exit 0

  # Check if any other pane in this window is still waiting.
  local waiting_flags
  waiting_flags=$(tmux list-panes -t "$win" -F '#{@waiting}' 2>/dev/null) || exit 0

  if echo "$waiting_flags" | grep -q '^1$'; then
    return 0
  fi

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
