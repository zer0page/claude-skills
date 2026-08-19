Before committing, run `./test_skill_format` and `./test_install` and validate all `skills/*/SKILL.md` files for clarity, completeness, and consistency.

## SKILL.md style

Skills must follow the standard Agent Skills format shared by Amp and Claude Code:

- YAML frontmatter with `name` and `description` only.
- Capability-based instructions, not product-specific tool names.
- No Claude-only APIs, slash-command dependencies, experimental Agent Teams, or template variables.
- Keep provider-specific settings and hooks outside `SKILL.md`.

If a skill needs a script, describe it with a path relative to the skill directory and ensure both agents can resolve it.
