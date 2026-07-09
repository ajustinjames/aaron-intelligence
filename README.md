# aaron-intelligence

My random enhancement for AI tools.

This repo is set up as a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugin-marketplaces). It doesn't host any plugins of its own yet — instead it's a curated jumping-off point for finding good Claude Code plugins, official and third-party.

## Using this marketplace

Add this repo as a marketplace source:

```
/plugin marketplace add ajustinjames/aaron-intelligence
```

Then install any plugin it lists:

```
/plugin install <plugin-name>@aaron-intelligence
```

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
