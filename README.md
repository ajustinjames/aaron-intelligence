# aaron-intelligence

My random enhancement for AI tools.

This repo is set up as a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugin-marketplaces). It hosts a few small plugins of its own ([`caveman-lite`](./plugins/caveman-lite), [`pilotfish-agents`](./plugins/pilotfish-agents), [`cross-model-delegate`](./plugins/cross-model-delegate)) and is otherwise a curated jumping-off point for finding good Claude Code plugins, official and third-party.

## Project-scoped Remote Control

[`scripts/claude-remote-control.sh`](./scripts/claude-remote-control.sh) starts a named Claude Remote Control server from the workspace root, then recursively discovers Git repositories beneath it and starts another server from each repository root. The workspace-level session can clone or initialize repositories; project sessions load their own instructions and Git context. Each target allows up to three concurrent sessions, and newly added repositories are picked up automatically the next time the launcher starts.

```bash
./scripts/claude-remote-control.sh start /path/to/workspace
./scripts/claude-remote-control.sh status
./scripts/claude-remote-control.sh attach
./scripts/claude-remote-control.sh stop
```

Install a symlink to run it from anywhere:

```bash
mkdir -p ~/.local/bin
ln -s /path/to/aaron-intelligence/scripts/claude-remote-control.sh \
  ~/.local/bin/claude-remote-control

claude-remote-control start /path/to/workspace
```

If the workspace argument is omitted, the launcher uses `CLAUDE_RC_WORKSPACE_ROOT` and then the current directory as fallbacks.

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
