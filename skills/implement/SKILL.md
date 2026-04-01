---
name: implement
description: Full development workflow — plan, audit, simplify, build, ship. Orchestrates /audit, /simplify, and /ci into a repeatable loop from idea to merged PR. Use --quick to skip audits for trivial changes. Use when building, developing, creating, implementing, shipping, delivering, or coding a feature end-to-end from plan to merged PR.
---

# /implement [description] [--quick]

End-to-end workflow for building features and updates. **Every phase is mandatory and sequential — do not skip or reorder phases.** The only exception is `--quick`, which skips the two audit phases.

`--quick` skips Phase 2 and Phase 5 (both audits) for trivial changes. All other phases are always required.

## Phase 1: Plan

1. Enter plan mode
2. Explore the codebase to understand the request
3. Ask the user clarifying questions — iterate until aligned
4. Write a concrete implementation plan
5. Do not exit plan mode yet — next is Phase 2 (or Phase 3 if using `--quick`)

## Phase 2: Audit plan

_Skipped only with `--quick`._

1. Run `/audit` on the plan file before asking the user to approve
2. Revise the plan based on audit findings
3. Update the plan file
4. Only after this phase is complete, proceed to Phase 3

Fix findings and continue to the next phase. If a finding requires a scope or design decision change, ask the user first.

## Phase 3: Gate — user approves execution

Present the final plan and ask the user to approve before writing any code. Do not proceed without explicit approval.

## Phase 4: Implement

1. Exit plan mode
2. Create a branch or worktree from main (never commit directly to main). Use a worktree when running as a parallel agent.
3. Build the feature, following the plan
4. Keep changes minimal and focused on the plan
5. Commit locally with a descriptive message — do not push yet. Phase 5 comes first (or Phase 6 if `--quick`).

## Phase 5: Audit diff

_Skipped only with `--quick`._

1. Ensure all changes are committed locally (do not push)
2. Run `/audit --diff` on the changes
3. Fix any issues found
4. Commit the fixes
5. Verify `git status` is clean. Only after this phase is complete, proceed to Phase 6

Fix findings and continue to the next phase. If a finding requires a scope or design decision change, ask the user first.

## Phase 6: Simplify

1. Run `/simplify` on the changed code
2. Fix any reuse, quality, or efficiency issues found
3. Commit the fixes
4. Only after this phase is complete, proceed to Phase 7

## Phase 7: Ship

1. Push and create a draft PR
2. Run `/ci --max 10` — fix failures and review comments until clean

## Phase 8: Gate — user approves merge

1. Report the PR URL and status
2. Ask the user to approve the merge
3. On approval:
   - Mark PR ready and squash merge
   - Switch to main and pull
   - Confirm completion
