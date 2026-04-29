---
name: implement
description: Full development workflow from idea to merged PR. Orchestrates superpowers:brainstorming, superpowers:writing-plans, superpowers:subagent-driven-development, /audit (optional), and /ci (mandatory) into sequential phases. Use when building, developing, creating, implementing, shipping, delivering, or coding a feature end-to-end from plan to merged PR.
---

# /implement [description]

## Purpose

End-to-end workflow from idea to merged PR. Orchestrates `superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:subagent-driven-development`, `/audit` (optional), and `/ci` (mandatory) into sequential phases.

Prevents: silently skipping phases, committing to main, implementing without a plan, shipping without review.

`/audit` (Phase 5) has a user gate — agent recommends but never auto-skips. `/ci` (Phase 6) is always mandatory.

## Operating Mode

You are an **orchestrator** — delegate to sub-skills, gate on user approval between phases. Never implement without a plan. Never commit to main directly.

All work happens in a worktree. Enter in Phase 1, exit in Phase 6 (if `/ci` merges) or via the final user gate (`remove` on merge, `keep` otherwise).

Name the worktree from the description (lowercase, hyphens, max 30 chars). If collision, append `-2`, `-3`, etc.

When invoking superpowers sub-skills, pass explicit overrides:

- `superpowers:brainstorming`: do NOT commit the spec; return control to /implement after spec approval — do NOT auto-chain to `superpowers:writing-plans`.
- `superpowers:writing-plans`: do NOT commit the plan.
- `superpowers:subagent-driven-development`: stop after the final code reviewer subagent; do NOT invoke `superpowers:finishing-a-development-branch`. Return control to /implement.

If a sub-skill ignores an override (announces a chained skill we did not authorize, or pushes/creates a PR before Phase 6), stop, report the conflict by name, and ask the user how to recover. Do not attempt to undo.

Cleanliness checks (Phase 4 step 4, Phase 6 step 1) refer to working-tree changes **outside** `docs/superpowers/specs/` and `docs/superpowers/plans/`. Spec and plan files in those paths are intentionally untracked scratch artifacts (per their no-commit overrides) and do not block progression.

## The Process

### Phase 1: Worktree + Brainstorm

1. `EnterWorktree` with slugified description. Capture the worktree's starting commit SHA as `BASE_SHA` (used in Phase 4 to verify implementation commits).
2. Configure git identity if empty (try `git log -1`, fall back to global config, abort if still empty).
3. Ensure `docs/superpowers/specs/` exists inside the worktree (`mkdir -p` if needed). Compute a concrete `SPEC_PATH = docs/superpowers/specs/<YYYY-MM-DD>-<slug>-design.md` using today's date and the slug. If that path already exists, append `-2`, `-3`, … before `-design.md` until you find a free path; hold the resolved path in `SPEC_PATH`.
4. Invoke `superpowers:brainstorming` with the user's description and the override above. Instruct it to write the spec to `SPEC_PATH`.
5. On return, confirm the spec file exists at `SPEC_PATH`. If brainstorming wrote it elsewhere, move it to `SPEC_PATH` and update the held spec path. If brainstorming returned only in-chat content without writing a file, write it yourself to `SPEC_PATH`. If brainstorming announced `superpowers:writing-plans` (auto-chained despite the override), apply the Operating Mode failure-detection rule — stop and report.

### Phase 2: Plan

1. Invoke `superpowers:writing-plans` with the spec path and the no-commit override.
2. If the plan touches any `skills/*/SKILL.md`, validate sibling skill files for consistency — fold any fixes into the plan.

### Phase 3: Gate — user approves plan

1. Surface the plan file path written by `superpowers:writing-plans` and a brief summary of its task list.
2. `AskUserQuestion`: **approve** / **refine** (return to Phase 2 to revise).

### Phase 4: Implement (TDD via SDD)

1. Invoke `superpowers:subagent-driven-development` with plan path and the do-not-finish override.
2. SDD runs per-task TDD (RED-GREEN-REFACTOR + per-task spec review + per-task code quality review) and a final whole-implementation code review.
3. If SDD reports a `BLOCKED` task it cannot resolve, surface the implementer's blocker message to the user. Do not auto-proceed.
4. After SDD returns, verify there is at least one implementation commit since Phase 1 (`git log $BASE_SHA..HEAD --oneline` is non-empty, using the `BASE_SHA` captured in Phase 1 step 1) and the working tree is clean per the Operating Mode cleanliness rule. If implementation work is uncommitted, commit it or stop and report — do not proceed to Phase 5.

### Phase 5: Audit gate (optional)

1. Assess the committed diff: size (files/lines), complexity (new logic, refactors, API surface), risk areas (concurrency, security, data handling).
2. Recommend **run audit** or **skip to ship** with a one-line rationale.
3. `AskUserQuestion` with three options:
   - **Run audit** — `/audit --diff --no-handoff` on committed changes (full personas, no `--core`). Fix findings via targeted edits, commit, then re-present this gate.
   - **Skip** — proceed to Phase 6.
   - **Self-fix** *(no audit personas)* — orchestrator addresses concerns directly via targeted edits, commits, verifies the working tree is clean per the Operating Mode cleanliness rule, then re-presents this gate. Do not re-invoke SDD for a full re-run.
4. If audit findings require plan-scope changes (new files, new modules, redesign), return to Phase 3 for re-approval — only that path re-enters Phase 4 (SDD).

### Phase 6: Ship

1. Verify the working tree is clean per the Operating Mode cleanliness rule (commit any pending Phase 5 edits first). Push and create draft PR.
2. Invoke `/ci --max 10`. Mandatory. Don't run CI scripts directly or inline CI logic — the `/ci` skill and its scripts handle all detection and polling.
3. `/ci` presents completion options:
   - **Mark ready** → remove draft status, proceed to the final user gate below (step 5).
   - **Clean up and reopen** → squash commits, force-push, close + reopen PR. Re-fetch new PR URL, proceed to the final user gate below (step 5).
   - **Merge and close** _(only if `merge_state` is `CLEAN`)_ → follow `/ci` Completion merge steps, then `ExitWorktree remove` with `discard_changes: true` (squash SHA differs from local), `git pull` (returns to main).
4. If merge fails (PR `state` from `gh pr view --json state` is not `MERGED` during `/ci` completion verification): keep worktree, report error with PR URL, stop. User must resolve blocking checks or conflicts before retry.
5. User gate (skip if already merged via Merge-and-close): report PR URL and status. `AskUserQuestion`: **approve merge** (then follow `/ci` Completion merge steps + `ExitWorktree remove` with `discard_changes: true` + `git pull`) or **keep worktree** (`ExitWorktree keep`).

## Exit Criteria (Hard Stop)

- PR merged and worktree removed, OR
- Worktree kept for later work

## Key Principles (Non-Negotiable)

- Follow phases in order. Never reorder. The audit phase (5) is never skipped without explicit user approval at its gate. Never skip automatically based on agent reasoning.
- Never commit directly to main.
- Always gate on user approval before implementation and merge.
- Only modify files identified in the plan.
- Keep changes minimal and focused.
- Never skip `/ci` — CI detection is handled by the scripts.
- Phase 6 is mandatory regardless of change size, type, or perceived risk.
- Never invoke `superpowers:finishing-a-development-branch` — disposition is the orchestrator's job.
- When invoking superpowers sub-skills, always pass the override instructions described in Operating Mode.
