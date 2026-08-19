# Example: Optional Claude tmux notifications

The portable audit skill does not require runtime configuration. The optional Claude Code integration adds a marker to the tmux window name when Claude is waiting for input and clears it when you respond.

## tmux pane notifications

Adds a marker to the tmux window name when Claude is waiting for your input. Clears when you respond. Multi-pane safe — the marker stays until all panes in a window are cleared.

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/tmux-notify.sh notify"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/tmux-notify.sh clear"
          }
        ]
      }
    ]
  }
}
```

Enable with `./install --tmux-notify 1`. The example above uses `$HOME` for readability, but the installer writes an expanded absolute path into `settings.json`. Disable with `./install --tmux-notify 0`.

### Customization

Configure via tmux global options:

```bash
# Change the marker (default: +)
tmux set -g @claude_notify_marker "🔄"

# Append instead of prepend (default: prepend)
tmux set -g @claude_notify_position "append"
```
