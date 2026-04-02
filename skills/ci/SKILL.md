---
name: ci
description: Watch CI + bot reviews on the current PR, fix failures, push, loop until green. Review bot is configurable via CLAUDE.md. Use when checking, monitoring, fixing, debugging, watching, polling, waiting for, or retrying CI builds, test failures, or review bot comments on a PR.
---

# /ci [--max N]

Automate the CI fix loop for the current branch's PR.

**MANDATORY:** This skill must NEVER be skipped, abbreviated, or short-circuited, regardless of how small or trivial the changes appear. Every invocation must complete the full polling loop for both CI and reviews. No exceptions.

## Preconditions

```bash
BRANCH=$(git branch --show-current)
PR=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number // empty')
if [ -z "$PR" ]; then echo "No PR found for branch $BRANCH"; exit 1; fi
REPO=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')
if [ -z "$REPO" ]; then echo "Error: could not resolve repo"; exit 1; fi
OWNER=${REPO%%/*}
NAME=${REPO##*/}
ALLOWED_FILES=$(gh pr diff "$PR" --name-only) || { echo "Error: gh pr diff failed"; exit 1; }
LATEST_SHA=$(git rev-parse HEAD)
```

**Resolve review bot:** Read `CLAUDE.md` for a configured review bot (e.g. `review_bot: my-reviewer[bot]`). Default: `copilot-pull-request-reviewer[bot]`. If set to `none`, skip all review bot steps (review polling and review comment checking).

```bash
REVIEW_BOT="${REVIEW_BOT:-copilot-pull-request-reviewer[bot]}"
```

**Shell compatibility:** Do not use `status` as a variable name — it is read-only in zsh. Prefix CI-related variables (e.g., `run_status`, `run_conclusion`, `run_id`).

**State:** All loop state variables are initialized at the start of each attempt (see Attempt loop). The only variable that persists across attempts is `last_ci_error=""` (for flaky CI detection).

## Loop (max N attempts, default 5)

Each pass through the attempt loop (fix + commit + push) counts as **one attempt**. This includes review-only fixes, because each push restarts CI.

**Error handling:** If a `gh` command exits non-zero or returns empty/null:
- **Rate limit (HTTP 403/429):** Set `backoff_delay = min(backoff_delay * 2, 120)`, sleep `backoff_delay`, retry on the next poll tick. Reset `backoff_delay = 10` on the next successful `gh` call.
- **Other failures:** Log the error, sleep `backoff_delay`, retry on the next poll tick. Do not treat failures as success or skip the check.

### Attempt loop

Each attempt consists of a **polling phase** followed by optional **fixes**. Recompute state at the start of each attempt:

```bash
LATEST_SHA=$(git rev-parse HEAD)
ci_status="pending"         # pending | clean | failed
reviews_status="pending"    # pending | clean | failed
review_evaluated="false"    # set to "true" after step 3a runs
backoff_delay=10
review_poll_count=0         # 10-min timeout = 60 ticks × 10s
```

If `$REVIEW_BOT` is not `none`, request a review:

```bash
gh api "repos/$OWNER/$NAME/pulls/$PR/requested_reviewers" \
  -X POST -f "reviewers[]=$REVIEW_BOT"
```

### Polling phase (every 10s)

Poll both CI and reviews on each tick. Act on the first actionable result.

#### 1. Poll CI

```bash
result=$(gh run list --branch "$BRANCH" --limit 1 --json status,conclusion,databaseId,headSha --jq '.[0] // empty')
```

If `gh` fails or returns empty, apply backoff and retry next tick. Otherwise:

```bash
run_status=$(echo "$result" | jq -r '.status')
run_conclusion=$(echo "$result" | jq -r '.conclusion')
run_id=$(echo "$result" | jq -r '.databaseId')
run_sha=$(echo "$result" | jq -r '.headSha')
```

- If `$run_sha != $LATEST_SHA` → stale run, keep polling.
- If `$run_status != "completed"` → still running, keep polling.
- If `$run_conclusion == "success"` → `ci_status="clean"`.
- If `$run_conclusion == "failure"` → `ci_status="failed"`.
- If `$run_conclusion` is anything else (`cancelled`, `skipped`, etc.) → report to user and **STOP**. Do not treat as success or attempt to fix.

#### 2. Poll reviews

Skip entirely if `$REVIEW_BOT` is `none`.

**Important:** Always use `gh api --jq` instead of piping to `jq` for review endpoints — bot review bodies can contain raw control characters (U+0000–U+001F) that crash standalone `jq`. Note: `gh api` does **not** support jq's `--arg` flag — use escaped double-quote interpolation for variables.

**Check for review bot review on latest commit** (extracts both state and ID in one call to avoid a redundant API request in step 3a):

```bash
review_obj=$(gh api "repos/$OWNER/$NAME/pulls/$PR/reviews" \
  --jq "[.[] | select(.user.login == \"$REVIEW_BOT\") | select(.state != \"PENDING\") | select(.commit_id == \"$LATEST_SHA\")] | last // empty")
review_state=$(echo "$review_obj" | jq -r '.state // empty')
REVIEW_ID=$(echo "$review_obj" | jq -r '.id // empty')
```

If `gh` fails, apply backoff and retry next tick. Otherwise:

- If `$review_state` is empty and `review_poll_count < 60` → no review yet, increment `review_poll_count`, keep polling.
- If `$review_state` is empty and `review_poll_count >= 60` → 10-minute timeout, set `reviews_status="clean"` and proceed. This ensures rule 3b fires on the next decision check.
- If `$review_state` is non-empty and `review_evaluated == "false"` → review arrived. Run step 3a **once** (using the cached `$REVIEW_ID`), then set `review_evaluated="true"` and `reviews_status` accordingly.

**Check for non-bot review comments** (human reviewers, other bots) on the latest commit:

```bash
other_comments=$(gh api "repos/$OWNER/$NAME/pulls/$PR/comments" \
  --jq "[.[] | select(.user.login != \"$REVIEW_BOT\") | select(.commit_id == \"$LATEST_SHA\" or .original_commit_id == \"$LATEST_SHA\")] | .[] | {id, path, body, user: .user.login}")
```

#### 3. Decision (priority order)

Evaluate in this exact order:

**a.** `reviews_status == "failed"` → **Break polling phase. Fix review comments.**
Reviews always get fix priority — they are faster to resolve, and pushing a fix restarts CI.

**b.** `ci_status == "failed"` AND `reviews_status != "pending"` → **Break polling phase. Fix CI failures.**
CI failed and reviews have a result (clean or failed-and-already-fixed). Read failure logs and fix.

**c.** `ci_status == "failed"` AND `reviews_status == "pending"` → **Continue polling.**
CI failed but reviews haven't arrived yet. Wait for reviews — they may arrive with comments that also need fixing. Batching both into one push saves a cycle. When `review_poll_count` reaches 60 (10-min timeout), step 2 sets `reviews_status="clean"`, which causes rule (b) to fire on the next tick — this prevents indefinite waiting.

**d.** `ci_status == "clean"` AND `reviews_status == "clean"` (on the current `$LATEST_SHA`) → **EXIT loop → proceed to Completion.**

**e.** Otherwise → `sleep 10`, continue polling.

#### 3a. Evaluate review comments

**Trigger:** Run this step **once** per attempt, guarded by `review_evaluated`. Use the `$REVIEW_ID` cached from step 2 (no additional API call needed):

```bash
review_comments=""
if [ -n "$REVIEW_ID" ] && [ "$REVIEW_ID" != "null" ]; then
  review_comments=$(gh api "repos/$OWNER/$NAME/pulls/$PR/reviews/$REVIEW_ID/comments" \
    --jq '.[] | {id, path, body}')
fi
```

- If `$review_comments` is empty AND `$other_comments` is empty → `reviews_status="clean"`.
- If either `$review_comments` or `$other_comments` is non-empty → `reviews_status="failed"`.

For non-bot comments: fix if within scope and react +1. **Stop and notify the user** if a comment requires a design or architectural change.

### 4. Fix issues

- **CI failures:** Read logs via `gh run view $run_id --log-failed`.
- **Review comments:** Read from `$review_comments` and `$other_comments` collected in step 3a.
- Fix using industry best practices.
- **Only modify files in `$ALLOWED_FILES`** — never touch unrelated code. This is a hard rule.
- **Minimize lines changed** per fix.
- **Do not deviate from design decisions** in the PR — if a comment requires an architectural change, stop and notify the user.
- **Do not increase scope.**
- React +1 on addressed review comments:
  ```bash
  gh api "repos/$OWNER/$NAME/pulls/comments/$COMMENT_ID/reactions" -f content="+1"
  ```

**Flaky CI detection:** After reading failure logs via `gh run view $run_id --log-failed`, extract the first failing job name + first 200 characters of its error output as the error signature. On the first CI failure, store the signature in `$last_ci_error`. On subsequent failures, compare against `$last_ci_error`. If identical across 2+ consecutive attempts, use `AskUserQuestion` with these options:
1. **Retry anyway** — continue the loop, attempt counter still increments.
2. **Skip CI (mark clean)** — set `ci_status="clean"` and proceed to exit check.
3. **Stop and report** — proceed to Completion with current status.

Update `$last_ci_error` with the current error signature after each CI failure.

### 5. Commit and push

- Create a **new commit** each round (not amend) with a descriptive message.
- Push to the PR branch.
- Re-request review bot (if configured):
  ```bash
  gh api "repos/$OWNER/$NAME/pulls/$PR/requested_reviewers" -X POST -f "reviewers[]=$REVIEW_BOT"
  ```

### 6. Continue or stop

- Not last attempt → continue attempt loop (back to step 1).
- Last attempt → complete fix + commit + push, then proceed to Completion. Report what was fixed and any remaining issues.

## Output

Report only when `ci_status` or `reviews_status` transitions (not every tick):

```
Attempt N/M — polling (CI: <status>, Reviews: <status>)
```

Do not report on ticks where both statuses remain unchanged. After each fix, report:
- What was fixed (files + summary)
- CI status
- Review status
- Remaining comments (if any)

## Completion

Use `AskUserQuestion` to present three options:

1. **Mark ready (Recommended)** — remove draft status. Do not merge.
2. **Clean up and reopen** — squash all commits into one, force-push, close the PR, reopen with clean history.
3. **Merge and close** — mark ready, squash merge into base branch, delete remote branch, switch to main locally.
