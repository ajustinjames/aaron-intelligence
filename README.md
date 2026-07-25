# aaron-intelligence

My random enhancement for AI tools.

This repo is set up as a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugin-marketplaces). It hosts a few small plugins of its own ([`caveman-lite`](./plugins/caveman-lite), [`pilotfish-agents`](./plugins/pilotfish-agents), [`cross-model-delegate`](./plugins/cross-model-delegate)) and is otherwise a curated jumping-off point for finding good Claude Code plugins, official and third-party.

## Project-scoped Remote Control

[`scripts/claude-remote-control.sh`](./scripts/claude-remote-control.sh) starts a named Claude Remote Control server from the workspace root, then recursively discovers Git repositories beneath it and starts another server from each repository root. The workspace-level session can clone or initialize repositories; project sessions load their own instructions and Git context. Each target allows up to three concurrent sessions, and newly added repositories are picked up automatically the next time the launcher starts.

**Why one server per repository:** a Remote Control server is bound to the directory it was started from. Sessions either share that directory (`--spawn same-dir`) or get worktrees of that repository (`--spawn worktree`), and a remote client cannot pick a different one. Reaching several repositories from a phone therefore needs several servers. This is unlike Codex, whose single app-server is host-scoped and lets the client choose among projects.

> **Size the host first.** Each server is a separate long-lived Claude process holding roughly 400 MB resident, before any session runs. A workspace with a dozen repositories wants several gigabytes just to idle, and exhausting memory on a small VM or LXC container presents as the whole machine hanging rather than as a failed command. Run `list` before your first `start`:
>
> ```bash
> ./scripts/claude-remote-control.sh list /path/to/workspace
> ```
>
> `list` prints every target it would launch and the estimated memory. `start` refuses to run past `CLAUDE_RC_MAX_PROJECTS` (default 8).

> **Trust each directory first.** These servers run in detached tmux windows, where nothing can answer the workspace trust prompt, so run `claude` once in each target directory beforehand. Claude never persists trust for a home directory, so the launcher rejects a home directory as the workspace root outright.

> **Agent execution:** Run all Remote Control lifecycle commands on the host (outside an isolated agent sandbox). A sandbox may have a separate process or tmux namespace, causing `status` or `stop` to report that a host service is not running when it is. Agents should request host/escalated execution for these scripts when their environment is sandboxed.

```bash
./scripts/claude-remote-control.sh list /path/to/workspace
./scripts/claude-remote-control.sh start /path/to/workspace
./scripts/claude-remote-control.sh status
./scripts/claude-remote-control.sh attach
./scripts/claude-remote-control.sh update /path/to/workspace
./scripts/claude-remote-control.sh stop
```

Tunable through the environment:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CLAUDE_RC_WORKSPACE_ROOT` | `$PWD` | Fallback when the argument is omitted |
| `CLAUDE_RC_TMUX_SESSION` | `claude-rc` | tmux session name |
| `CLAUDE_RC_CAPACITY` | `3` | Concurrent sessions per server (Claude's own default is 32) |
| `CLAUDE_RC_MAX_PROJECTS` | `8` | `start` refuses beyond this many repositories |
| `CLAUDE_RC_MAX_DEPTH` | `3` | Repository search depth below the root |
| `CLAUDE_RC_SETTLE_SECONDS` | `3` | Delay before verifying servers came up |
| `CLAUDE_RC_PRECREATE_SESSIONS` | `off` | `on` restores Claude's default of pre-creating a session per server |

`status` lists only servers that are actually alive; a crashed server leaves no tmux window behind, so compare against `list` to spot one that died. `start` verifies each server survived startup and exits non-zero, naming the targets that failed, rather than reporting success unconditionally.

Install it on your user `PATH` to run it from anywhere:

```bash
mkdir -p ~/.local/bin
install -m 755 scripts/claude-remote-control.sh \
  ~/.local/bin/claude-remote-control

claude-remote-control start /path/to/workspace
```

Rerun the `install` command after updating the checkout. During development, you can symlink the script instead so changes take effect immediately. If the workspace argument is omitted, the launcher uses `CLAUDE_RC_WORKSPACE_ROOT` and then the current directory as fallbacks.

`remote-control.sh` calls its two sibling launchers, so install or symlink the whole `scripts/` directory together rather than that one file; it resolves symlinks to find its siblings and reports clearly if they are missing.

Run Codex Remote Control independently with the matching launcher:

```bash
./scripts/codex-remote-control.sh start /path/to/workspace
./scripts/codex-remote-control.sh pair
./scripts/codex-remote-control.sh update /path/to/workspace
./scripts/codex-remote-control.sh stop
```

Codex runs one app-server daemon from the supplied workspace. If the workspace argument is omitted, the launcher uses `CODEX_RC_WORKSPACE_ROOT` and then the current directory as fallbacks. Codex Remote Control does not expose a status command.

To manage Claude and Codex Remote Control together, run the combined launcher directly from this checkout:

```bash
./scripts/remote-control.sh list /path/to/workspace
./scripts/remote-control.sh start /path/to/workspace
./scripts/remote-control.sh status
./scripts/remote-control.sh pair
./scripts/remote-control.sh update /path/to/workspace
./scripts/remote-control.sh stop
```

Claude still receives one server per discovered repository. Codex runs its single app-server daemon with the supplied workspace as its working directory.

`stop` always attempts both services and reports a failure only after both have run, so an already-stopped service never blocks the other from stopping. `restart` and `update` likewise continue through a stop failure instead of aborting before they start anything. Stopping a service that was not running is not an error.

## Using this marketplace

Add this repo as a marketplace source:

```
/plugin marketplace add ajustinjames/aaron-intelligence
```

Then install any plugin it lists:

```
/plugin install <plugin-name>@aaron-intelligence
```

## Plugins hosted here

| Plugin | Description | Install |
|---|---|---|
| `caveman-lite` | Ultra-compressed communication mode, hooks only — no agents or slash commands, so it won't collide with another plugin's orchestration surface. Also ships a zero-runtime pure-prompt template for setups where even hooks are too much. | `/plugin install caveman-lite@aaron-intelligence` |
| `pilotfish-agents` | Vendored copy of [Nanako0129/pilotfish](https://github.com/Nanako0129/pilotfish)'s six role subagents (scout, Explore, mech-executor, executor, verifier, security-executor) for portable multi-model orchestration. Named distinctly from upstream's `pilotfish` to avoid marketplace collisions. Requires a couple of manual `settings.json`/`CLAUDE.md` steps — see [plugin README](./plugins/pilotfish-agents/README.md). | `/plugin install pilotfish-agents@aaron-intelligence` |
| `cross-model-delegate` | Skill that routes suitable work (second-opinion diagnosis, cross-model review, web research, bulk repo-wide refactors) to OpenAI Codex (`codex`) and Google Antigravity CLI (`agy`, Gemini) — separate subscription pools, zero Anthropic tokens. Requires `codex`/`agy` installed and authenticated; no-ops otherwise. | `/plugin install cross-model-delegate@aaron-intelligence` |
| `aaron-intelligence` | Aaron's personal Claude Code enhancements — a growing bundle of hooks, skills, and commands tuned to how he works. **First component:** a PreToolUse Bash guard that soft-blocks using the shell (`cat`/`head`/`tail`, `sed -i`, `echo > file`) as a stand-in for the Read/Edit/Write tools and tells Claude which tool to use — a `deny` that Claude re-plans around, nothing destructive. Precision-first: pipelines, `tail -f`, `awk`/`grep`, and program-output redirects are left alone. Off via `AARON_INTELLIGENCE_GUARD=off`. See [plugin README](./plugins/aaron-intelligence/README.md). | `/plugin install aaron-intelligence@aaron-intelligence` |

## Curated plugins

### Official Anthropic plugins

These live in the [`anthropics/claude-plugins-official`](https://github.com/anthropics/claude-plugins-official) marketplace. Add it once, then install any of them:

```
/plugin marketplace add anthropics/claude-plugins-official
```

| Plugin | Description | Install |
|---|---|---|
| `claude-md-management` | Audit and maintain `CLAUDE.md` files — check quality, capture session learnings, keep project memory current. | `/plugin install claude-md-management@claude-plugins-official` |
| `context7` | Upstash Context7 MCP server for up-to-date, version-specific library docs and code examples pulled straight from source repos. | `/plugin install context7@claude-plugins-official` |
| `frontend-design` | Guidance and tooling for distinctive, production-grade frontend UI — avoids generic AI-generated aesthetics. | `/plugin install frontend-design@claude-plugins-official` |
| `security-guidance` | Security review for Claude-generated code — pattern-based edit warnings, LLM diff review on stop, and an agentic commit reviewer for injection, XSS, SSRF, secrets, and more. | `/plugin install security-guidance@claude-plugins-official` |

### Third-party

| Plugin | Description | Install |
|---|---|---|
| `codex` | Delegate tasks to OpenAI Codex from Claude Code, or have Codex review your code. From [`openai/codex-plugin-cc`](https://github.com/openai/codex-plugin-cc). | `/plugin marketplace add openai/codex-plugin-cc` then `/plugin install codex@openai-codex` |
