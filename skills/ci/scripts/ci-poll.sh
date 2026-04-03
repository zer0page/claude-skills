#!/usr/bin/env bash
# ci-poll.sh — Single-shot CI/review status snapshot for a PR.
# Returns normalized GitHub API data as JSON (field mapping only).
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
  echo "Usage: ci-poll.sh --pr PR --repo OWNER/NAME --sha SHA [--review-bot BOT]" >&2
  exit 1
fi

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

# Validate inputs
if ! echo "$PR" | grep -qE '^[0-9]+$'; then
  printf '{"error":"invalid PR format"}\n'
  exit 0
fi
if ! echo "$REPO" | grep -qE '^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$'; then
  printf '{"error":"invalid REPO format"}\n'
  exit 0
fi
if ! echo "$SHA" | grep -qE '^[a-f0-9]+$'; then
  printf '{"error":"invalid SHA format"}\n'
  exit 0
fi
# Validate bot name: alphanumeric/dots/hyphens with optional [bot] suffix
if [ -n "$REVIEW_BOT" ]; then
  if ! echo "$REVIEW_BOT" | grep -qE '^[a-zA-Z0-9._-]+(\[bot\])?$'; then
    printf '{"error":"invalid review-bot format"}\n'
    exit 0
  fi
fi

# --- Helper: safe gh call, returns empty string on failure ---
gh_safe() {
  gh "$@" 2>/dev/null || true
}

# --- 1. Fetch PR data in one call (avoids race between SHA check and status fetch) ---
pr_data=$(gh_safe pr view "$PR" -R "$REPO" --json headRefOid,statusCheckRollup,mergeStateStatus)
if [ -z "$pr_data" ]; then
  printf '{"error":"failed to fetch PR data"}\n'
  exit 0
fi

head_sha=$(echo "$pr_data" | jq -r '.headRefOid // empty')
if [ -z "$head_sha" ]; then
  printf '{"error":"failed to parse PR head SHA"}\n'
  exit 0
fi

if [ "$head_sha" != "$SHA" ]; then
  printf '{"head_sha":"%s","expected_sha":"%s","sha_match":false}\n' "$head_sha" "$SHA"
  exit 0
fi

# --- 2. Normalize statusCheckRollup ---
# Maps CheckRun and StatusContext into uniform field names. States pass through unchanged.
checks_json=$(echo "$pr_data" | jq -c '.statusCheckRollup // []')

# Normalize into uniform format (schema mapping, not interpretation)
checks=$(echo "$checks_json" | jq -c '[.[] | {
  name: (if .__typename == "CheckRun" then .name else .context end),
  type: .__typename,
  resolved: (if .__typename == "CheckRun" then (.status == "COMPLETED") else (.state != "PENDING" and .state != "EXPECTED") end),
  state: (if .__typename == "CheckRun" then (.conclusion // "PENDING") else .state end),
  url: (if .__typename == "CheckRun" then .detailsUrl else .targetUrl end)
}]')


# --- 3. Review bot ---
review_state="null"
review_id="null"
review_comment_count=0

if [ -n "$REVIEW_BOT" ]; then
  # --arg passes values safely to jq (prevents injection via bot name or SHA)
  review_obj=$(gh api "repos/$OWNER/$NAME/pulls/$PR/reviews" 2>/dev/null \
    | jq --arg bot "$REVIEW_BOT" --arg sha "$SHA" \
    '[.[] | select(.user.login == $bot) | select(.state != "PENDING") | select(.commit_id == $sha)] | last // empty' 2>/dev/null || true)

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
# Filter by user.type != "Bot" (GitHub uses different logins in reviews vs comments API,
# but user.type is consistent).
human_comment_ids="[]"

human_comments=$(gh api "repos/$OWNER/$NAME/pulls/$PR/comments" 2>/dev/null \
  | jq --arg sha "$SHA" \
  '[.[] | select(.commit_id == $sha or .original_commit_id == $sha) | select(.user.type != "Bot")] | [.[].id]' 2>/dev/null || echo "[]")

if [ -n "$human_comments" ] && [ "$human_comments" != "null" ]; then
  human_comment_ids="$human_comments"
fi

# --- 5. Merge state (from initial pr_data fetch — no extra API call) ---
merge_state=$(echo "$pr_data" | jq -r '.mergeStateStatus // "UNKNOWN"')

# --- 6. Output ---
jq -nc \
  --arg head_sha "$head_sha" \
  --argjson sha_match true \
  --argjson checks "$checks" \
  --arg review_state "$([ "$review_state" = "null" ] && echo "" || echo "$review_state")" \
  --argjson review_id "$([ "$review_id" = "null" ] && echo "null" || echo "$review_id")" \
  --argjson review_comment_count "$review_comment_count" \
  --argjson human_comment_ids "$human_comment_ids" \
  --arg merge_state "$merge_state" \
  '{
    head_sha: $head_sha,
    sha_match: $sha_match,
    checks: $checks,
    review_state: (if $review_state == "" then null else $review_state end),
    review_id: $review_id,
    review_comment_count: $review_comment_count,
    human_comment_ids: $human_comment_ids,
    merge_state: $merge_state
  }'
