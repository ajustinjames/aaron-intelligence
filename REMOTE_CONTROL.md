# Remote Control

Start Remote Control only when it is needed. Codex starts from the workspace
root and selects target repositories from remote sessions. Claude starts from
the target repository in a detached tmux session so it remains available after
the terminal closes.

Run these commands on the host rather than in an isolated agent sandbox. A
sandbox may have a different process or tmux namespace.

## Codex

Change to the workspace root and use Codex's native Remote Control command:

```bash
cd /path/to/workspace
codex remote-control start
```

Start only one Codex Remote Control process for the workspace. Remote sessions
can select the target repository within that workspace. Codex needs no tmux
session or repository script. Use its native pairing command when needed:

```bash
codex remote-control pair
```

## Claude

Choose a short, unique tmux session name beginning with `claude-rc-`, change to
the target repository, and start Claude:

```bash
cd /path/to/repository
tmux new-session -d -s claude-rc-my-project \
  'claude remote-control'
```

Use one tmux session per repository. The `claude-rc-` prefix lets the shutdown
helper distinguish these sessions from unrelated tmux work.

After starting the session, inspect its output without attaching or sending
input:

```bash
tmux capture-pane -p -t claude-rc-my-project -S -100
```

Claude may pause for a trust confirmation, spawn-mode choice, or another
interactive prompt. Report the exact prompt to the user and ask for permission
before sending any response, including accepting a default with Enter. Only
after the user explicitly approves should you send the requested input:

```bash
tmux send-keys -t claude-rc-my-project Enter
```

Inspect the pane again and confirm that Remote Control reports `Ready` or
`Connected`. A live tmux pane or Claude process alone does not prove that Remote
Control finished starting.

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
