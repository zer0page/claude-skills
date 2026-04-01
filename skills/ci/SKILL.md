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

**Resolve review bot:** Read `CLAUDE.md` for a configured review bot (e.g. `review_bot: my-reviewer[bot]`). Default: `copilot-pull-request-reviewer[bot]`. If set to `none`, skip all review bot steps (2, and review portions of 3).

```bash
REVIEW_BOT="${REVIEW_BOT:-copilot-pull-request-reviewer[bot]}"
```

**Shell compatibility:** Do not use `status` as a variable name — it is read-only in zsh. Prefix CI-related variables (e.g., `run_status`, `run_conclusion`, `run_id`).

## Loop (max N attempts, default 5)

Each attempt, first recompute `LATEST_SHA=$(git rev-parse HEAD)` (it changes after each push).

### 1. Wait for CI

```bash
result=$(gh run list --branch "$BRANCH" --limit 1 --json status,conclusion,databaseId,headSha --jq '.[0]')
run_status=$(echo "$result" | jq -r '.status')
run_conclusion=$(echo "$result" | jq -r '.conclusion')
run_id=$(echo "$result" | jq -r '.databaseId')
run_sha=$(echo "$result" | jq -r '.headSha')
```

Poll every 10s until `$run_status` is `completed`. Verify `$run_sha` matches `$LATEST_SHA` to ensure this run is for the current commit. Use `$run_id` for log retrieval.

Check `$run_conclusion`:
- `"success"` → CI passed, proceed to step 2
- `"failure"` → CI failed, skip to step 3 (read logs, fix)
- Any other value (`cancelled`, `skipped`, etc.) → report the conclusion to the user and stop. Do not treat as success or attempt to fix — these require human intervention.

### 2. Wait for review bot

If `$REVIEW_BOT` is `none`, skip this step.

Check for a submitted review from `$REVIEW_BOT` on the **latest commit**.

**Important:** Always use `gh api --jq` instead of piping to `jq` for review endpoints — bot review bodies can contain raw control characters (U+0000–U+001F) that crash standalone `jq`.

```bash
gh api "repos/$OWNER/$NAME/pulls/$PR/reviews" \
  --jq "[.[] | select(.user.login == \"$REVIEW_BOT\") | select(.state != \"PENDING\") | select(.commit_id == \"$LATEST_SHA\")] | last | .state // empty"
```
If none, request one:
```bash
gh api repos/$OWNER/$NAME/pulls/$PR/requested_reviewers -X POST -f "reviewers[]=$REVIEW_BOT"
```
Poll every 10s, up to 10 minutes. If timeout, proceed without it.

### 3. Check results

- **CI failed** (`$run_conclusion == "failure"`): read logs via `gh run view $run_id --log-failed`
- **CI passed** (`$run_conclusion == "success"`) + review bot reviewed: check for comments on the **latest commit's review**:
  ```bash
  # Get latest review bot review ID for this commit (use --jq to avoid control char crashes)
  REVIEW_ID=$(gh api "repos/$OWNER/$NAME/pulls/$PR/reviews" \
    --jq "[.[] | select(.user.login == \"$REVIEW_BOT\") | select(.commit_id == \"$LATEST_SHA\")] | last | .id")
  # Get that review's inline comments
  gh api "repos/$OWNER/$NAME/pulls/$PR/reviews/$REVIEW_ID/comments" --jq '.[] | {id, path, body}'
  ```
- **Also check for non-bot review comments** (human reviewers, other bots):
  ```bash
  # Get PR review comments on the latest commit, not from the configured review bot
  gh api "repos/$OWNER/$NAME/pulls/$PR/comments" \
    --jq '[.[] | select(.user.login != "'"$REVIEW_BOT"'") | select(.commit_id == "'"$LATEST_SHA"'" or .original_commit_id == "'"$LATEST_SHA"'")] | .[] | {id, path, body, user: .user.login}'
  ```
  Address these the same way as bot comments — fix if within scope, react +1, or stop and notify the user if the comment requires a design change.

### 4. If issues found

- Read the failure logs or review comments
- Fix using industry best practices
- **Only modify files in ALLOWED_FILES** — never touch unrelated code
- **Minimize lines changed** per fix
- **Do not deviate from design decisions** in the PR — if a comment requires an architectural change, stop and notify the user
- **Do not increase scope** beyond what is necessary
- React +1 on addressed comments:
  ```bash
  gh api repos/$OWNER/$NAME/pulls/comments/$COMMENT_ID/reactions -f content="+1"
  ```

### 5. Commit and push

- New commit each round (not amend) with descriptive message
- Push to the PR branch
- Re-request review bot (if configured):
  ```bash
  gh api repos/$OWNER/$NAME/pulls/$PR/requested_reviewers -X POST -f "reviewers[]=$REVIEW_BOT"
  ```

### 6. Repeat or stop

- If `$run_conclusion == "success"` + no unaddressed comments → proceed to Completion
- If not last attempt → loop back to step 1
- If last attempt → still do steps 4+5 fully (fix, react +1, commit, push), just skip looping back to step 1. Report what was fixed and any remaining comments, then proceed to Completion.

## Output

After each attempt, report:
- What was fixed (files + summary)
- CI status
- Remaining review comments (if any)

## Completion

When the loop finishes, use `AskUserQuestion` to present three options:

1. **Mark ready** — mark the PR as ready for review (remove draft status). Do not merge.
2. **Clean up and reopen** — squash all commits on the branch into one, force-push, close the PR, and reopen a new PR with clean history.
3. **Merge and close** — mark the PR ready, squash merge into the base branch, delete the remote branch, and switch to main locally.
