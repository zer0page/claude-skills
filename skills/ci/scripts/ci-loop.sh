#!/usr/bin/env bash
# ci-loop.sh — Poll CI/reviews, return on first actionable event.
#
# Usage: ci-loop.sh --pr PR --repo OWNER/NAME --sha SHA [--review-bot BOT]
#
# Returns ci-poll.sh output plus:
#   - "ci_logs": failure logs (CheckRun) or URLs (StatusContext)
#   - "review_comments": array of {id, path, body}
#   - "human_comment_details": array of {id, path, body, user}
#   - "review_bot_timeout": true if bot didn't respond within 10 min
#
# Requires: gh, jq, ci-poll.sh in the same directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLL_SCRIPT="$SCRIPT_DIR/ci-poll.sh"

if [ ! -f "$POLL_SCRIPT" ]; then
  echo '{"error":"ci-poll.sh not found at '"$SCRIPT_DIR"'"}'
  exit 0
fi

# --- Argument parsing ---
PR=""
REPO=""
SHA=""
REVIEW_BOT=""

needs_arg() { if [ $# -lt 2 ] || [ -z "$2" ]; then echo "Missing value for $1" >&2; exit 1; fi; }
while [ $# -gt 0 ]; do
  case "$1" in
    --pr)         needs_arg "$@"; PR="$2";         shift 2 ;;
    --repo)       needs_arg "$@"; REPO="$2";       shift 2 ;;
    --sha)        needs_arg "$@"; SHA="$2";        shift 2 ;;
    --review-bot) needs_arg "$@"; REVIEW_BOT="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$PR" ] || [ -z "$REPO" ] || [ -z "$SHA" ]; then
  echo "Usage: ci-loop.sh --pr PR --repo OWNER/NAME --sha SHA [--review-bot BOT]" >&2
  exit 1
fi

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

# --- Build poll args ---
POLL_ARGS=(--pr "$PR" --repo "$REPO" --sha "$SHA")
if [ -n "$REVIEW_BOT" ]; then
  POLL_ARGS+=(--review-bot "$REVIEW_BOT")
fi

# --- Request review bot ---
if [ -n "$REVIEW_BOT" ]; then
  for attempt in 1 2 3; do
    if gh api "repos/$OWNER/$NAME/pulls/$PR/requested_reviewers" \
        -X POST -f "reviewers[]=$REVIEW_BOT" >/dev/null 2>&1; then
      break
    fi
    sleep $((attempt * 2))
  done
fi

# --- Polling loop: return on first actionable event ---
poll_result=""
review_elapsed=0
review_resolved=true  # default: no bot configured = resolved
review_bot_timeout=false

[ -n "$REVIEW_BOT" ] && review_resolved=false

while true; do
  poll_result=$(bash "$POLL_SCRIPT" "${POLL_ARGS[@]}" 2>/dev/null) || poll_result='{"error":"ci-poll.sh failed"}'

  # Error or SHA mismatch — exit immediately
  has_error=$(echo "$poll_result" | jq -r '.error // empty')
  sha_match=$(echo "$poll_result" | jq -r '.sha_match')
  [ -n "$has_error" ] && break
  [ "$sha_match" = "false" ] && break

  # --- Reviews (only during 10-min window) ---
  if ! $review_resolved; then
    review_state=$(echo "$poll_result" | jq -r '.review_state // empty')
    review_comment_count=$(echo "$poll_result" | jq -r '.review_comment_count // 0')
    human_count=$(echo "$poll_result" | jq '[.human_comment_ids // [] | length] | .[0]')

    if [ -n "$review_state" ]; then
      review_resolved=true
      # Bot responded with comments → return immediately (actionable)
      if [ "$review_comment_count" -gt 0 ] || [ "$human_count" -gt 0 ]; then
        break
      fi
    elif [ $review_elapsed -ge 600 ]; then
      # 10-min timeout — re-request bot, flag, treat as resolved
      review_resolved=true
      review_bot_timeout=true
      gh api "repos/$OWNER/$NAME/pulls/$PR/requested_reviewers" \
        -X POST -f "reviewers[]=$REVIEW_BOT" >/dev/null 2>&1 || true
    fi
  fi

  # --- CI ---
  has_checks=$(echo "$poll_result" | jq 'has("checks")')
  if [ "$has_checks" = "true" ]; then
    check_pending=$(echo "$poll_result" | jq '[.checks[] | select(.resolved == false)] | length')

    if [ "$check_pending" -eq 0 ]; then
      # All checks resolved
      non_success=$(echo "$poll_result" | jq '[.checks[] | select(.resolved == true and .state != "SUCCESS" and .state != "NEUTRAL")] | length')

      if [ "$non_success" -gt 0 ]; then
        break  # CI failure — return
      fi

      if $review_resolved; then
        break  # Done — CI clean + reviews clean
      fi
    fi
  fi

  sleep 10
  review_elapsed=$((review_elapsed + 10))
done

# --- Fetch CI failure logs ---
ci_logs=""
has_checks=$(echo "$poll_result" | jq 'has("checks")')
if [ "$has_checks" = "true" ]; then
  failed_count=$(echo "$poll_result" | jq '[.checks[] | select(.resolved == true and .state != "SUCCESS" and .state != "NEUTRAL")] | length')

  if [ "$failed_count" -gt 0 ]; then
    while IFS= read -r url; do
      [ -z "$url" ] && continue
      run_id=$(echo "$url" | grep -oE '/actions/runs/[0-9]+' | grep -oE '[0-9]+' | head -1 || true)
      if [ -n "$run_id" ]; then
        logs=$(gh run view "$run_id" -R "$REPO" --log-failed 2>/dev/null || echo "[failed to fetch logs for run $run_id]")
        ci_logs="${ci_logs}${ci_logs:+\n\n}--- Run $run_id ---\n$logs"
      else
        ci_logs="${ci_logs}${ci_logs:+\n\n}--- CheckRun ---\nURL: $url"
      fi
    done < <(echo "$poll_result" | jq -r '.checks[] | select(.resolved == true and .state != "SUCCESS" and .state != "NEUTRAL") | select(.type == "CheckRun") | .url // empty')

    status_context_failures=$(echo "$poll_result" | jq -r '.checks[] | select(.resolved == true and .state != "SUCCESS" and .state != "NEUTRAL") | select(.type == "StatusContext") | "--- \(.name) (\(.state)) ---\nURL: \(.url)"')
    if [ -n "$status_context_failures" ]; then
      ci_logs="${ci_logs}${ci_logs:+\n\n}$status_context_failures"
    fi
  fi
fi

# --- Fetch review comments ---
review_comments="[]"
rc_count=$(echo "$poll_result" | jq -r '.review_comment_count // 0')
rid=$(echo "$poll_result" | jq -r '.review_id // empty')

if [ "$rc_count" -gt 0 ] && [ -n "$rid" ] && [ "$rid" != "null" ]; then
  review_comments=$(gh api "repos/$OWNER/$NAME/pulls/$PR/reviews/$rid/comments" \
    --jq '[.[] | {id, path, body}]' 2>/dev/null || echo "[]")
fi

# --- Fetch human comment details ---
human_comment_details="[]"
human_id_json=$(echo "$poll_result" | jq -c '.human_comment_ids // []')
human_ids=$(echo "$human_id_json" | jq 'length')

if [ "$human_ids" -gt 0 ]; then
  human_comment_details=$(gh api "repos/$OWNER/$NAME/pulls/$PR/comments" \
    --jq "[.[] | select(.id as \$id | $human_id_json | index(\$id)) | {id, path, body, user: .user.login}]" 2>/dev/null || echo "[]")
fi

# --- Output ---
echo "$poll_result" | jq -c \
  --argjson review_bot_timeout "$review_bot_timeout" \
  --arg ci_logs "$ci_logs" \
  --argjson review_comments "$review_comments" \
  --argjson human_comment_details "$human_comment_details" \
  '. + {review_bot_timeout: $review_bot_timeout, ci_logs: $ci_logs, review_comments: $review_comments, human_comment_details: $human_comment_details}'
