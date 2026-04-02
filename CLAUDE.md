Before committing, validate all skills/*/SKILL.md files for clarity, completeness, and consistency. Fix any issues before proceeding with the commit.

Scripts in skills must follow the Claude Code skills spec: use `{{SKILL_DIR}}` to reference the skill directory (expands at runtime), place scripts in a `scripts/` subdirectory, and register them in `allowed-tools` frontmatter if needed.

Before committing, run any `test_*` scripts found in the changed skill's directory (e.g., `skills/ci/scripts/test_*`) and verify they pass.
