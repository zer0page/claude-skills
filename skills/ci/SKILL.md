---
name: ci
description: Watch CI + bot reviews on the current PR, fix failures, push, loop until green. Review bot is configurable via CLAUDE.md. Use when checking, monitoring, fixing, debugging, watching, polling, waiting for, or retrying CI builds, test failures, or review bot comments on a PR.
---

# /ci [--max N]

## Purpose

Fix loop for the current branch's PR. Poll CI and reviews, fix failures and comments, push, repeat until green.

Prevents: short-circuiting the loop, skipping reviews, modifying unrelated files, increasing scope.

**Never skip or abbreviate — always complete the full loop.**

## Operating Mode

You are a **fix loop** — poll, fix, push, repeat.

- **ci-loop.sh**: Use for the main fix loop (step 1). Blocks until actionable. When `--review-bot` is passed, automatically requests the bot on startup and re-requests after 10 min if unresponsive.
- **ci-poll.sh**: Use only for one-time status checks outside the loop.

Before starting: resolve `BRANCH`, `PR`, `REPO`, `OWNER`, `NAME`, `ALLOWED_FILES` via `gh`. Read `CLAUDE.md` for `review_bot` (default: `copilot-pull-request-reviewer[bot]`, `none` to skip).

## The Process

Each fix + commit + push = one attempt. Max N attempts (default 5).

### 1. Poll

Run `{{SKILL_DIR}}/scripts/ci-loop.sh` with `--pr`, `--repo`, `--sha`, and `--review-bot BOT` when `review_bot` is a real bot login. Omit `--review-bot` if `review_bot` is `none`. One Bash call — blocks until actionable.

### 2. Decide

Read the JSON result:

- `sha_match == false` → `git pull`, recompute SHA, restart.
- `error` present → retry next attempt.
- `review_bot_timeout == true` → mention to user, not a blocker.
- `review_comments` or `human_comment_details` non-empty → fix comments (step 3). Pushing restarts CI.
- Any check with `resolved: true` and `state` not `SUCCESS`/`NEUTRAL` → fix CI (step 3).
- All clean + no comments → **done → Completion**.

### 3. Fix

Logs and comments are pre-fetched — no extra API calls.

- **CI:** CheckRun logs in `ci_logs`. StatusContext failures have URL — `WebFetch` for details. If behind auth, ask user.
- **Comments:** Bot in `review_comments` (`{id, path, body}`). Human in `human_comment_details` (`{id, path, body, user}`).
- Only modify `ALLOWED_FILES`. Minimize changes. No scope increase.
- If comment requires architectural change, stop and notify user.
- React +1 on addressed comments.
- **Flaky CI:** Same error signature across 2 attempts → `AskUserQuestion`: retry, skip CI, or stop.

### 4. Commit and push

New commit (not amend). Push. (Review bot is re-requested automatically by ci-loop.sh on next poll.)

### 5. Continue or stop

Not last attempt → back to step 1. Last attempt → fix + commit + push, then one final poll (step 1, read-only — no more fixes) to get actual CI/review state, then Completion.

## Exit Criteria

- All checks `SUCCESS`/`NEUTRAL` on latest commit
- Bot reviewed clean (no actionable comments) on latest commit
- OR max attempts reached

## Completion

Use `merge_state` from last poll. `AskUserQuestion` with options:

1. **Mark ready (Recommended)** — remove draft status. Do not merge.
2. **Clean up and reopen** — squash, force-push, close, reopen.
3. **Merge and close** _(only if `CLEAN`)_ — squash merge, delete branch, switch to main.

If not `CLEAN`: note the state (`DRAFT`, `BLOCKED`, `DIRTY`, `BEHIND`, `UNSTABLE`).

## Key Principles

- Never skip or short-circuit the loop. Never assume CI is absent — always run ci-loop.sh.
- Only modify files in `ALLOWED_FILES`.
- Minimize lines changed per fix.
- Do not deviate from PR design decisions.
- Do not increase scope.
