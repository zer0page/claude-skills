#!/usr/bin/env bash
# ci-poll.sh — Single-shot CI/review status snapshot for a PR.
# Returns structured JSON. Designed to be called in a polling loop.
#
# Usage: ci-poll.sh --pr PR --repo OWNER/NAME --sha SHA [--review-bot BOT]
#
# Requires: gh, jq
set -euo pipefail

# --- Argument parsing ---
PR=""
REPO=""
SHA=""
REVIEW_BOT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pr)       PR="$2";         shift 2 ;;
    --repo)     REPO="$2";       shift 2 ;;
    --sha)      SHA="$2";        shift 2 ;;
    --review-bot) REVIEW_BOT="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$PR" ] || [ -z "$REPO" ] || [ -z "$SHA" ]; then
  echo "Usage: ci-poll.sh --pr PR --repo OWNER/NAME --sha SHA [--review-bot BOT]" >&2
  exit 1
fi

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

# --- Helper: safe gh call, returns empty string on failure ---
gh_safe() {
  gh "$@" 2>/dev/null || true
}

# --- 1. Validate PR head SHA ---
head_sha=$(gh_safe pr view "$PR" -R "$REPO" --json headRefOid --jq '.headRefOid')
if [ -z "$head_sha" ]; then
  printf '{"ci_status":"error","error":"failed to fetch PR head SHA","head_sha":""}\n'
  exit 0
fi

if [ "$head_sha" != "$SHA" ]; then
  printf '{"ci_status":"stale","head_sha":"%s","expected_sha":"%s"}\n' "$head_sha" "$SHA"
  exit 0
fi

# --- 2. Fetch statusCheckRollup ---
# Returns both CheckRun and StatusContext objects.
# CheckRun: resolved when status=="COMPLETED", conclusion from .conclusion
# StatusContext: resolved when state not in PENDING/EXPECTED, .state is conclusion
checks_json=$(gh_safe pr view "$PR" -R "$REPO" --json statusCheckRollup --jq '.statusCheckRollup')

if [ -z "$checks_json" ] || [ "$checks_json" = "null" ]; then
  checks_json="[]"
fi

# Normalize checks into uniform format
normalized=$(echo "$checks_json" | jq -c '[.[] | {
  name: (if .__typename == "CheckRun" then .name else .context end),
  type: .__typename,
  resolved: (if .__typename == "CheckRun" then (.status == "COMPLETED") else (.state != "PENDING" and .state != "EXPECTED") end),
  state: (if .__typename == "CheckRun" then (.conclusion // "PENDING") else .state end),
  url: (if .__typename == "CheckRun" then .detailsUrl else .targetUrl end)
}]')

# Compute summary
total=$(echo "$normalized" | jq 'length')
pending=$(echo "$normalized" | jq '[.[] | select(.resolved == false)] | length')
passed=$(echo "$normalized" | jq '[.[] | select(.resolved == true) | select(.state == "SUCCESS" or .state == "NEUTRAL" or .state == "SKIPPED")] | length')
failed=$(echo "$normalized" | jq '[.[] | select(.resolved == true) | select(.state == "FAILURE" or .state == "ERROR" or .state == "TIMED_OUT" or .state == "ACTION_REQUIRED")] | length')
cancelled=$(echo "$normalized" | jq '[.[] | select(.resolved == true) | select(.state == "CANCELLED")] | length')

# Determine ci_status
if [ "$pending" -gt 0 ]; then
  ci_status="pending"
elif [ "$failed" -gt 0 ]; then
  ci_status="failed"
elif [ "$cancelled" -gt 0 ] && [ "$passed" -eq 0 ]; then
  ci_status="cancelled"
else
  ci_status="clean"
fi

# Extract failed checks
failed_checks=$(echo "$normalized" | jq -c '[.[] | select(.resolved == true) | select(.state == "FAILURE" or .state == "ERROR" or .state == "TIMED_OUT" or .state == "ACTION_REQUIRED")]')

# --- 3. Fetch review bot status ---
review_json='{"status":"skipped","review_id":null,"comment_count":0}'

if [ -n "$REVIEW_BOT" ]; then
  # Use gh api --jq to avoid control character crashes from bot review bodies
  review_obj=$(gh api "repos/$OWNER/$NAME/pulls/$PR/reviews" \
    --jq "[.[] | select(.user.login == \"$REVIEW_BOT\") | select(.state != \"PENDING\") | select(.commit_id == \"$SHA\")] | last // empty" 2>/dev/null || true)

  if [ -z "$review_obj" ] || [ "$review_obj" = "null" ]; then
    review_json='{"status":"pending","review_id":null,"comment_count":0}'
  else
    review_id=$(echo "$review_obj" | jq -r '.id // empty')
    review_state=$(echo "$review_obj" | jq -r '.state // empty')

    comment_count=0
    if [ -n "$review_id" ] && [ "$review_id" != "null" ]; then
      comment_count=$(gh api "repos/$OWNER/$NAME/pulls/$PR/reviews/$review_id/comments" \
        --jq 'length' 2>/dev/null || echo "0")
    fi

    if [ "$review_state" = "APPROVED" ] || [ "$comment_count" -eq 0 ]; then
      review_status="clean"
    else
      review_status="failed"
    fi

    review_json=$(printf '{"status":"%s","review_id":%s,"comment_count":%s}' \
      "$review_status" \
      "$(echo "$review_id" | jq -R '.')" \
      "$comment_count")
  fi
fi

# --- 4. Fetch human review comments on latest commit ---
human_json='{"count":0,"comment_ids":[]}'

human_comments=$(gh api "repos/$OWNER/$NAME/pulls/$PR/comments" \
  --jq "[.[] | select(.commit_id == \"$SHA\" or .original_commit_id == \"$SHA\")$([ -n "$REVIEW_BOT" ] && echo " | select(.user.login != \"$REVIEW_BOT\")")] | [.[].id]" 2>/dev/null || echo "[]")

if [ -n "$human_comments" ] && [ "$human_comments" != "null" ]; then
  human_count=$(echo "$human_comments" | jq 'length')
  human_json=$(printf '{"count":%s,"comment_ids":%s}' "$human_count" "$human_comments")
fi

# --- 5. Fetch merge state ---
merge_state=$(gh_safe pr view "$PR" -R "$REPO" --json mergeStateStatus --jq '.mergeStateStatus')
if [ -z "$merge_state" ]; then
  merge_state="UNKNOWN"
fi

# --- 6. Assemble output ---
jq -n \
  --arg ci_status "$ci_status" \
  --argjson failed_checks "$failed_checks" \
  --argjson check_summary "{\"total\":$total,\"pending\":$pending,\"passed\":$passed,\"failed\":$failed}" \
  --argjson review_bot "$review_json" \
  --argjson human_comments "$human_json" \
  --arg merge_state "$merge_state" \
  --arg head_sha "$head_sha" \
  '{
    ci_status: $ci_status,
    failed_checks: $failed_checks,
    check_summary: $check_summary,
    review_bot: $review_bot,
    human_comments: $human_comments,
    merge_state: $merge_state,
    head_sha: $head_sha
  }'
