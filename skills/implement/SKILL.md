---
name: implement
description: Full development workflow — brainstorm, plan, audit, simplify, build, ship. Orchestrates /brainstorming, /audit, /simplify, and /ci into a repeatable loop from idea to merged PR. Use --quick to skip audits for trivial changes. Use when building, developing, creating, implementing, shipping, delivering, or coding a feature end-to-end from plan to merged PR.
---

# /implement [description] [--quick]

## Purpose

End-to-end workflow from idea to merged PR. Orchestrates `/brainstorming`, `/audit`, `/simplify`, and `/ci` into sequential phases.

Prevents: skipping phases, committing to main, implementing without a plan, shipping without review.

`--quick` skips audit phases (4 and 6). All other phases are mandatory.

## Operating Mode

You are an **orchestrator** — delegate to sub-skills, gate on user approval between phases. Never implement without a plan. Never commit to main directly.

All work happens in a worktree. Enter in Phase 2, exit in Phase 8 (if `/ci` merges) or Phase 9 (`remove` on merge, `keep` otherwise).

Name the worktree from the description (lowercase, hyphens, max 30 chars). If collision, append `-2`, `-3`, etc.

## The Process

### Phase 0: Quick check

If the change appears trivial (single-file fix, small bug) and `--quick` was not already passed, `AskUserQuestion` whether to use `--quick` (skip audit phases 4 and 6). Gate on the answer before proceeding.

### Phase 1: Brainstorm

1. Run `/brainstorming` to explore the idea.
2. `AskUserQuestion` for additional context before planning.

### Phase 2: Plan

1. `EnterWorktree` with slugified description.
2. Configure git identity if empty (try `git log -1`, fall back to global config, abort if still empty).
3. Enter plan mode.
4. Write implementation plan from Phase 1 design.
5. Validate all `skills/*/SKILL.md` for consistency — include fixes in plan.
6. `AskUserQuestion` for unresolved questions.

### Phase 3: Gate — user approves plan

1. `ExitPlanMode` to present the plan. Phase 4 may revise it.
2. `AskUserQuestion` for explicit approval.

### Phase 4: Pre-implementation audit

_Skipped with `--quick`._

1. Run `/audit --no-handoff` on the primary target directory from the plan.
2. Fix findings — revise plan if needed.
3. `AskUserQuestion` to present findings and request approval.

### Phase 5: Implement

1. Build the feature following the plan. Only modify files in the plan.
2. Commit locally — do not push yet.

### Phase 6: Audit diff

_Skipped with `--quick`._

1. Run `/audit --diff --no-handoff` on committed changes.
2. Fix findings and commit.
3. Print one-line status summary.

### Phase 7: Simplify

1. Run `/simplify` on changed code.
2. Fix issues and commit.
3. `AskUserQuestion` for approval before pushing.

### Phase 8: Ship

1. Push and create draft PR.
2. Run `/ci --max 10`.
3. `/ci` presents completion options:
   - **Mark ready** → remove draft status, proceed to Phase 9.
   - **Clean up and reopen** → squash commits, force-push, close and reopen PR. Re-fetch new PR URL, proceed to Phase 9.
   - **Merge and close** _(only if `merge_state` is `CLEAN`)_ → follow `/ci` Completion merge steps, then `ExitWorktree remove` with `discard_changes: true` (squash SHA differs from local), `git pull` (ExitWorktree returns to main). Skip Phase 9.

### Phase 9: Gate — user decides

1. Report PR URL and status.
2. `AskUserQuestion`: approve merge, or keep worktree for later.
3. On merge approval: follow `/ci` Completion merge steps, then `ExitWorktree remove` with `discard_changes: true` (squash SHA differs from local), `git pull` (ExitWorktree returns to main).
4. Otherwise: `ExitWorktree keep`.

## Exit Criteria

- PR merged and worktree removed, OR
- Worktree kept for later work

## Key Principles

- All phases are mandatory and sequential except phases 4 and 6, which are skipped with `--quick`. Never reorder.
- Never commit directly to main.
- Always gate on user approval before implementation and merge.
- Only modify files identified in the plan.
- Keep changes minimal and focused.
- Never skip `/ci` — CI detection is handled by the scripts.
