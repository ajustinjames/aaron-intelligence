#!/usr/bin/env bash

set -euo pipefail

TMUX_SESSION="${CLAUDE_RC_TMUX_SESSION:-claude-rc}"
WORKSPACE_ROOT="${2:-${CLAUDE_RC_WORKSPACE_ROOT:-$PWD}}"
CAPACITY="${CLAUDE_RC_CAPACITY:-3}"
# Claude pre-creates a session in the server's directory unless told not to.
# One server per repository plus a pre-created session each is a large amount
# of resident memory for sessions nobody asked for, so default to off.
PRECREATE_SESSIONS="${CLAUDE_RC_PRECREATE_SESSIONS:-off}"
MAX_PROJECTS="${CLAUDE_RC_MAX_PROJECTS:-8}"
MAX_DEPTH="${CLAUDE_RC_MAX_DEPTH:-3}"
SETTLE_SECONDS="${CLAUDE_RC_SETTLE_SECONDS:-3}"

# Directories never worth scanning for project roots. Keeps discovery off
# caches and vendored dependency trees that can contain their own .git dirs.
PRUNE_DIRS=(
  node_modules .cache .npm .cargo .rustup .rvm .pyenv .nvm
  .venv venv __pycache__ .terraform .gradle .m2 Library
)

PROJECTS=()
declare -a EXPECTED_WINDOWS=()
# 'error' aborts when the repository count exceeds the cap; 'warn' reports and
# continues, so 'list' can always show what discovery found.
CAP_MODE=error

usage() {
  cat <<'EOF'
Usage: claude-remote-control <command> [workspace-root]

Commands:
  list     Show the targets start would launch, without launching them
  start    Start one workspace server plus one per discovered repository
  stop     Stop all Remote Control servers managed by this script
  restart  Stop and start the servers beneath workspace-root
  update   Stop servers, update Claude Code, then start beneath workspace-root
  status   Show the managed tmux windows
  attach   Attach to the managed tmux session

Environment:
  CLAUDE_RC_WORKSPACE_ROOT  Fallback when workspace-root is omitted
  CLAUDE_RC_TMUX_SESSION    tmux session name (default: claude-rc)
  CLAUDE_RC_CAPACITY        Concurrent sessions per server (default: 3)
  CLAUDE_RC_MAX_PROJECTS    Refuse to start beyond this many repos (default: 8)
  CLAUDE_RC_MAX_DEPTH       Repository search depth below root (default: 3)
  CLAUDE_RC_SETTLE_SECONDS  Startup verification delay (default: 3)
  CLAUDE_RC_PRECREATE_SESSIONS  'on' to pre-create a session per server
                            (default: off, i.e. --no-create-session-in-dir)

workspace-root defaults to the current directory.

A Remote Control server is bound to the directory it was started from: sessions
either share that directory or get worktrees of that repository, and a remote
client cannot pick a different one. That is why reaching several repositories
from a phone needs several servers.

Each server is a separate long-lived Claude process holding roughly 400 MB
resident, and each can spawn up to CLAUDE_RC_CAPACITY concurrent sessions on
top of that. Run 'list' first and size the host accordingly: a workspace with
many repositories can exhaust memory on a small VM or container, which looks
like the whole machine hanging. CLAUDE_RC_MAX_PROJECTS is the guard rail.

Every target directory must already be trusted, because these servers run in
detached tmux windows where nobody can answer the workspace trust prompt. Run
'claude' once in each directory first. Claude never saves trust for a home
directory, so a home directory cannot be used as a server target at all.

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

require_positive_int() {
  local name="$1" value="$2"

  if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 )); then
    echo "$name must be a positive integer, got: $value" >&2
    exit 1
  fi
}

# Refuse to kill the session we are running inside; that would take down the
# caller's own terminal along with the servers.
assert_not_inside_managed_session() {
  [[ -n "${TMUX:-}" ]] || return 0

  local current
  current="$(tmux display-message -p '#{session_name}' 2>/dev/null || true)"

  if [[ "$current" == "$TMUX_SESSION" ]]; then
    echo "Refusing to run from inside the managed tmux session: $TMUX_SESSION" >&2
    echo "Detach first (prefix + d), then rerun from outside the session." >&2
    exit 1
  fi
}

discover_projects() {
  local -a prune_expr=()
  local dir

  for dir in "${PRUNE_DIRS[@]}"; do
    prune_expr+=(-name "$dir" -o)
  done
  unset 'prune_expr[${#prune_expr[@]}-1]'

  # A repository root is any directory holding a .git entry. Test -e rather
  # than -d so linked worktrees and submodules, where .git is a file, count.
  # Matching prunes, so nested repositories inside a repository are skipped.
  mapfile -d '' PROJECTS < <(
    find "$WORKSPACE_ROOT" -mindepth 1 -maxdepth "$MAX_DEPTH" \
      \( -type d \( "${prune_expr[@]}" \) -prune \) -o \
      \( -type d -exec test -e '{}/.git' ';' -print0 -prune \) \
      2>/dev/null | sort -z
  )

  if (( ${#PROJECTS[@]} > MAX_PROJECTS )); then
    echo "Found ${#PROJECTS[@]} repositories under $WORKSPACE_ROOT, which is more" >&2
    echo "than CLAUDE_RC_MAX_PROJECTS=$MAX_PROJECTS. Starting one Claude server per" >&2
    echo "repository would need roughly $(( (${#PROJECTS[@]} + 1) * 400 )) MB before any" >&2
    echo "session runs, and can hang a small host. Options:" >&2
    echo "  - point workspace-root at a narrower directory" >&2
    echo "  - lower CLAUDE_RC_MAX_DEPTH (currently $MAX_DEPTH)" >&2
    echo "  - raise CLAUDE_RC_MAX_PROJECTS if the host really has the memory" >&2

    if [[ "$CAP_MODE" == error ]]; then
      echo "Run '$0 list ${WORKSPACE_ROOT@Q}' to see what was found." >&2
      exit 1
    fi

    echo "Listing anyway; 'start' would refuse until the count fits." >&2
    echo >&2
  fi

  if (( ${#PROJECTS[@]} == 0 )); then
    echo "No Git repositories found under: $WORKSPACE_ROOT" >&2
    echo "Starting the workspace server only; use it to clone or init a repo." >&2
  fi
}

validate_configuration() {
  require_command claude
  require_command find
  require_command sort
  require_command tmux

  require_positive_int CLAUDE_RC_CAPACITY "$CAPACITY"
  require_positive_int CLAUDE_RC_MAX_PROJECTS "$MAX_PROJECTS"
  require_positive_int CLAUDE_RC_MAX_DEPTH "$MAX_DEPTH"

  if [[ ! "$SETTLE_SECONDS" =~ ^[0-9]+$ ]]; then
    echo "CLAUDE_RC_SETTLE_SECONDS must be a non-negative integer, got: $SETTLE_SECONDS" >&2
    exit 1
  fi

  if [[ ! -d "$WORKSPACE_ROOT" ]]; then
    echo "Workspace directory not found: $WORKSPACE_ROOT" >&2
    exit 1
  fi

  WORKSPACE_ROOT="$(cd -- "$WORKSPACE_ROOT" && pwd)"

  # Claude refuses to persist workspace trust for a home directory, so a
  # server started there can never get past the trust prompt, and there is no
  # terminal attached to answer it anyway.
  if [[ "$WORKSPACE_ROOT" == "$HOME" ]]; then
    echo "Refusing to use a home directory as the workspace root: $WORKSPACE_ROOT" >&2
    echo "Claude never saves workspace trust for a home directory, so the" >&2
    echo "workspace server would block on an unanswerable trust prompt." >&2
    echo "Point workspace-root at a project directory such as $HOME/code." >&2
    exit 1
  fi

  discover_projects
}

target_name_for() {
  local project_dir="$1"

  printf '%s' "${project_dir#"$WORKSPACE_ROOT"/}"
}

window_name_for() {
  local target_name="$1"

  printf '%s' "${target_name//\//-}"
}

server_command() {
  local target_dir="$1"
  local target_name="$2"
  local precreate_flag='--no-create-session-in-dir'
  local command

  if [[ "$PRECREATE_SESSIONS" != "off" ]]; then
    precreate_flag='--create-session-in-dir'
  fi

  printf -v command \
    'cd %q && exec claude remote-control --name %q --spawn same-dir --capacity %d %s' \
    "$target_dir" "$target_name" "$CAPACITY" "$precreate_flag"
  printf '%s' "$command"
}

add_server_window() {
  local target_dir="$1"
  local target_name="$2"
  local window_name
  window_name="$(window_name_for "$target_name")"

  if ! tmux has-session -t "=$TMUX_SESSION" 2>/dev/null; then
    tmux new-session -d -s "$TMUX_SESSION" -n "$window_name" \
      "$(server_command "$target_dir" "$target_name")"
  else
    tmux new-window -d -t "=$TMUX_SESSION" -n "$window_name" \
      "$(server_command "$target_dir" "$target_name")"
  fi

  EXPECTED_WINDOWS+=("$window_name")
}

# A server that fails on startup takes its tmux window with it, so presence of
# the window after a settle delay is the signal that it actually came up.
verify_servers() {
  local -a live=() missing=()
  local window_name

  if (( SETTLE_SECONDS > 0 )); then
    sleep "$SETTLE_SECONDS"
  fi

  if tmux has-session -t "=$TMUX_SESSION" 2>/dev/null; then
    mapfile -t live < <(tmux list-windows -t "=$TMUX_SESSION" -F '#{window_name}')
  fi

  for window_name in "${EXPECTED_WINDOWS[@]}"; do
    if ! printf '%s\n' "${live[@]}" | grep -Fxq -- "$window_name"; then
      missing+=("$window_name")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    echo "Failed to start ${#missing[@]} of ${#EXPECTED_WINDOWS[@]} Claude Remote Control servers:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    echo "Run 'claude remote-control' by hand in one of those directories to see why." >&2
    if (( ${#missing[@]} == ${#EXPECTED_WINDOWS[@]} )); then
      return 1
    fi
    echo "Started $(( ${#EXPECTED_WINDOWS[@]} - ${#missing[@]} )) of ${#EXPECTED_WINDOWS[@]} servers:" >&2
    status_servers
    return 1
  fi

  echo "Started ${#EXPECTED_WINDOWS[@]} Claude Remote Control servers:"
  status_servers
}

start_servers() {
  validate_configuration

  if tmux has-session -t "=$TMUX_SESSION" 2>/dev/null; then
    echo "Remote Control tmux session already exists: $TMUX_SESSION" >&2
    echo "Run '$0 status' or '$0 restart'." >&2
    exit 1
  fi

  add_server_window "$WORKSPACE_ROOT" "workspace"

  local project_dir
  local project_name
  for project_dir in "${PROJECTS[@]}"; do
    project_name="$(target_name_for "$project_dir")"
    add_server_window "$project_dir" "$project_name"
  done

  verify_servers
}

list_targets() {
  CAP_MODE=warn
  validate_configuration

  echo "Workspace root: $WORKSPACE_ROOT"
  echo "tmux session:   $TMUX_SESSION"
  echo "Capacity:       $CAPACITY concurrent sessions per server"
  echo
  printf 'Targets (%d servers):\n' "$(( ${#PROJECTS[@]} + 1 ))"
  printf '  %-28s %s\n' "workspace" "$WORKSPACE_ROOT"

  local project_dir
  for project_dir in "${PROJECTS[@]}"; do
    printf '  %-28s %s\n' "$(target_name_for "$project_dir")" "$project_dir"
  done

  echo
  printf 'Estimated resident memory before any session runs: ~%d MB\n' \
    "$(( (${#PROJECTS[@]} + 1) * 400 ))"
}

stop_servers() {
  require_command tmux
  assert_not_inside_managed_session

  if ! tmux has-session -t "=$TMUX_SESSION" 2>/dev/null; then
    echo "Remote Control tmux session is not running: $TMUX_SESSION"
    return 0
  fi

  tmux kill-session -t "=$TMUX_SESSION"
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

  if ! tmux has-session -t "=$TMUX_SESSION" 2>/dev/null; then
    echo "Remote Control tmux session is not running: $TMUX_SESSION"
    return 1
  fi

  # A crashed server leaves no window behind, so this lists what is actually
  # alive. Compare against 'list' output to spot a target that died.
  tmux list-windows -t "=$TMUX_SESSION" \
    -F '#{window_name}: #{pane_current_command} (pid #{pane_pid})'
}

attach_servers() {
  require_command tmux

  if ! tmux has-session -t "=$TMUX_SESSION" 2>/dev/null; then
    echo "Remote Control tmux session is not running: $TMUX_SESSION" >&2
    exit 1
  fi

  exec tmux attach-session -t "=$TMUX_SESSION"
}

case "${1:-}" in
  list)
    list_targets
    ;;
  start)
    start_servers
    ;;
  stop)
    stop_servers
    ;;
  restart)
    # stop_servers must not abort the restart when nothing was running.
    stop_servers || true
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
