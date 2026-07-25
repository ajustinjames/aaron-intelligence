#!/usr/bin/env bash

set -euo pipefail

SESSION_PREFIX="${CLAUDE_RC_TMUX_PREFIX:-claude-rc-}"

if ! command -v tmux >/dev/null 2>&1; then
  echo "Required command not found: tmux" >&2
  exit 1
fi

mapfile -t sessions < <(
  tmux list-sessions -F '#{session_name}' 2>/dev/null |
    while IFS= read -r session; do
      if [[ "$session" == "$SESSION_PREFIX"* ]]; then
        printf '%s\n' "$session"
      fi
    done
)

if (( ${#sessions[@]} == 0 )); then
  echo "No Claude Remote Control tmux sessions found with prefix: $SESSION_PREFIX"
  exit 0
fi

for session in "${sessions[@]}"; do
  tmux kill-session -t "=$session"
  echo "Stopped Claude Remote Control tmux session: $session"
done
