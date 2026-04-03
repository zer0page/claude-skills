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
| `/implement` | Full dev workflow — plan, audit, build, ship (orchestrates `/brainstorming`, `/audit`, `/ci`, and `/simplify`) |

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) **v2.1.0+** (skills support)
  - **v2.1.63+** required if using `/implement` (depends on the built-in `/simplify` skill)
- `git`
- `gh` ([GitHub CLI](https://cli.github.com/)) — required for `/ci`
- `jq` — required for `./install` to auto-configure `~/.claude/settings.json`

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

The `./install` script auto-configures `~/.claude/settings.json` with sensible defaults. You can customize:

### `/ci` — review bot (`REVIEW_BOT`)

Controls which bot `/ci` requests for automated PR reviews. Set in `~/.claude/settings.json`:

```json
{
  "env": {
    "REVIEW_BOT": "copilot-pull-request-reviewer[bot]"
  }
}
```

- Default (set by install): `copilot-pull-request-reviewer[bot]`
- Custom bot: any bot login (e.g., `my-company-reviewer[bot]`)
- `skip`: disable automated review requests (CI-only mode)

### `/audit` — Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`)

Enables Agent Teams for `/audit` reviewer personas. Set automatically by `./install`.

## License

MIT
