---
name: ci
description: Watch CI + bot reviews on the current PR, fix failures, push, loop until green. Review bot is configurable via CLAUDE.md. Use when checking, monitoring, fixing, debugging, watching, polling, waiting for, or retrying CI builds, test failures, or review bot comments on a PR.
---

# /ci [--max N]

Automate the CI fix loop for the current branch's PR.

## Preconditions

```bash
BRANCH=$(git branch --show-current)
PR=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number // empty')
if [ -z "$PR" ]; then echo "No PR found for branch $BRANCH"; exit; fi
REPO=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')
OWNER=${REPO%%/*}
NAME=${REPO##*/}
ALLOWED_FILES=$(gh pr diff "$PR" --name-only)
LATEST_SHA=$(git rev-parse HEAD)
```

**Resolve review bot:** Read `CLAUDE.md` for a configured review bot (e.g. `review_bot: my-reviewer[bot]`). Default: `copilot-pull-request-reviewer[bot]`. If set to `none`, skip all review bot steps (step 2 and review portions of step 3).

```bash
REVIEW_BOT="${REVIEW_BOT:-copilot-pull-request-reviewer[bot]}"
```

**Shell compatibility:** Do not use `status` as a variable name — it is read-only in zsh. Prefix CI-related variables (e.g., `run_status`, `run_conclusion`, `run_id`).

## Loop (max N attempts, default 5)

Recompute `LATEST_SHA=$(git rev-parse HEAD)` at the start of each attempt (it changes after each push).

### 1. Wait for CI

```bash
LATEST_SHA=$(git rev-parse HEAD)
result=$(gh run list --branch "$BRANCH" --limit 1 --json status,conclusion,databaseId,headSha --jq '.[0]')
run_status=$(echo "$result" | jq -r '.status')
run_conclusion=$(echo "$result" | jq -r '.conclusion')
run_id=$(echo "$result" | jq -r '.databaseId')
run_sha=$(echo "$result" | jq -r '.headSha')
```

Poll every 10s until `$run_status` is `completed`. Verify `$run_sha` matches `$LATEST_SHA` to confirm the run is for the current commit. Use `$run_id` for log retrieval.

Check `$run_conclusion`:
- `"success"` → proceed to step 2
- `"failure"` → skip to step 3 (read logs, fix)
- Any other value (`cancelled`, `skipped`, etc.) → report to the user and stop. Do not treat as success or attempt to fix.

### 2. Wait for review bot

Skip this step if `$REVIEW_BOT` is `none`.

Check for a submitted review from `$REVIEW_BOT` on the **latest commit**.

**Important:** Always use `gh api --jq` instead of piping to `jq` for review endpoints — bot review bodies can contain raw control characters (U+0000–U+001F) that crash standalone `jq`.

```bash
# Check for existing review
review_state=$(gh api "repos/$OWNER/$NAME/pulls/$PR/reviews" \
  --jq "[.[] | select(.user.login == \"$REVIEW_BOT\") | select(.state != \"PENDING\") | select(.commit_id == \"$LATEST_SHA\")] | last | .state // empty")

# If no review, request one
if [ -z "$review_state" ]; then
  gh api "repos/$OWNER/$NAME/pulls/$PR/requested_reviewers" \
    -X POST -f "reviewers[]=$REVIEW_BOT"
fi

# Poll every 10s, up to 10 minutes (60 × 10s = 600s)
for i in $(seq 1 60); do
  review_state=$(gh api "repos/$OWNER/$NAME/pulls/$PR/reviews" \
    --jq "[.[] | select(.user.login == \"$REVIEW_BOT\") | select(.state != \"PENDING\") | select(.commit_id == \"$LATEST_SHA\")] | last | .state // empty")
  if [ -n "$review_state" ]; then break; fi
  if [ $i -lt 60 ]; then sleep 10; fi
done
```

If no review after 10 minutes, proceed without it.

### 3. Check results

- **CI failed** (`$run_conclusion == "failure"`): read logs via `gh run view $run_id --log-failed`.
- **CI passed** + review bot reviewed: check for comments on the **latest commit's review** (skip if no review arrived):
  ```bash
  REVIEW_ID=$(gh api "repos/$OWNER/$NAME/pulls/$PR/reviews" \
    --jq "[.[] | select(.user.login == \"$REVIEW_BOT\") | select(.state != \"PENDING\") | select(.commit_id == \"$LATEST_SHA\")] | last | .id")
  if [ -n "$REVIEW_ID" ] && [ "$REVIEW_ID" != "null" ]; then
    gh api "repos/$OWNER/$NAME/pulls/$PR/reviews/$REVIEW_ID/comments" --jq '.[] | {id, path, body}'
  fi
  ```
- **Non-bot review comments** (human reviewers, other bots):
  ```bash
  gh api "repos/$OWNER/$NAME/pulls/$PR/comments" \
    --jq '[.[] | select(.user.login != "'"$REVIEW_BOT"'") | select(.commit_id == "'"$LATEST_SHA"'" or .original_commit_id == "'"$LATEST_SHA"'")] | .[] | {id, path, body, user: .user.login}'
  ```
  Fix if within scope and react +1. Stop and notify the user if a comment requires a design change.

### 4. Fix issues

- Read the failure logs or review comments.
- Fix using industry best practices.
- **Only modify files in `$ALLOWED_FILES`** — never touch unrelated code.
- **Minimize lines changed** per fix.
- **Do not deviate from design decisions** in the PR — if a comment requires an architectural change, stop and notify the user.
- **Do not increase scope.**
- React +1 on addressed comments:
  ```bash
  gh api repos/$OWNER/$NAME/pulls/comments/$COMMENT_ID/reactions -f content="+1"
  ```

### 5. Commit and push

- Create a new commit each round (not amend) with a descriptive message.
- Push to the PR branch.
- Re-request review bot (if configured):
  ```bash
  gh api repos/$OWNER/$NAME/pulls/$PR/requested_reviewers -X POST -f "reviewers[]=$REVIEW_BOT"
  ```

### 6. Repeat or stop

- `$run_conclusion == "success"` + no unaddressed comments → proceed to Completion.
- Not last attempt → loop back to step 1.
- Last attempt → complete steps 4–5 (fix, react +1, commit, push), then proceed to Completion. Report what was fixed and any remaining comments.

## Output

After each attempt, report:
- What was fixed (files + summary)
- CI status
- Remaining review comments (if any)

## Completion

Use `AskUserQuestion` to present three options:

1. **Mark ready (Recommended)** — remove draft status. Do not merge.
2. **Clean up and reopen** — squash all commits into one, force-push, close the PR, reopen with clean history.
3. **Merge and close** — mark ready, squash merge into base branch, delete remote branch, switch to main locally.
