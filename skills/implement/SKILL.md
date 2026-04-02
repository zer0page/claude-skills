---
name: implement
description: Full development workflow — brainstorm, plan, audit, simplify, build, ship. Orchestrates /brainstorming, /audit, /simplify, and /ci into a repeatable loop from idea to merged PR. Use --quick to skip audits for trivial changes. Use when building, developing, creating, implementing, shipping, delivering, or coding a feature end-to-end from plan to merged PR.
---

# /implement [description] [--quick]

End-to-end workflow for building features and updates. **Every phase is mandatory and sequential — do not skip or reorder phases.** The only exception is `--quick`, which skips audit phases.

`--quick` skips Phase 3 (audit plan) and Phase 6 (audit diff) for trivial changes. All other phases are always required.

**Auto-quick:** If `--quick` was not specified but the change appears trivial (single-file fix, small bug fix, minor update), use `AskUserQuestion` to ask the user whether to run with `--quick`. `--quick` only skips audits — brainstorming still runs.

## Worktree isolation

All `/implement` runs use a worktree for isolation.

- **Enter:** Phase 2, step 1 — before entering plan mode
- **Active:** Phases 2–8, and Phase 9 until `ExitWorktree`
- **Exit:** Phase 9 — `remove` on merge, `keep` otherwise. Switching to main happens after exit.

Name the worktree with a slug derived from the feature description (lowercase, hyphens, max 30 chars, e.g. `fix-auth-timeout`). If no description is provided, omit the name and let `EnterWorktree` generate one. If `EnterWorktree` fails (name collision), append `-2`, `-3`, etc. and retry.

## Phase 1: Brainstorm

1. Run `/brainstorming` to explore the idea before planning
2. Validate understanding, surface assumptions, and explore design approaches
3. Only after the brainstorming exit criteria are met, proceed to Phase 2

## Phase 2: Plan

1. Enter a worktree with `EnterWorktree`: if a description was provided, use its slugified form as the name; otherwise let `EnterWorktree` generate one. This creates a new branch from HEAD.
2. If `git config user.name` is empty, copy identity from the parent repo's latest commit (`git log -1 --format='%an'` / `'%ae'`), verify non-empty, then set with `git config user.name` and `git config user.email`
3. Enter plan mode
4. Use the validated design from Phase 1 to write a concrete implementation plan
5. Validate all `skills/*/SKILL.md` files for clarity, completeness, and consistency — fix any issues as part of the plan
6. Ask the user clarifying questions if anything remains unresolved
7. Do not exit plan mode yet — next is Phase 3 (or Phase 4 if using `--quick`)

## Phase 3: Audit plan

_Skipped only with `--quick`._

1. Run `/audit` on the plan file before asking the user to approve
2. Fix findings immediately — revise the plan based on audit results
3. Update the plan file
4. Use `AskUserQuestion` to present a summary of findings and fixes, then proceed to Phase 4

## Phase 4: Gate — user approves execution

Present the final plan and ask the user to approve before writing any code. Do not proceed without explicit approval.

## Phase 5: Implement

1. Exit plan mode
2. You are inside the worktree created in Phase 2 — the branch is already checked out. Never commit directly to main.
3. Build the feature, following the plan
4. Keep changes minimal and focused on the plan
5. Commit locally with a descriptive message — do not push yet. Phase 6 comes first (or Phase 7 if `--quick`).

## Phase 6: Audit diff

_Skipped only with `--quick`._

1. Ensure all changes are committed locally (do not push)
2. Run `/audit --diff` on the changes
3. Fix findings immediately and commit the fixes
4. Verify `git status` is clean
5. Use `AskUserQuestion` to present a summary of findings and fixes, then proceed to Phase 7

## Phase 7: Simplify

1. Run `/simplify` on the changed code
2. Fix any reuse, quality, or efficiency issues found
3. Commit the fixes
4. Only after this phase is complete, proceed to Phase 8

## Phase 8: Ship

1. Push and create a draft PR
2. Run `/ci --max 10` — fix failures and review comments until clean
3. When `/ci` completes, select "Mark ready" — do not merge or switch to main. Phase 9 handles the merge.

## Phase 9: Gate — user approves merge

1. Report the PR URL and status
2. Ask the user to approve the merge
3. On approval:
   - Squash merge with `gh pr merge --squash` (do not use `--delete-branch` — it tries to checkout main locally, which fails in worktrees)
   - Delete the remote branch: `BRANCH=$(gh pr view --json headRefName --jq '.headRefName') && [ -n "$BRANCH" ] && git push origin --delete "$BRANCH"`
   - Verify merge completed: `gh pr view --json merged --jq .merged` (must be `true`)
   - Exit the worktree with `ExitWorktree action: "remove", discard_changes: true` (safe — squash merge confirmed on main)
   - Switch to main and pull to sync the merge locally
4. If not approved:
   - Exit the worktree with `ExitWorktree action: "keep"`
