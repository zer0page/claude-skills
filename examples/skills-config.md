# Example: Skills Config via settings.json

Configure skill behavior in `~/.claude/settings.json`. The `./install` script sets defaults automatically.

## Review bot

Set the `REVIEW_BOT` env var to control which bot `/ci` requests for automated reviews.

### Default (set by install)

```json
{
  "env": {
    "REVIEW_BOT": "copilot-pull-request-reviewer[bot]"
  }
}
```

### Custom review bot

```json
{
  "env": {
    "REVIEW_BOT": "my-company-reviewer[bot]"
  }
}
```

### CI-only mode (no review bot)

```json
{
  "env": {
    "REVIEW_BOT": "skip"
  }
}
```

Skips all automated review request/wait steps. Only monitors CI pass/fail.

## Agent Teams

Required for `/audit` to spawn reviewer personas as Agent Team teammates.

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Both env vars are set automatically by `./install`.
