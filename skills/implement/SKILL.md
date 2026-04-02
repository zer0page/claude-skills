---
name: implement
description: Full development workflow — brainstorm, plan, audit, simplify, build, ship. Orchestrates /brainstorming, /audit, /simplify, and /ci into a repeatable loop from idea to merged PR. Use --quick to skip audits for trivial changes. Use when building, developing, creating, implementing, shipping, delivering, or coding a feature end-to-end from plan to merged PR.
---

# /implement [description] [--quick]

End-to-end workflow for building features and updates. **Every phase is mandatory and sequential — do not skip or reorder phases.** The only exception is `--quick`, which skips audit phases.

`--quick` skips Phase 3 (audit plan) and Phase 6 (audit diff). All other phases are always required.

**Auto-quick:** If `--quick` was not specified but the change appears trivial (single-file fix, small bug fix, minor update), use `AskUserQuestion` to ask whether to run with `--quick`. `--quick` only skips audits — brainstorming still runs.

## Worktree isolation

All `/implement` runs use a worktree for isolation.

- **Enter:** Phase 2, step 1 — before entering plan mode.
- **Active:** Phases 2–8, and Phase 9 until `ExitWorktree`.
- **Exit:** Phase 9 — `remove` on merge, `keep` otherwise. Also exits after Phase 8 if `/ci` completes with "Merge and close" (Phase 9 is skipped).

Name the worktree with a slug derived from the feature description (lowercase, hyphens, max 30 chars, e.g. `fix-auth-timeout`). If no description is provided, omit the name and let `EnterWorktree` generate one. If `EnterWorktree` fails (name collision), append `-2`, `-3`, etc. and retry.

## Phase 1: Brainstorm

1. Run `/brainstorming` to explore the idea before planning.
2. After `/brainstorming` completes, use `AskUserQuestion` to ask if the user has additional context or changes before planning begins.

## Phase 2: Plan

1. Enter a worktree with `EnterWorktree`: use the slugified description as the name, or omit to auto-generate. This creates a new branch from HEAD.
2. If `git config user.name` is empty, configure git identity:
   ```bash
   if git rev-parse --verify HEAD >/dev/null 2>&1; then
     git config user.name "$(git log -1 --format='%an')"
     git config user.email "$(git log -1 --format='%ae')"
   else
     git config user.name "$(git config --global user.name)"
     git config user.email "$(git config --global user.email)"
   fi
   ```
3. Enter plan mode.
4. Write a concrete implementation plan based on the validated design from Phase 1.
5. Validate all `skills/*/SKILL.md` files for clarity, completeness, and consistency — include fixes in the plan.
6. Use `AskUserQuestion` for any unresolved design questions.
7. Do not exit plan mode yet — Phase 3 is next (or Phase 4 with `--quick`).

## Phase 3: Audit plan

_Skipped with `--quick`._

1. Run `/audit --no-handoff` on the plan file.
2. Fix findings immediately — revise the plan.
3. Update the plan file. Do not pause here — fold the audit summary into Phase 4.

## Phase 4: Gate — user approves execution

Present the final plan to the user. If Phase 3 ran, include a summary of audit findings and how they were addressed. Use `ExitPlanMode` to request approval — this exits plan mode and gates on user approval. Do not proceed without explicit approval.

## Phase 5: Implement

1. You are now out of plan mode (Phase 4's `ExitPlanMode` handled the exit).
2. You are inside the worktree created in Phase 2 — the branch is already checked out. Never commit directly to main.
3. Build the feature following the plan. Only modify files identified in the plan.
4. Commit locally with a descriptive message — do not push yet.

## Phase 6: Audit diff

_Skipped with `--quick`._

1. Ensure all changes are committed locally (do not push).
2. Run `/audit --diff --no-handoff` on the changes.
3. Fix findings immediately and commit the fixes.
4. Verify `git status` is clean.
5. Print a one-line status summary (e.g. "Audit: 3 findings fixed, 0 remaining"), then proceed directly to Phase 7.

## Phase 7: Simplify

1. Run `/simplify` on the changed code.
2. Fix any reuse, quality, or efficiency issues found.
3. Commit the fixes.
4. Use `AskUserQuestion` to present a summary of simplify results and request approval before pushing to remote. Do not proceed without explicit approval.

## Phase 8: Ship

1. Push and create a draft PR.
2. Run `/ci --max 10` — fix failures and review comments until clean.
3. `/ci` presents completion options:
   - **Mark ready** → proceed to Phase 9.
   - **Clean up and reopen** → `/ci` closes and reopens the PR. Re-fetch the new PR URL before proceeding to Phase 9.
   - **Merge and close** → `/ci` handles the merge. Skip Phase 9 and go directly to worktree cleanup: `ExitWorktree action: "remove", discard_changes: true`, then switch to main and pull.

## Phase 9: Gate — user approves merge

1. Report the PR URL and status.
2. Use `AskUserQuestion` to ask the user to approve the merge.
3. On approval:
   ```bash
   # Squash merge (do not use --delete-branch — fails in worktrees)
   gh pr merge --squash
   # Verify merge completed
   gh pr view --json state --jq '.state'  # must be "MERGED"
   # Delete remote branch
   BRANCH=$(gh pr view --json headRefName --jq '.headRefName') && [ -n "$BRANCH" ] && git push origin --delete "$BRANCH"
   ```
   - Exit the worktree: `ExitWorktree action: "remove", discard_changes: true` (safe — squash merge confirmed on main).
   - Switch to main and pull to sync the merge locally.
4. If not approved:
   - Exit the worktree: `ExitWorktree action: "keep"`.
