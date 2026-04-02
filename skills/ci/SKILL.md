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
```

**Resolve review bot:** Read `CLAUDE.md` for a configured review bot (e.g. `review_bot: my-reviewer[bot]`). Default: `copilot-pull-request-reviewer[bot]`. If set to `none`, pass no `--review-bot` flag to the polling script.

**Locate polling script:** `ci-poll.sh` is in the same directory as this SKILL.md. Resolve its path:

```bash
POLL_SCRIPT="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/ci-poll.sh"
```

If `ci-poll.sh` is not found at the resolved path, search common skill install locations: `~/.claude/skills/ci/ci-poll.sh`, then `.claude/skills/ci/ci-poll.sh` relative to the repo root.

## Loop (max N attempts, default 5)

Each pass through the attempt loop (fix + commit + push) counts as **one attempt**. This includes review-only fixes, because each push restarts CI.

### 1. Poll CI and reviews

Recompute the latest SHA then run the polling script in a loop until both CI and reviews are resolved. This is **one Bash call** — the shell loop handles polling internally:

```bash
LATEST_SHA=$(git rev-parse HEAD)
REVIEW_BOT_FLAG=""
[ "$REVIEW_BOT" != "none" ] && REVIEW_BOT_FLAG="--review-bot $REVIEW_BOT"

while true; do
  result=$(bash "$POLL_SCRIPT" --pr "$PR" --repo "$REPO" --sha "$LATEST_SHA" $REVIEW_BOT_FLAG)
  ci=$(echo "$result" | jq -r '.ci_status')
  rv=$(echo "$result" | jq -r '.review_bot.status')
  if [ "$ci" = "stale" ] || [ "$ci" = "error" ]; then break; fi
  if [ "$ci" != "pending" ] && [ "$rv" != "pending" ]; then break; fi
  sleep 10
done
echo "$result"
```

If `ci_status` is `"stale"`, someone else pushed — re-sync with `git pull` and restart the attempt.

If `ci_status` is `"error"`, the script couldn't reach the GitHub API — wait 30s and retry the polling loop.

### 2. Decision (priority order)

Read the JSON output from step 1. Evaluate in this exact order:

**a.** `review_bot.status == "failed"` OR `human_comments.count > 0` → **Fix review/human comments first.**
Reviews are faster to resolve, and pushing a fix restarts CI.

**b.** `ci_status == "failed"` → **Fix CI failures.**

**c.** `ci_status == "clean"` AND `review_bot.status` is `"clean"` or `"skipped"` AND `human_comments.count == 0` → **EXIT loop → proceed to Completion.**

**d.** `ci_status == "cancelled"` or any unexpected value → **Report to user and STOP.** Do not treat as success or attempt to fix.

### 3. Fix issues

#### CI failures

For each entry in `failed_checks`:

- **`type: "CheckRun"` (GitHub Actions):** Extract the run ID from the `url` field (pattern: `/actions/runs/<ID>/job/...`), then read logs:
  ```bash
  gh run view <RUN_ID> --log-failed
  ```

- **`type: "StatusContext"` (external CI):** Try `WebFetch <url>` to retrieve failure details. Parse the page for error messages. If the page is behind auth or not parseable, report the failure name, state, and URL to the user and ask for guidance.

#### Review comments

If `review_bot.comment_count > 0`, fetch the comments:
```bash
gh api "repos/$OWNER/$NAME/pulls/$PR/reviews/<review_id>/comments" --jq '.[] | {id, path, body}'
```

If `human_comments.count > 0`, fetch by IDs:
```bash
gh api "repos/$OWNER/$NAME/pulls/comments/<ID>" --jq '{id, path, body, user: .user.login}'
```

#### Fix rules

- Fix using industry best practices.
- **Only modify files in `$ALLOWED_FILES`** — never touch unrelated code.
- **Minimize lines changed** per fix.
- **Do not deviate from design decisions** in the PR — if a comment requires an architectural change, stop and notify the user.
- **Do not increase scope.**
- React +1 on addressed review comments:
  ```bash
  gh api "repos/$OWNER/$NAME/pulls/comments/$COMMENT_ID/reactions" -f content="+1"
  ```

#### Flaky CI detection

After reading failure logs, extract the first failing job name + first 200 characters of its error output as the error signature. On the first CI failure, store the signature. On subsequent failures, compare. If identical across 2+ consecutive attempts, use `AskUserQuestion` with:
1. **Retry anyway** — continue the loop.
2. **Skip CI (mark clean)** — proceed to Completion.
3. **Stop and report** — proceed to Completion with current status.

### 4. Commit and push

- Create a **new commit** each round (not amend) with a descriptive message.
- Push to the PR branch.
- If review bot is configured, re-request a review:
  ```bash
  gh api "repos/$OWNER/$NAME/pulls/$PR/requested_reviewers" -X POST -f "reviewers[]=$REVIEW_BOT"
  ```

### 5. Continue or stop

- Not last attempt → loop back to step 1.
- Last attempt → complete fix + commit + push, then proceed to Completion. Report what was fixed and any remaining issues.

## Output

Report on status transitions, not every poll tick. After each fix, report:
- What was fixed (files + summary)
- CI status
- Review status
- Remaining comments (if any)

## Completion

Use `merge_state` from the last polling result (no additional API call needed).

Use `AskUserQuestion` to present the applicable options:

**Options always available:**

1. **Mark ready (Recommended)** — remove draft status. Do not merge.
2. **Clean up and reopen** — squash all commits into one, force-push, close the PR, reopen with clean history.

**Conditional option — only if `merge_state` is `CLEAN`:**

3. **Merge and close** — mark ready, squash merge into base branch, delete remote branch, switch to main locally.

If `merge_state` is not `CLEAN`, include a note explaining why:

> Note: Merge unavailable — PR state is `<merge_state>`. Common reasons: PR is a draft (`DRAFT`), requires reviewer approval (`BLOCKED`), has merge conflicts (`DIRTY`), base branch moved (`BEHIND`), or checks failing (`UNSTABLE`).
