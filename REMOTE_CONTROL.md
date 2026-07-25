# Remote Control

Start Remote Control only when it is needed, from the repository it should
control. Codex manages its own process. Claude runs in a detached tmux session
so it remains available after the terminal closes.

Run these commands on the host rather than in an isolated agent sandbox. A
sandbox may have a different process or tmux namespace.

## Codex

Change to the target repository and use Codex's native Remote Control command:

```bash
cd /path/to/repository
codex remote-control start
```

Codex uses the current directory as its workspace and needs no tmux session or
repository script. Use its native pairing command when needed:

```bash
codex remote-control pair
```

## Claude

Choose a short, unique tmux session name beginning with `claude-rc-`, change to
the target repository, and start Claude:

```bash
cd /path/to/repository
tmux new-session -d -s claude-rc-my-project \
  'exec claude remote-control --name my-project --spawn same-dir --capacity 3'
```

Use one tmux session per repository. The `claude-rc-` prefix lets the shutdown
helper distinguish these sessions from unrelated tmux work.

Useful tmux commands:

```bash
# List active Claude Remote Control sessions
tmux list-sessions -F '#{session_name}' | grep '^claude-rc-'

# Attach to one
tmux attach-session -t claude-rc-my-project

# Stop one
tmux kill-session -t claude-rc-my-project
```

To stop every Claude Remote Control session that follows the naming convention:

```bash
./scripts/stop-claude-remote-controls.sh
```

The helper only kills tmux sessions whose names begin with `claude-rc-`. Override
the prefix with `CLAUDE_RC_TMUX_PREFIX` if a different convention is required.
