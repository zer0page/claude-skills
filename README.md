![CI](https://github.com/zer0page/claude-skills/actions/workflows/test.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

# claude-skills

Personal Agent Skills that work with [Amp](https://ampcode.com/) and [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

## Skills

| Skill | Description |
|-------|-------------|
| `audit` | Read-only, multi-perspective code audit with a prioritized final report |

## Prerequisites

- Amp or Claude Code with Agent Skills support
- `jq` only when enabling the optional Claude tmux notification hooks

## Install

Clone this repo, then symlink skills into the shared user skill location. Both Amp and Claude Code discover `~/.claude/skills`:

```bash
git clone <repo-url> claude-skills
cd claude-skills
./install                     # Global: ~/.claude/skills/
./install --project /path     # Project-local: /path/.claude/skills/
./install --skill audit       # Just one skill
./install --skills-only       # Never prompt for or modify Claude hooks/settings
./install --uninstall         # Remove symlinks
```

The installer preserves files and links it does not own. Project-local and `--skills-only` installs do not modify global settings.

## Optional Claude Code integration

Running `./install` without `--skills-only` offers to configure tmux pane notifications for Claude Code. To choose explicitly:

```bash
./install --tmux-notify 1     # Enable
./install --tmux-notify 0     # Disable
```

## License

MIT
