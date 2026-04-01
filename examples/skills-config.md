# Example: Skills Config in CLAUDE.md

Add these to your project's `CLAUDE.md` to customize skill behavior.

## Using a custom review bot

```markdown
review_bot: my-company-reviewer[bot]
```

The `/ci` skill reads this and uses `my-company-reviewer[bot]` instead of Copilot for automated review requests and monitoring.

## CI-only mode (no review bot)

```markdown
review_bot: none
```

Skips all automated review request/wait steps. Only monitors CI pass/fail.

## Default behavior (no config needed)

If your `CLAUDE.md` doesn't mention `review_bot`, `/ci` defaults to `copilot-pull-request-reviewer[bot]`.
