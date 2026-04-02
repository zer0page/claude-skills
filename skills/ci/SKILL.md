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

**Scripts:**

- `{{SKILL_DIR}}/scripts/ci-poll.sh` — Single-shot status snapshot. Returns JSON with current CI, review, and merge state. Use when you need fine-grained control over the polling loop.
- `{{SKILL_DIR}}/scripts/ci-loop.sh` — Wraps `ci-poll.sh` in a polling loop. Blocks until actionable, then fetches failure logs and review comments before returning. Use this by default — it minimizes round trips.

## Loop (max N attempts, default 5)

Each pass through the attempt loop (fix + commit + push) counts as **one attempt**. This includes review-only fixes, because each push restarts CI.

### 1. Poll CI and reviews

Recompute the latest SHA then run the loop script. This is **one Bash call** — it polls internally and only returns when action is needed:

```bash
LATEST_SHA=$(git rev-parse HEAD)
REVIEW_BOT_FLAG=""
[ "$REVIEW_BOT" != "none" ] && REVIEW_BOT_FLAG="--review-bot $REVIEW_BOT"

result=$(bash "{{SKILL_DIR}}/scripts/ci-loop.sh" --pr "$PR" --repo "$REPO" --sha "$LATEST_SHA" $REVIEW_BOT_FLAG --timeout 600)
echo "$result"
```

### 2. Interpret the result

`ci-loop.sh` only returns once all checks are resolved and reviews are in — you will never see pending states. Read the JSON fields to decide what to do:

- **`sha_match == false`** → Someone else pushed. `git pull`, recompute `LATEST_SHA`, restart attempt.
- **`error` field present** → API failure. Wait 30s, retry.
- **`timed_out == true`** → Report to user and **STOP**.
- **`check_counts.failed > 0`** → CI failures. Logs pre-fetched in `ci_logs`. Fix them.
- **`review_comment_count > 0`** or **`human_comment_ids` non-empty** → Review comments to address. Details pre-fetched in `review_comments` and `human_comment_details`. Fix reviews first (pushing restarts CI).
- **`check_counts.failed == 0`** and **no comments** → **EXIT loop → proceed to Completion.**

### 3. Fix issues

Failure details are pre-fetched by `ci-loop.sh` — no additional API calls needed.

#### CI failures

Read `ci_logs` from the JSON output. It contains:
- **CheckRun (GitHub Actions):** Full failure logs from `gh run view --log-failed`.
- **StatusContext (external CI):** The failure name, state, and URL. Use `WebFetch <url>` to retrieve details. If the page is behind auth or not parseable, report to the user and ask for guidance.

#### Review comments

Read `review_comments` (bot: `{id, path, body}`) and `human_comment_details` (human: `{id, path, body, user}`) arrays from the JSON output.

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

After reading failure logs, extract the first failing job name + first 200 characters of its error output as the error signature.
- **First failure:** Store the signature.
- **Second+ failure:** Compare current signature to the stored one.
- **If identical in 2 consecutive attempts:** Use `AskUserQuestion` with:
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
