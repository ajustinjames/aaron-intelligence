# caveman-lite

Ultra-compressed communication mode, stripped down to just the two Claude
Code hooks. Built as a lighter alternative to the
[`caveman`](https://github.com/JuliusBrussee/caveman) plugin for use
alongside multi-agent orchestration layers, where caveman's 3 global agents
(`cavecrew-*`) and 4 slash commands (`/caveman-*`) can collide with another
plugin's own agent/command namespace.

## What's included

- `SessionStart` hook — activates caveman mode and injects the ruleset
- `UserPromptSubmit` hook — tracks natural-language toggles ("talk like
  caveman", "stop caveman"), reinforces the active mode every turn
- One slash command, `/caveman-lite [lite|full|ultra|wenyan|wenyan-lite|wenyan-ultra|off]`,
  to switch levels deterministically

## What's deliberately left out

- No agents (no `cavecrew-*`)
- No `/caveman-commit`, `/caveman-review`, `/caveman-compress`, `/caveman-stats`
- No skills

If you don't want to install even hooks, see [`caveman-lite.md`](./caveman-lite.md)
for a copy-pasteable prompt block with the same behavior and zero runtime
footprint.

## Install

```
/plugin install caveman-lite@aaron-intelligence
```

## Configuration

Same resolution order as upstream caveman:

1. `CAVEMAN_DEFAULT_MODE` env var
2. `defaultMode` in `~/.config/caveman/config.json` (or `$XDG_CONFIG_HOME/caveman/config.json`)
3. `full` (default)

Valid modes: `off`, `lite`, `full`, `ultra`, `wenyan-lite`, `wenyan`/`wenyan-full`, `wenyan-ultra`.

## Security note

The `/caveman-lite` command passes its argument (`$ARGUMENTS`) to a shell
command, and Claude Code does not currently shell-escape that interpolation
([anthropics/claude-code#16163](https://github.com/anthropics/claude-code/issues/16163)).
The command is gated human-only with `disable-model-invocation: true`, so the
model cannot invoke it with an attacker-supplied argument, and the set-mode
script whitelist-validates the token against the valid-modes list. Even so:
only type or paste a trusted mode token (e.g. `lite`, `off`) as the argument —
never an untrusted string.
