#!/usr/bin/env bash
# ci-loop.sh — Poll CI/reviews until actionable, then return with details.
# Wraps ci-poll.sh. Only returns when the LLM needs to act (fix or complete).
#
# Usage: ci-loop.sh --pr PR --repo OWNER/NAME --sha SHA [--review-bot BOT] [--timeout SECS]
#
# Returns JSON with ci-poll.sh output plus:
#   - "action": "fix_ci" | "fix_reviews" | "fix_both" | "done" | "error" | "stale" | "cancelled" | "timeout"
#   - "ci_logs": string (failure logs for CheckRun, empty for StatusContext)
#   - "review_comments": array of {id, path, body, user}
#   - "human_comment_details": array of {id, path, body, user}
#
# Requires: gh, jq, ci-poll.sh in the same directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLL_SCRIPT="$SCRIPT_DIR/ci-poll.sh"

if [ ! -f "$POLL_SCRIPT" ]; then
  echo '{"action":"error","error":"ci-poll.sh not found at '"$SCRIPT_DIR"'"}' >&2
  exit 1
fi

# --- Argument parsing ---
PR=""
REPO=""
SHA=""
REVIEW_BOT=""
TIMEOUT=600  # 10 minutes default

while [ $# -gt 0 ]; do
  case "$1" in
    --pr)         PR="$2";         shift 2 ;;
    --repo)       REPO="$2";       shift 2 ;;
    --sha)        SHA="$2";        shift 2 ;;
    --review-bot) REVIEW_BOT="$2"; shift 2 ;;
    --timeout)    TIMEOUT="$2";    shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$PR" ] || [ -z "$REPO" ] || [ -z "$SHA" ]; then
  echo "Usage: ci-loop.sh --pr PR --repo OWNER/NAME --sha SHA [--review-bot BOT] [--timeout SECS]" >&2
  exit 1
fi

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

# --- Build poll args ---
POLL_ARGS="--pr $PR --repo $REPO --sha $SHA"
if [ -n "$REVIEW_BOT" ]; then
  POLL_ARGS="$POLL_ARGS --review-bot $REVIEW_BOT"
fi

# --- Polling loop ---
elapsed=0
poll_result=""

while [ $elapsed -lt "$TIMEOUT" ]; do
  poll_result=$(bash "$POLL_SCRIPT" $POLL_ARGS 2>/dev/null) || poll_result='{"ci_status":"error"}'

  ci=$(echo "$poll_result" | jq -r '.ci_status')
  rv=$(echo "$poll_result" | jq -r '.review_bot.status')
  human_count=$(echo "$poll_result" | jq -r '.human_comments.count')

  # Immediate exit conditions
  case "$ci" in
    stale)     echo "$poll_result" | jq -c '. + {"action":"stale","ci_logs":"","review_comments":[],"human_comment_details":[]}'; exit 0 ;;
    error)     echo "$poll_result" | jq -c '. + {"action":"error","ci_logs":"","review_comments":[],"human_comment_details":[]}'; exit 0 ;;
    cancelled) echo "$poll_result" | jq -c '. + {"action":"cancelled","ci_logs":"","review_comments":[],"human_comment_details":[]}'; exit 0 ;;
  esac

  # Still pending — keep polling
  if [ "$ci" = "pending" ] || [ "$rv" = "pending" ]; then
    sleep 10
    elapsed=$((elapsed + 10))
    continue
  fi

  # Both resolved — break out to determine action
  break
done

# Timeout check
if [ $elapsed -ge "$TIMEOUT" ]; then
  echo "$poll_result" | jq -c '. + {"action":"timeout","ci_logs":"","review_comments":[],"human_comment_details":[]}'
  exit 0
fi

# --- Determine action and fetch details ---
ci=$(echo "$poll_result" | jq -r '.ci_status')
rv=$(echo "$poll_result" | jq -r '.review_bot.status')
review_comment_count=$(echo "$poll_result" | jq -r '.review_bot.comment_count')
human_count=$(echo "$poll_result" | jq -r '.human_comments.count')

needs_ci_fix=false
needs_review_fix=false

[ "$ci" = "failed" ] && needs_ci_fix=true
{ [ "$rv" = "failed" ] || [ "$human_count" -gt 0 ]; } && needs_review_fix=true

# --- Fetch CI failure logs ---
ci_logs=""
if $needs_ci_fix; then
  # Collect logs for CheckRun failures (GitHub Actions)
  checkrun_ids=$(echo "$poll_result" | jq -r '.failed_checks[] | select(.type == "CheckRun") | .url' | while read -r url; do
    # Extract run ID from URL pattern: /actions/runs/<ID>/job/...
    echo "$url" | grep -oE '/actions/runs/[0-9]+' | grep -oE '[0-9]+' | head -1
  done | sort -u)

  for run_id in $checkrun_ids; do
    if [ -n "$run_id" ]; then
      logs=$(gh run view "$run_id" -R "$REPO" --log-failed 2>/dev/null || echo "[failed to fetch logs for run $run_id]")
      ci_logs="${ci_logs}${ci_logs:+\n\n}--- Run $run_id ---\n$logs"
    fi
  done

  # For StatusContext failures, include the URL (LLM will WebFetch)
  status_context_failures=$(echo "$poll_result" | jq -r '.failed_checks[] | select(.type == "StatusContext") | "--- \(.name) (\(.state)) ---\nURL: \(.url)"')
  if [ -n "$status_context_failures" ]; then
    ci_logs="${ci_logs}${ci_logs:+\n\n}$status_context_failures"
  fi
fi

# --- Fetch review comments ---
review_comments="[]"
if [ "$rv" = "failed" ] && [ "$review_comment_count" -gt 0 ]; then
  review_id=$(echo "$poll_result" | jq -r '.review_bot.review_id')
  if [ -n "$review_id" ] && [ "$review_id" != "null" ]; then
    review_comments=$(gh api "repos/$OWNER/$NAME/pulls/$PR/reviews/$review_id/comments" \
      --jq '[.[] | {id, path, body}]' 2>/dev/null || echo "[]")
  fi
fi

# --- Fetch human comment details ---
human_comment_details="[]"
if [ "$human_count" -gt 0 ]; then
  comment_ids=$(echo "$poll_result" | jq -r '.human_comments.comment_ids[]')
  details="["
  first=true
  for cid in $comment_ids; do
    if [ -n "$cid" ]; then
      detail=$(gh api "repos/$OWNER/$NAME/pulls/comments/$cid" \
        --jq '{id, path, body, user: .user.login}' 2>/dev/null || echo "null")
      if [ "$detail" != "null" ]; then
        $first || details="$details,"
        details="$details$detail"
        first=false
      fi
    fi
  done
  details="$details]"
  human_comment_details="$details"
fi

# --- Determine action ---
action="done"
if $needs_ci_fix && $needs_review_fix; then
  action="fix_both"
elif $needs_review_fix; then
  action="fix_reviews"
elif $needs_ci_fix; then
  action="fix_ci"
fi

# --- Assemble output ---
# Use jq for safe JSON construction (handles escaping ci_logs properly)
echo "$poll_result" | jq -c \
  --arg action "$action" \
  --arg ci_logs "$ci_logs" \
  --argjson review_comments "$review_comments" \
  --argjson human_comment_details "$human_comment_details" \
  '. + {action: $action, ci_logs: $ci_logs, review_comments: $review_comments, human_comment_details: $human_comment_details}'
