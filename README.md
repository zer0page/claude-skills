![CI](https://github.com/zer0page/claude-skills/actions/workflows/test.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Built with Claude Code](https://img.shields.io/badge/Built%20with-Claude%20Code-blueviolet)

# claude-skills

Reusable [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skills for development workflows.

## Skills

| Skill | Description |
|-------|-------------|
| `/audit` | Multi-perspective code audit — 5 reviewer personas + PM aggregation |
| `/ci` | Watch CI + bot reviews on a PR, fix failures, push, loop until green |
| `/brainstorming` | Transform vague ideas into validated designs through structured dialogue |
| `/implement` | Full dev workflow — plan, audit, build, ship (orchestrates `/audit` and `/ci`) |

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) **v2.1.0+** (skills support)
  - **v2.1.63+** required if using `/implement` (depends on the built-in `/simplify` skill)
- `git`
- `gh` ([GitHub CLI](https://cli.github.com/)) — required for `/ci`

## Install

Clone this repo, then symlink skills into your Claude Code environment:

```bash
git clone <repo-url> claude-skills
cd claude-skills
./install                     # Global: ~/.claude/skills/
./install --project /path     # Project-local: /path/.claude/skills/
./install --skill audit       # Just one skill
./install --uninstall         # Remove symlinks
```

## Configuration

Skills read project-specific settings from your `CLAUDE.md`. Currently configurable:

### `/ci` — review bot

By default, `/ci` uses GitHub Copilot as the automated reviewer. Override in your project's `CLAUDE.md`:

```markdown
review_bot: my-company-reviewer[bot]
```

Set to `none` to skip automated review requests entirely (CI-only mode).

## License

MIT
