#!/usr/bin/env bash
# ci-poll.sh — Single-shot CI/review status snapshot for a PR.
# Returns normalized GitHub API data as JSON. No interpretation.
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
  printf '{"error":"failed to fetch PR head SHA"}\n'
  exit 0
fi

if [ "$head_sha" != "$SHA" ]; then
  printf '{"head_sha":"%s","expected_sha":"%s","sha_match":false}\n' "$head_sha" "$SHA"
  exit 0
fi

# --- 2. Fetch statusCheckRollup ---
# Normalizes CheckRun and StatusContext into a common schema.
# Field mapping only — states are passed through from GitHub unchanged.
checks_json=$(gh_safe pr view "$PR" -R "$REPO" --json statusCheckRollup --jq '.statusCheckRollup')

if [ -z "$checks_json" ] || [ "$checks_json" = "null" ]; then
  checks_json="[]"
fi

# Normalize into uniform format (schema mapping, not interpretation)
checks=$(echo "$checks_json" | jq -c '[.[] | {
  name: (if .__typename == "CheckRun" then .name else .context end),
  type: .__typename,
  resolved: (if .__typename == "CheckRun" then (.status == "COMPLETED") else (.state != "PENDING" and .state != "EXPECTED") end),
  state: (if .__typename == "CheckRun" then (.conclusion // "PENDING") else .state end),
  url: (if .__typename == "CheckRun" then .detailsUrl else .targetUrl end)
}]')

# Counts (arithmetic, not interpretation)
total=$(echo "$checks" | jq 'length')
pending=$(echo "$checks" | jq '[.[] | select(.resolved == false)] | length')
failed=$(echo "$checks" | jq '[.[] | select(.resolved == true) | select(.state == "FAILURE" or .state == "ERROR" or .state == "TIMED_OUT" or .state == "ACTION_REQUIRED")] | length')

# Failed checks list
failed_checks=$(echo "$checks" | jq -c '[.[] | select(.resolved == true) | select(.state == "FAILURE" or .state == "ERROR" or .state == "TIMED_OUT" or .state == "ACTION_REQUIRED")]')

# --- 3. Review bot ---
review_state="null"
review_id="null"
review_comment_count=0

if [ -n "$REVIEW_BOT" ]; then
  review_obj=$(gh api "repos/$OWNER/$NAME/pulls/$PR/reviews" \
    --jq "[.[] | select(.user.login == \"$REVIEW_BOT\") | select(.state != \"PENDING\") | select(.commit_id == \"$SHA\")] | last // empty" 2>/dev/null || true)

  if [ -n "$review_obj" ] && [ "$review_obj" != "null" ]; then
    review_id=$(echo "$review_obj" | jq -r '.id // empty')
    review_state=$(echo "$review_obj" | jq -r '.state // empty')

    if [ -n "$review_id" ] && [ "$review_id" != "null" ]; then
      review_comment_count=$(gh api "repos/$OWNER/$NAME/pulls/$PR/reviews/$review_id/comments" \
        --jq 'length' 2>/dev/null || echo "0")
    fi
  fi
fi

# --- 4. Human review comments on latest commit ---
human_comment_ids="[]"

human_comments=$(gh api "repos/$OWNER/$NAME/pulls/$PR/comments" \
  --jq "[.[] | select(.commit_id == \"$SHA\" or .original_commit_id == \"$SHA\")$([ -n "$REVIEW_BOT" ] && echo " | select(.user.login != \"$REVIEW_BOT\")")] | [.[].id]" 2>/dev/null || echo "[]")

if [ -n "$human_comments" ] && [ "$human_comments" != "null" ]; then
  human_comment_ids="$human_comments"
fi

# --- 5. Merge state ---
merge_state=$(gh_safe pr view "$PR" -R "$REPO" --json mergeStateStatus --jq '.mergeStateStatus')
if [ -z "$merge_state" ]; then
  merge_state="UNKNOWN"
fi

# --- 6. Output: raw data, no computed verdicts ---
jq -n \
  --arg head_sha "$head_sha" \
  --argjson sha_match true \
  --argjson checks "$checks" \
  --argjson check_counts "{\"total\":$total,\"pending\":$pending,\"failed\":$failed}" \
  --argjson failed_checks "$failed_checks" \
  --arg review_state "$([ "$review_state" = "null" ] && echo "" || echo "$review_state")" \
  --argjson review_id "$([ "$review_id" = "null" ] && echo "null" || echo "$review_id")" \
  --argjson review_comment_count "$review_comment_count" \
  --argjson human_comment_ids "$human_comment_ids" \
  --arg merge_state "$merge_state" \
  '{
    head_sha: $head_sha,
    sha_match: $sha_match,
    checks: $checks,
    check_counts: $check_counts,
    failed_checks: $failed_checks,
    review_state: (if $review_state == "" then null else $review_state end),
    review_id: $review_id,
    review_comment_count: $review_comment_count,
    human_comment_ids: $human_comment_ids,
    merge_state: $merge_state
  }'
