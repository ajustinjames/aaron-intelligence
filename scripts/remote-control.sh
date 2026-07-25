#!/usr/bin/env bash

set -euo pipefail

# Resolve symlinks so the launcher still finds its siblings when it is linked
# onto PATH rather than copied.
resolve_script_dir() {
  local source="${BASH_SOURCE[0]}"
  local dir

  while [[ -L "$source" ]]; do
    dir="$(cd -- "$(dirname -- "$source")" && pwd)"
    source="$(readlink -- "$source")"
    [[ "$source" != /* ]] && source="$dir/$source"
  done

  cd -- "$(dirname -- "$source")" && pwd
}

SCRIPT_DIR="$(resolve_script_dir)"
CLAUDE_LAUNCHER="$SCRIPT_DIR/claude-remote-control.sh"
CODEX_LAUNCHER="$SCRIPT_DIR/codex-remote-control.sh"
WORKSPACE_ROOT="${2:-${REMOTE_CONTROL_WORKSPACE_ROOT:-$PWD}}"

usage() {
  cat <<'EOF'
Usage: remote-control <command> [workspace-root]

Commands:
  list     Show the Claude targets start would launch, without launching them
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

Claude gets one server per discovered repository plus one for the workspace,
each a separate long-lived process. Run 'list' before the first 'start' to see
how many that is; see claude-remote-control.sh --help for the memory guard.

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

require_launchers() {
  local launcher

  for launcher in "$CLAUDE_LAUNCHER" "$CODEX_LAUNCHER"; do
    if [[ ! -x "$launcher" ]]; then
      echo "Companion launcher missing or not executable: $launcher" >&2
      echo "Run this script from the repository checkout, or install the whole" >&2
      echo "scripts/ directory together rather than this file alone." >&2
      exit 1
    fi
  done
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
    "$CLAUDE_LAUNCHER" stop || true
    return 1
  fi
}

# Always attempt both stops, and report a failure only after both have run, so
# one already-stopped service never prevents the other from being stopped.
stop_services() {
  local failed=0

  "$CLAUDE_LAUNCHER" stop || failed=1
  "$CODEX_LAUNCHER" stop || failed=1

  return "$failed"
}

update_services() {
  stop_services || echo "Continuing update despite a stop failure." >&2
  require_command claude
  require_command codex
  claude update
  codex update
  start_services
}

require_launchers

case "${1:-}" in
  list)
    resolve_workspace
    "$CLAUDE_LAUNCHER" list "$WORKSPACE_ROOT"
    ;;
  start)
    start_services
    ;;
  stop)
    stop_services
    ;;
  restart)
    # A stop failure must not prevent the start half of the restart.
    stop_services || echo "Continuing restart despite a stop failure." >&2
    start_services
    ;;
  update)
    update_services
    ;;
  status)
    # Report both sides even when the Claude session is down, but keep the
    # Claude exit status so callers can still test for "everything is up".
    claude_status=0
    "$CLAUDE_LAUNCHER" status || claude_status=$?
    echo "Codex Remote Control does not expose a status command."
    exit "$claude_status"
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
