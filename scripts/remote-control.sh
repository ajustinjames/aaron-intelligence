#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_LAUNCHER="$SCRIPT_DIR/claude-remote-control.sh"
CODEX_LAUNCHER="$SCRIPT_DIR/codex-remote-control.sh"
WORKSPACE_ROOT="${2:-${REMOTE_CONTROL_WORKSPACE_ROOT:-$PWD}}"

usage() {
  cat <<'EOF'
Usage: remote-control <command> [workspace-root]

Commands:
  start    Start Claude and Codex Remote Control beneath workspace-root
  stop     Stop Claude and Codex Remote Control
  restart  Stop and start both Remote Control services
  update   Stop both, update both CLIs, then start both beneath workspace-root
  status   Show Claude status (Codex does not expose a status command)
  attach   Attach to the managed Claude tmux session
  pair     Create a Codex Remote Control pairing code

Environment:
  REMOTE_CONTROL_WORKSPACE_ROOT  Fallback when workspace-root is omitted

workspace-root defaults to the current directory.

Run this script on the host, not inside an isolated agent sandbox. A sandbox may
not be able to see or control the host tmux session or app-server daemon.
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

resolve_workspace() {
  if [[ ! -d "$WORKSPACE_ROOT" ]]; then
    echo "Workspace directory not found: $WORKSPACE_ROOT" >&2
    exit 1
  fi

  WORKSPACE_ROOT="$(cd -- "$WORKSPACE_ROOT" && pwd)"
}

start_services() {
  resolve_workspace

  "$CLAUDE_LAUNCHER" start "$WORKSPACE_ROOT"
  if ! "$CODEX_LAUNCHER" start "$WORKSPACE_ROOT"; then
    echo "Codex Remote Control failed to start; stopping Claude Remote Control." >&2
    "$CLAUDE_LAUNCHER" stop
    return 1
  fi
}

stop_services() {
  local failed=0

  "$CLAUDE_LAUNCHER" stop || failed=1
  "$CODEX_LAUNCHER" stop || failed=1

  return "$failed"
}

update_services() {
  stop_services
  require_command claude
  require_command codex
  claude update
  codex update
  start_services
}

case "${1:-}" in
  start)
    start_services
    ;;
  stop)
    stop_services
    ;;
  restart)
    stop_services
    start_services
    ;;
  update)
    update_services
    ;;
  status)
    "$CLAUDE_LAUNCHER" status
    echo "Codex Remote Control does not expose a status command."
    ;;
  attach)
    exec "$CLAUDE_LAUNCHER" attach
    ;;
  pair)
    "$CODEX_LAUNCHER" pair
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
