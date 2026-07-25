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

# Codex exits non-zero when asked to stop a daemon that is not running. Treat
# that as success so restart and update do not abort on an already-stopped
# service; only report a real failure.
stop_service() {
  require_command codex

  if codex remote-control stop; then
    return 0
  fi

  echo "Codex Remote Control was not running, or did not stop cleanly." >&2
  echo "Continuing; verify with 'codex remote-control status' if available." >&2
  return 0
}

update_service() {
  stop_service
  require_command codex
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
