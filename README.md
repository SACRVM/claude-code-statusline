# claude-code-statusline

A status line for [Claude Code](https://claude.com/claude-code) that shows **real usage percentages** straight from Anthropic's rate-limit API — no self-invented limits, no token guessing.

```
the-fishbowl · master · Opus 4.7 (1M) · ctx ████░░░░ 41% · 5h ██░░░░░░ 23% (3h12m) · wk █░░░░░░░ 8% (4d18h)
```

- **Project name** (cwd basename)
- **Git branch** (current)
- **Model** (Claude Code's `display_name`)
- **Context %** (from Claude Code's pre-calculated `context_window.used_percentage`, with a transcript-tokens fallback for the very first turn)
- **5-hour limit** with reset countdown
- **7-day limit** with reset countdown

The 5h / 7d numbers come from Claude Code's stdin payload (`rate_limits.{five_hour,seven_day}.used_percentage`), which Claude Code itself sources from `https://api.anthropic.com/api/oauth/usage` — the same numbers shown on [claude.ai/usage](https://claude.ai/usage). Requires Claude Code v2.1.80+.

Color thresholds: green < 50%, yellow ≥ 50%, red ≥ 80%. Catppuccin Mocha palette, 24-bit truecolor.

## Install

1. **Drop the script** into your Claude config directory:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/chloe-dream/claude-code-statusline/main/statusline-command.sh \
     -o ~/.claude/statusline-command.sh
   chmod +x ~/.claude/statusline-command.sh
   ```

2. **Wire it into `~/.claude/settings.json`**:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline-command.sh",
       "refreshInterval": 60
     }
   }
   ```

3. Restart Claude Code (or run `/statusline` to reload).

### Windows

Works under Git Bash or WSL. The `command` line stays the same — Claude Code on Windows already runs it through its bundled bash.

## Requirements

- `bash`, `sed`, `grep`, `date`, `tac` — standard on macOS / Linux / Git Bash
- No `jq` dependency (JSON is parsed with `sed`)
- Truecolor terminal (any modern terminal; Windows Terminal, iTerm2, Alacritty, kitty, etc.)

## Notes

- **API-key users see no 5h/7d bars** — those rate-limit fields are only populated for OAuth (Claude Pro/Max) sessions.
- Reset times format adaptively: `<1m`, `42m`, `3h12m`, `2d18h`, `6d`.
- The script reads stdin once and never makes its own network calls.

## License

MIT — see [LICENSE](LICENSE).
