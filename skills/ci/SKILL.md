---
name: ci
description: Watch CI + bot reviews on the current PR, fix failures, push, loop until green. Review bot is configurable via CLAUDE.md. Use when checking, monitoring, fixing, debugging, watching, polling, waiting for, or retrying CI builds, test failures, or review bot comments on a PR.
---

# /ci [--max N]

Fix loop for the current branch's PR. **Never skip or short-circuit — always complete the full loop.**

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

Read `CLAUDE.md` for `review_bot`. Default: `copilot-pull-request-reviewer[bot]`. If `none`, omit `--review-bot`.

**Scripts:** Use `{{SKILL_DIR}}/scripts/ci-loop.sh` (blocks until resolved, fetches logs and comments). For fine-grained control, use `{{SKILL_DIR}}/scripts/ci-poll.sh` (single-shot snapshot).

## Loop (max N attempts, default 5)

Each fix + commit + push = one attempt.

### 1. Poll

```bash
LATEST_SHA=$(git rev-parse HEAD)
REVIEW_BOT="${REVIEW_BOT:-copilot-pull-request-reviewer[bot]}"
LOOP_ARGS=(--pr "$PR" --repo "$REPO" --sha "$LATEST_SHA" --timeout 600)
[ -n "$REVIEW_BOT" ] && [ "$REVIEW_BOT" != "none" ] && LOOP_ARGS+=(--review-bot "$REVIEW_BOT")

result=$(bash "{{SKILL_DIR}}/scripts/ci-loop.sh" "${LOOP_ARGS[@]}")
echo "$result"
```

### 2. Decide

`ci-loop.sh` blocks until resolved. Read the JSON:

- `sha_match == false` → `git pull`, recompute `LATEST_SHA`, restart attempt.
- `error` present → API/network failure. Retry in next attempt.
- `timed_out == true` → report to user, **STOP**.
- `review_comment_count > 0` or `human_comment_ids` non-empty → fix comments first (step 3). If both bot and human comments exist, address in one fix. Pushing restarts CI.
- Any check in `checks` with `resolved: true` and `state` not `SUCCESS`/`NEUTRAL` → fix CI (step 3).
- All resolved checks `SUCCESS`/`NEUTRAL`, no comments → **EXIT → Completion**.

### 3. Fix

Logs and comments are pre-fetched in the JSON — no extra API calls.

- **CI (`ci_logs`):** CheckRun logs included directly. StatusContext failures have name + URL — use `WebFetch <url>` for details. If behind auth, ask user.
- **Bot comments (`review_comments`):** `{id, path, body}`.
- **Human comments (`human_comment_details`):** `{id, path, body, user}`.
- **Only modify files in `$ALLOWED_FILES`.**
- **Minimize lines changed.** Do not increase scope.
- If a comment requires architectural change, stop and notify user.
- React +1 on addressed comments: `gh api repos/$OWNER/$NAME/pulls/comments/$COMMENT_ID/reactions -f content="+1"`

**Flaky CI:** Extract first failing job + first 200 chars as error signature. If identical across 2 consecutive attempts, `AskUserQuestion`:
1. Retry anyway
2. Skip CI → Completion
3. Stop and report

### 4. Commit and push

1. New commit (not amend) with descriptive message.
2. Push to PR branch.
3. Re-request review bot if configured: `gh api repos/$OWNER/$NAME/pulls/$PR/requested_reviewers -X POST -f "reviewers[]=$REVIEW_BOT"`

### 5. Continue or stop

- Not last attempt → back to step 1.
- Last attempt → fix + commit + push, then Completion.

## Completion

Use `merge_state` from last poll result. `AskUserQuestion` with applicable options:

1. **Mark ready (Recommended)** — remove draft status. Do not merge.
2. **Clean up and reopen** — squash all commits, force-push, close PR, reopen with clean history.
3. **Merge and close** _(only if `merge_state` is `CLEAN`)_ — mark ready, squash merge, delete remote branch, switch to main.

If not `CLEAN`:

> Merge unavailable — PR state: `<merge_state>`. States: `DRAFT` (draft), `BLOCKED` (approval/changes needed), `DIRTY` (conflicts), `BEHIND` (out of date), `UNSTABLE` (checks pending/failing).
