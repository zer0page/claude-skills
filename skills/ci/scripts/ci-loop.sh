#!/usr/bin/env bash
# ci-loop.sh — Poll CI/reviews until resolved, fetch details.
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
  echo '{"error":"ci-poll.sh not found at '"$SCRIPT_DIR"'"}'
  exit 0
fi

# --- Argument parsing ---
PR=""
REPO=""
SHA=""
REVIEW_BOT=""
TIMEOUT=600  # 10 minutes default

needs_arg() { if [ $# -lt 2 ] || [ -z "$2" ]; then echo "Missing value for $1" >&2; exit 1; fi; }
while [ $# -gt 0 ]; do
  case "$1" in
    --pr)         needs_arg "$@"; PR="$2";         shift 2 ;;
    --repo)       needs_arg "$@"; REPO="$2";       shift 2 ;;
    --sha)        needs_arg "$@"; SHA="$2";        shift 2 ;;
    --review-bot) needs_arg "$@"; REVIEW_BOT="$2"; shift 2 ;;
    --timeout)    needs_arg "$@"; TIMEOUT="$2";    shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$PR" ] || [ -z "$REPO" ] || [ -z "$SHA" ]; then
  echo "Usage: ci-loop.sh --pr PR --repo OWNER/NAME --sha SHA [--review-bot BOT] [--timeout SECS]" >&2
  exit 1
fi

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

# Validate timeout (must be positive integer)
case "$TIMEOUT" in
  ''|*[!0-9]*) echo '{"error":"--timeout must be a positive integer"}'; exit 0 ;;
esac
if [ "$TIMEOUT" -le 0 ]; then echo '{"error":"--timeout must be greater than 0"}'; exit 0; fi

# --- Build poll args (array for safe quoting) ---
POLL_ARGS=(--pr "$PR" --repo "$REPO" --sha "$SHA")
if [ -n "$REVIEW_BOT" ]; then
  POLL_ARGS+=(--review-bot "$REVIEW_BOT")
fi

# --- Request review bot (validation happens in ci-poll.sh) ---
if [ -n "$REVIEW_BOT" ]; then
  for attempt in 1 2 3; do
    if gh api "repos/$OWNER/$NAME/pulls/$PR/requested_reviewers" \
        -X POST -f "reviewers[]=$REVIEW_BOT" >/dev/null 2>&1; then
      break
    fi
    sleep $((attempt * 2))
  done
fi

# --- Polling loop: exit when all checks resolved and review resolved ---
elapsed=0
poll_result=""
timed_out=false

while [ $elapsed -lt "$TIMEOUT" ]; do
  poll_result=$(bash "$POLL_SCRIPT" "${POLL_ARGS[@]}" 2>/dev/null) || poll_result='{"error":"ci-poll.sh failed"}'

  # Check for error or SHA mismatch — exit immediately
  has_error=$(echo "$poll_result" | jq -r '.error // empty')
  sha_match=$(echo "$poll_result" | jq -r '.sha_match')
  [ -n "$has_error" ] && break
  [ "$sha_match" = "false" ] && break

  # Check if all checks are resolved
  check_pending=0
  if [ "$(echo "$poll_result" | jq 'has("checks")')" = "true" ]; then
    check_pending=$(echo "$poll_result" | jq '[.checks[] | select(.resolved == false)] | length')
  fi

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
has_checks=$(echo "$poll_result" | jq 'has("checks")')
failed_count=0
if [ "$has_checks" = "true" ]; then
  failed_count=$(echo "$poll_result" | jq '[.checks[] | select(.resolved == true and .state != "SUCCESS" and .state != "NEUTRAL")] | length')
fi

if [ "$failed_count" -gt 0 ]; then
  # CheckRun failures — fetch logs via gh run view (tolerant of non-Actions URLs)
  while IFS= read -r url; do
    [ -z "$url" ] && continue
    run_id=$(echo "$url" | grep -oE '/actions/runs/[0-9]+' | grep -oE '[0-9]+' | head -1 || true)
    if [ -n "$run_id" ]; then
      logs=$(gh run view "$run_id" -R "$REPO" --log-failed 2>/dev/null || echo "[failed to fetch logs for run $run_id]")
      ci_logs="${ci_logs}${ci_logs:+\n\n}--- Run $run_id ---\n$logs"
    else
      # Non-Actions CheckRun — treat like StatusContext, include URL
      ci_logs="${ci_logs}${ci_logs:+\n\n}--- CheckRun ---\nURL: $url"
    fi
  done < <(echo "$poll_result" | jq -r '.checks[] | select(.resolved == true and .state != "SUCCESS" and .state != "NEUTRAL") | select(.type == "CheckRun") | .url // empty')

  # StatusContext failures — include URL for LLM to WebFetch
  status_context_failures=$(echo "$poll_result" | jq -r '.checks[] | select(.resolved == true and .state != "SUCCESS" and .state != "NEUTRAL") | select(.type == "StatusContext") | "--- \(.name) (\(.state)) ---\nURL: \(.url)"')
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

# --- Fetch human comment details (batch — one API call, filter client-side) ---
human_comment_details="[]"
human_id_json=$(echo "$poll_result" | jq -c '.human_comment_ids // []')
human_ids=$(echo "$human_id_json" | jq 'length')

if [ "$human_ids" -gt 0 ]; then
  human_comment_details=$(gh api "repos/$OWNER/$NAME/pulls/$PR/comments" \
    --jq "[.[] | select(.id as \$id | $human_id_json | index(\$id)) | {id, path, body, user: .user.login}]" 2>/dev/null || echo "[]")
fi

# --- Output: ci-poll.sh data + fetched details ---
# All JSON fragments are clean — ci-poll.sh uses jq -n, gh api uses --jq internally
echo "$poll_result" | jq -c \
  --argjson timed_out "$timed_out" \
  --arg ci_logs "$ci_logs" \
  --argjson review_comments "$review_comments" \
  --argjson human_comment_details "$human_comment_details" \
  '. + {timed_out: $timed_out, ci_logs: $ci_logs, review_comments: $review_comments, human_comment_details: $human_comment_details}'
