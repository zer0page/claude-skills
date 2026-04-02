Before committing, validate all skills/*/SKILL.md files for clarity, completeness, and consistency. Fix any issues before proceeding with the commit.

Before committing, run any `test_*` scripts found in the changed skill's directory (e.g., `skills/ci/scripts/test_*`) and verify they pass.

## SKILL.md style

Every SKILL.md follows this structure:

1. **Purpose** — What this skill does. What it prevents (anti-patterns). Constraints.
2. **Operating Mode** — Persona or mindset. What NOT to do.
3. **The Process** — Numbered steps with brief bullets. No inline bash blocks — use scripts or one-line descriptions.
4. **Exit Criteria** — When the skill is done. Hard stop conditions.
5. **Key Principles** — Behavioral guardrails. Non-negotiable rules.

Reference scripts by `{{SKILL_DIR}}/scripts/<name>` path.

## Scripts

Follow the Claude Code skills spec: use `{{SKILL_DIR}}` to reference the skill directory (expands at runtime), place scripts in a `scripts/` subdirectory, and register them in `allowed-tools` frontmatter if needed. Scripts may normalize raw API data (field mapping) only if it reduces token count without losing context — otherwise return raw data. Scripts must not return aggregated verdicts — let the LLM reason about the data. Internal computations for control flow (loop termination, log filtering) are fine.
