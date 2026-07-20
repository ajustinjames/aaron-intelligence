#!/usr/bin/env bash

set -euo pipefail

WORKSPACE_ROOT="${2:-${CODEX_RC_WORKSPACE_ROOT:-$PWD}}"

usage() {
  cat <<'EOF'
Usage: codex-remote-control <command> [workspace-root]

Commands:
  start    Start Codex Remote Control from workspace-root
  stop     Stop Codex Remote Control
  restart  Stop and start Codex Remote Control from workspace-root
  update   Stop, update Codex, then start from workspace-root
  pair     Create a Codex Remote Control pairing code

Environment:
  CODEX_RC_WORKSPACE_ROOT  Fallback when workspace-root is omitted

workspace-root defaults to the current directory.

Run this script on the host, not inside an isolated agent sandbox. A sandbox may
not be able to see or control the host app-server daemon.
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

start_service() {
  require_command codex
  resolve_workspace
  (cd -- "$WORKSPACE_ROOT" && codex remote-control start)
}

stop_service() {
  require_command codex
  codex remote-control stop
}

update_service() {
  stop_service
  codex update
  start_service
}

case "${1:-}" in
  start)
    start_service
    ;;
  stop)
    stop_service
    ;;
  restart)
    stop_service
    start_service
    ;;
  update)
    update_service
    ;;
  pair)
    require_command codex
    codex remote-control pair
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
