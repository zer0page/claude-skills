---
name: implement
description: Full development workflow — brainstorm, plan, audit, simplify, build, ship. Orchestrates /brainstorming, /audit, /simplify, and /ci into a repeatable loop from idea to merged PR. Use when building, developing, creating, implementing, shipping, delivering, or coding a feature end-to-end from plan to merged PR.
---

# /implement [description]

## Purpose

End-to-end workflow from idea to merged PR. Orchestrates `/brainstorming`, `/audit`, `/simplify`, and `/ci` into sequential phases.

Prevents: silently skipping phases, committing to main, implementing without a plan, shipping without review.

Both audit phases (4 and 6) have user gates. The agent never skips an audit without explicit user approval.

## Operating Mode

You are an **orchestrator** — delegate to sub-skills, gate on user approval between phases. Never implement without a plan. Never commit to main directly.

All work happens in a worktree. Enter in Phase 2, exit in Phase 8 (if `/ci` merges) or Phase 9 (`remove` on merge, `keep` otherwise).

Name the worktree from the description (lowercase, hyphens, max 30 chars). If collision, append `-2`, `-3`, etc.

## The Process

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

1. `AskUserQuestion` with three options:
   - **Run audit** — proceed with pre-implementation audit.
   - **Skip audit** — proceed directly to Phase 5 (implementation).
   - **Refine plan** — return to Phase 2 step 3 (enter plan mode, revise plan, then Phase 3 re-approval and repeat Phase 4).
2. If run audit: `/audit --core --no-handoff [primary-target-directory]` from the plan.
3. If run audit: fix findings. If plan scope changes, return to Phase 3 for re-approval.

### Phase 5: Implement

1. Build the feature following the plan. Only modify files in the plan.
2. Commit locally — do not push yet.

### Phase 6: Audit diff

1. Assess the committed diff: size (files/lines changed), complexity (new logic, refactors, API surface changes), and risk areas (concurrency, security, data handling).
2. Based on the assessment, recommend **run audit** or **skip to simplify** with a one-line rationale.
3. `AskUserQuestion` with three options:
   - **Run audit** — run `/audit --diff --no-handoff` on committed changes (full personas — no `--core`). Fix findings and commit.
   - **Skip to simplify** — proceed directly to Phase 7.
   - **Iterate on implementation** — return to Phase 5 to revise, then re-present this gate.
4. Print one-line status summary.

### Phase 7: Simplify

1. Run `/simplify` on changed code.
2. Fix issues and commit.
3. `AskUserQuestion` for approval before pushing.

### Phase 8: Ship

1. Push and create draft PR.
2. Invoke the `/ci --max 10` skill command. Do not run CI scripts directly or inline CI logic — the `/ci` skill and its scripts handle all detection and polling.
3. `/ci` presents completion options:
   - **Mark ready** → remove draft status, proceed to Phase 9.
   - **Clean up and reopen** → squash commits, force-push, close and reopen PR. Re-fetch new PR URL, proceed to Phase 9.
   - **Merge and close** _(only if `merge_state` is `CLEAN`)_ → follow `/ci` Completion merge steps, then `ExitWorktree remove` with `discard_changes: true` (squash SHA differs from local), `git pull` (ExitWorktree returns to main). Skip Phase 9.
4. If merge fails (PR `state` from `gh pr view --json state` is not `MERGED` during `/ci` completion verification): keep worktree, report error with PR URL, stop. User must resolve blocking checks or conflicts before retry.

### Phase 9: Gate — user decides

1. Report PR URL and status.
2. `AskUserQuestion`: approve merge, or keep worktree for later.
3. On merge approval: follow `/ci` Completion merge steps, then `ExitWorktree remove` with `discard_changes: true` (squash SHA differs from local), `git pull` (ExitWorktree returns to main).
4. Otherwise: `ExitWorktree keep`.

## Exit Criteria

- PR merged and worktree removed, OR
- Worktree kept for later work

## Key Principles

- Follow phases in order. Never reorder. Audit phases (4 and 6) are never skipped without explicit user approval at their respective gates. Never skip automatically based on agent reasoning.
- Never commit directly to main.
- Always gate on user approval before implementation and merge.
- Only modify files identified in the plan.
- Keep changes minimal and focused.
- Never skip `/ci` — CI detection is handled by the scripts.
- Phase 8 is mandatory regardless of change size, type, or perceived risk. The agent never assesses whether CI is needed — it always is.
