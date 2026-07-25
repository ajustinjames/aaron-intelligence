#!/usr/bin/env bash

set -euo pipefail

TMUX_SESSION="${CLAUDE_RC_TMUX_SESSION:-claude-rc}"
WORKSPACE_ROOT="${2:-${CLAUDE_RC_WORKSPACE_ROOT:-$PWD}}"

PROJECTS=()

usage() {
  cat <<'EOF'
Usage: claude-remote-control <command> [workspace-root]

Commands:
  start    Start one workspace server plus one per discovered repository
  stop     Stop all Remote Control servers managed by this script
  restart  Stop and start the servers beneath workspace-root
  update   Stop servers, update Claude Code, then start beneath workspace-root
  status   Show the managed tmux windows
  attach   Attach to the managed tmux session

Environment:
  CLAUDE_RC_WORKSPACE_ROOT  Fallback when workspace-root is omitted
  CLAUDE_RC_TMUX_SESSION    tmux session name (default: claude-rc)

workspace-root defaults to the current directory.

Run this script on the host, not inside an isolated agent sandbox. A sandbox may
not be able to see or stop the host tmux session.
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

discover_projects() {
  mapfile -d '' PROJECTS < <(
    find "$WORKSPACE_ROOT" -mindepth 1 -type d \
      -exec test -d '{}/.git' ';' -print0 -prune
  )

  if (( ${#PROJECTS[@]} == 0 )); then
    echo "No Git repositories found under: $WORKSPACE_ROOT" >&2
    exit 1
  fi
}

validate_configuration() {
  require_command claude
  require_command find
  require_command tmux

  if [[ ! -d "$WORKSPACE_ROOT" ]]; then
    echo "Workspace directory not found: $WORKSPACE_ROOT" >&2
    exit 1
  fi

  WORKSPACE_ROOT="$(cd -- "$WORKSPACE_ROOT" && pwd)"
  discover_projects
}

server_command() {
  local target_dir="$1"
  local target_name="$2"
  local command

  printf -v command \
    'cd %q && exec claude remote-control --name %q --spawn same-dir --capacity 3' \
    "$target_dir" "$target_name"
  printf '%s' "$command"
}

add_server_window() {
  local target_dir="$1"
  local target_name="$2"
  local window_name="${target_name//\//-}"

  if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux new-session -d -s "$TMUX_SESSION" -n "$window_name" \
      "$(server_command "$target_dir" "$target_name")"
  else
    tmux new-window -d -t "$TMUX_SESSION" -n "$window_name" \
      "$(server_command "$target_dir" "$target_name")"
  fi
}

start_servers() {
  validate_configuration

  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "Remote Control tmux session already exists: $TMUX_SESSION" >&2
    echo "Run '$0 status' or '$0 restart'." >&2
    exit 1
  fi

  add_server_window "$WORKSPACE_ROOT" "workspace"

  local project_dir
  local project_name
  for project_dir in "${PROJECTS[@]}"; do
    project_name="${project_dir#"$WORKSPACE_ROOT"/}"
    add_server_window "$project_dir" "$project_name"
  done

  echo "Started project-scoped Claude Remote Control servers:"
  status_servers
}

stop_servers() {
  require_command tmux

  if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "Remote Control tmux session is not running: $TMUX_SESSION"
    return
  fi

  tmux kill-session -t "$TMUX_SESSION"
  echo "Stopped Remote Control tmux session: $TMUX_SESSION"
}

update_servers() {
  stop_servers
  require_command claude
  claude update
  start_servers
}

status_servers() {
  require_command tmux

  if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "Remote Control tmux session is not running: $TMUX_SESSION"
    return 1
  fi

  tmux list-windows -t "$TMUX_SESSION" \
    -F '#{window_name}: #{?pane_dead,stopped,running} (pid #{pane_pid})'
}

attach_servers() {
  require_command tmux

  if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "Remote Control tmux session is not running: $TMUX_SESSION" >&2
    exit 1
  fi

  exec tmux attach-session -t "$TMUX_SESSION"
}

case "${1:-}" in
  start)
    start_servers
    ;;
  stop)
    stop_servers
    ;;
  restart)
    stop_servers
    start_servers
    ;;
  update)
    update_servers
    ;;
  status)
    status_servers
    ;;
  attach)
    attach_servers
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
