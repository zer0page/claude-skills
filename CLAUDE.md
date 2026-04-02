Before committing, validate all skills/*/SKILL.md files for clarity, completeness, and consistency. Fix any issues before proceeding with the commit.

Before committing, run any `test_*` scripts found in the changed skill's directory (e.g., `skills/ci/scripts/test_*`) and verify they pass.

## SKILL.md style

- Concise, imperative voice. Lead with action, not explanation.
- Numbered steps for sequential operations. Bullet lists for options/rules.
- Minimal prose — if it can be a code block or one-liner, do that.
- No "you should" or "consider" — just state what to do.
- Reference scripts by `{{SKILL_DIR}}/scripts/<name>` path.

## Scripts

Follow the Claude Code skills spec: use `{{SKILL_DIR}}` to reference the skill directory (expands at runtime), place scripts in a `scripts/` subdirectory, and register them in `allowed-tools` frontmatter if needed. Scripts must not interpret or compute verdicts — return raw data from APIs and let the LLM decide.
