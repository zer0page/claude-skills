#!/usr/bin/env bash
# ci-loop.sh — Poll CI/reviews until resolved, fetch details, return raw data.
# Wraps ci-poll.sh. No interpretation — returns GitHub API data directly.
#
# Usage: ci-loop.sh --pr PR --repo OWNER/NAME --sha SHA [--review-bot BOT] [--timeout SECS]
#
# Returns ci-poll.sh output (raw GitHub data) plus:
#   - "ci_logs": failure logs from gh run view --log-failed (CheckRun) or URLs (StatusContext)
#   - "review_comments": array of review comment objects from GitHub API
#   - "human_comment_details": array of PR comment objects from GitHub API
#   - "timed_out": true if polling hit the timeout
#
# Requires: gh, jq, ci-poll.sh in the same directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLL_SCRIPT="$SCRIPT_DIR/ci-poll.sh"

if [ ! -f "$POLL_SCRIPT" ]; then
  echo '{"error":"ci-poll.sh not found at '"$SCRIPT_DIR"'"}' >&2
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

# --- Polling loop: exit when all checks resolved and review resolved ---
elapsed=0
poll_result=""
timed_out=false

while [ $elapsed -lt "$TIMEOUT" ]; do
  poll_result=$(bash "$POLL_SCRIPT" $POLL_ARGS 2>/dev/null) || poll_result='{"error":"ci-poll.sh failed"}'

  # Check for error or SHA mismatch — exit immediately
  has_error=$(echo "$poll_result" | jq -r '.error // empty')
  sha_match=$(echo "$poll_result" | jq -r '.sha_match // empty')
  [ -n "$has_error" ] && break
  [ "$sha_match" = "false" ] && break

  # Check if all checks are resolved (pending == 0)
  check_pending=$(echo "$poll_result" | jq -r '.check_counts.pending // 0')

  # Check if review bot has responded (review_state is non-null, or no bot configured)
  review_state=$(echo "$poll_result" | jq -r '.review_state // empty')
  if [ -n "$REVIEW_BOT" ]; then
    review_resolved=false
    [ -n "$review_state" ] && review_resolved=true
  else
    review_resolved=true
  fi

  # Both resolved — break
  if [ "$check_pending" -eq 0 ] && $review_resolved; then
    break
  fi

  sleep 10
  elapsed=$((elapsed + 10))
done

if [ $elapsed -ge "$TIMEOUT" ]; then
  timed_out=true
fi

# --- Fetch CI failure logs (raw gh output) ---
ci_logs=""
failed_count=$(echo "$poll_result" | jq -r '.check_counts.failed // 0')

if [ "$failed_count" -gt 0 ]; then
  # CheckRun failures — fetch logs via gh run view
  checkrun_ids=$(echo "$poll_result" | jq -r '.failed_checks[] | select(.type == "CheckRun") | .url' | while read -r url; do
    echo "$url" | grep -oE '/actions/runs/[0-9]+' | grep -oE '[0-9]+' | head -1
  done | sort -u)

  for run_id in $checkrun_ids; do
    if [ -n "$run_id" ]; then
      logs=$(gh run view "$run_id" -R "$REPO" --log-failed 2>/dev/null || echo "[failed to fetch logs for run $run_id]")
      ci_logs="${ci_logs}${ci_logs:+\n\n}--- Run $run_id ---\n$logs"
    fi
  done

  # StatusContext failures — include URL for LLM to WebFetch
  status_context_failures=$(echo "$poll_result" | jq -r '.failed_checks[] | select(.type == "StatusContext") | "--- \(.name) (\(.state)) ---\nURL: \(.url)"')
  if [ -n "$status_context_failures" ]; then
    ci_logs="${ci_logs}${ci_logs:+\n\n}$status_context_failures"
  fi
fi

# --- Fetch review comments (raw GitHub API response) ---
review_comments="[]"
review_comment_count=$(echo "$poll_result" | jq -r '.review_comment_count // 0')
review_id=$(echo "$poll_result" | jq -r '.review_id // empty')

if [ "$review_comment_count" -gt 0 ] && [ -n "$review_id" ] && [ "$review_id" != "null" ]; then
  review_comments=$(gh api "repos/$OWNER/$NAME/pulls/$PR/reviews/$review_id/comments" \
    --jq '[.[] | {id, path, body}]' 2>/dev/null || echo "[]")
fi

# --- Fetch human comment details (raw GitHub API response) ---
human_comment_details="[]"
human_ids=$(echo "$poll_result" | jq -r '.human_comment_ids | length // 0')

if [ "$human_ids" -gt 0 ]; then
  comment_ids=$(echo "$poll_result" | jq -r '.human_comment_ids[]')
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

# --- Output: ci-poll.sh data + fetched details ---
echo "$poll_result" | jq -c \
  --argjson timed_out "$timed_out" \
  --arg ci_logs "$ci_logs" \
  --argjson review_comments "$review_comments" \
  --argjson human_comment_details "$human_comment_details" \
  '. + {timed_out: $timed_out, ci_logs: $ci_logs, review_comments: $review_comments, human_comment_details: $human_comment_details}'
