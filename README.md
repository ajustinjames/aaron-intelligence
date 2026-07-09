# aaron-intelligence

My random enhancement for AI tools.

This repo is set up as a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugin-marketplaces). It hosts one small plugin of its own ([`caveman-lite`](./plugins/caveman-lite)) and is otherwise a curated jumping-off point for finding good Claude Code plugins, official and third-party.

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
