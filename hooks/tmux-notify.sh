#!/usr/bin/env bash
# tmux pane notification hook for Claude Code.
#
# Adds a marker to the tmux window name when the agent stops (user's turn).
# Clears when the user submits a prompt. Multi-pane safe via per-pane
# @claude_waiting flags (0/1), clearing the marker only when no pane is still waiting.
#
# Configuration (tmux global options):
#   @claude_notify_marker   — emoji/string to use (default: +)
#   @claude_notify_position — "prepend" or "append" (default: prepend)
#
# Example:
#   tmux set -g @claude_notify_marker "🔄"
#   tmux set -g @claude_notify_position "append"
#
# Usage (called by Claude Code hooks, not directly):
#   tmux-notify.sh notify   # on Stop
#   tmux-notify.sh clear    # on UserPromptSubmit
set -euo pipefail

# Guard: silently exit if not running inside tmux.
[ -n "${TMUX_PANE:-}" ] || exit 0

DEFAULT_MARKER="+"
DEFAULT_POSITION="prepend"

MARKER=$(tmux show-option -gqv @claude_notify_marker 2>/dev/null) || true
MARKER="${MARKER:-$DEFAULT_MARKER}"
POSITION=$(tmux show-option -gqv @claude_notify_position 2>/dev/null) || true
POSITION="${POSITION:-$DEFAULT_POSITION}"

ACTION="${1:-}"

has_marker() {
  local name="$1" marker="$2" pos="$3"
  local marker_len=${#marker}
  [ "$marker_len" -gt 0 ] || return 1
  [ "${#name}" -ge "$marker_len" ] || return 1

  if [[ "$pos" == "append" ]]; then
    [[ "${name: -marker_len}" == "$marker" ]]
  else
    [[ "${name:0:marker_len}" == "$marker" ]]
  fi
}

strip_marker() {
  local name="$1" marker="$2" pos="$3"
  local marker_len=${#marker}

  if [[ "$pos" == "append" ]]; then
    echo "${name:0:${#name}-marker_len}"
  else
    echo "${name:marker_len}"
  fi
}

notify() {
  local pane="$TMUX_PANE"

  # Skip if already waiting (avoids redundant tmux calls on repeated Stop events).
  local cur
  cur=$(tmux display-message -t "$pane" -p '#{@claude_waiting}' 2>/dev/null) || exit 0
  [ "$cur" != "1" ] || return 0

  tmux set-option -p -t "$pane" @claude_waiting 1 2>/dev/null || exit 0

  local win name
  win=$(tmux display-message -t "$pane" -p '#{window_id}' 2>/dev/null) || exit 0
  name=$(tmux display-message -t "$pane" -p '#{window_name}' 2>/dev/null) || exit 0

  # Honor existing per-window marker if already applied (avoids double markers on config change).
  local active_marker active_position
  active_marker=$(tmux show-option -wqv -t "$win" @claude_applied_marker 2>/dev/null) || true
  active_position=$(tmux show-option -wqv -t "$win" @claude_applied_position 2>/dev/null) || true
  active_marker="${active_marker:-$MARKER}"
  active_position="${active_position:-$POSITION}"

  if ! has_marker "$name" "$active_marker" "$active_position"; then
    if [[ "$active_position" == "append" ]]; then
      tmux rename-window -t "$win" -- "${name}${active_marker}" 2>/dev/null || true
    else
      tmux rename-window -t "$win" -- "${active_marker}${name}" 2>/dev/null || true
    fi
    tmux set-option -w -t "$win" @claude_applied_marker "$active_marker" 2>/dev/null || true
    tmux set-option -w -t "$win" @claude_applied_position "$active_position" 2>/dev/null || true
  fi
}

clear_notify() {
  local pane="$TMUX_PANE"

  # Skip if this pane wasn't waiting (avoids unnecessary tmux calls on every prompt).
  local cur
  cur=$(tmux display-message -t "$pane" -p '#{@claude_waiting}' 2>/dev/null) || exit 0
  [ "$cur" = "1" ] || return 0

  tmux set-option -p -t "$pane" @claude_waiting 0 2>/dev/null || exit 0

  local win name
  win=$(tmux display-message -t "$pane" -p '#{window_id}' 2>/dev/null) || exit 0
  name=$(tmux display-message -t "$pane" -p '#{window_name}' 2>/dev/null) || exit 0

  # Check if any other pane in this window is still waiting.
  local waiting_flags
  waiting_flags=$(tmux list-panes -t "$win" -F '#{@claude_waiting}' 2>/dev/null) || exit 0

  if echo "$waiting_flags" | grep -q '^1$'; then
    return 0
  fi

  # Only strip if per-window applied state exists (avoids stripping markers we didn't add).
  local applied_marker applied_position
  applied_marker=$(tmux show-option -wqv -t "$win" @claude_applied_marker 2>/dev/null) || true
  applied_position=$(tmux show-option -wqv -t "$win" @claude_applied_position 2>/dev/null) || true
  [ -n "$applied_marker" ] || return 0

  if ! has_marker "$name" "$applied_marker" "$applied_position"; then
    return 0
  fi

  tmux rename-window -t "$win" -- "$(strip_marker "$name" "$applied_marker" "$applied_position")" 2>/dev/null || true
  tmux set-option -wu -t "$win" @claude_applied_marker 2>/dev/null || true
  tmux set-option -wu -t "$win" @claude_applied_position 2>/dev/null || true
}

case "$ACTION" in
  notify) notify ;;
  clear)  clear_notify ;;
  *)
    echo "Usage: tmux-notify.sh {notify|clear}" >&2
    exit 1
    ;;
esac
