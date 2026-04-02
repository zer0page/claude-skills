---
name: audit
description: Read-only multi-perspective code audit. Spawns 5 reviewer personas tailored to the codebase type then aggregates findings as a PM. Use when reviewing, evaluating, critiquing, auditing, inspecting, examining, analyzing, or assessing PRs, code changes, diffs, implementations, or code quality.
---

# /audit [path] [--diff [base]]

**Read-only.** No edits, commits, branches, or file writes.

## Steps

1. **Classify** the target (frontend, API, CLI, backend, etc.)
2. **Discover project guardrails** — scan for `CLAUDE.md`, `AGENTS.md`, linter configs, architecture docs, and existing test patterns in the target and parent directories. These are the project's established rules — violations always flagged.
3. **Spawn 5 personas as Explore agents** — distributed across parallel agents:
   - Craft/quality · Usability · Beginner · Expert · Security adversary
   - Each: 3-5 issues, file:line, severity (quick-fix / medium / large), concrete fix
4. **Aggregate as PM** — dedupe, categorize (quick-win vs needs-plan), output:
   - Priority table
   - Suggested guardrails (footguns, "don't do X" rules for the project)
   - Architecture drift from established patterns (flag only)

## Diff mode (`--diff`)

Scope to `git diff [base]...HEAD`. Reviewers focus on regressions, missed edge cases, invariant violations, and whether the change achieves its intent. Default base: `main`.

## Output

```
| # | Issue | Flagged By | Severity | Category |
```

Table first. Details on request.

## Handoff

After presenting the aggregated table, use `AskUserQuestion` to confirm findings are understood and the caller can proceed.
