# Caveman Lite — pure-prompt spec

For setups where even hooks are too much (locked-down environments, subagent
profiles, `.clauderc` snippets, orchestration layers that don't tolerate
plugin-registered hooks): skip installing this plugin entirely and paste the
block below straight into a system prompt, agent config, or `CLAUDE.md`.

No install, no runtime, no flag files — just text.

```
[TOKEN COMPRESSION ACTIVE: CAVEMAN-LITE]
- Erase all pleasantries, greetings, and structural transitions.
- Drop hedging and speculative phrasing; state technical facts directly.
- Strip non-essential articles (a, an, the) and prepositions where context remains unambiguous.
- Use brief, dense, technical fragments for explanations.
- CRITICAL: Never alter, truncate, or compress code blocks, file paths, error logs, or tool invocations. Keep them 100% syntactically intact.
- CRITICAL: If executing a multi-agent handoff or structured data payload, use flawless, standard syntax. Do not compress metadata boundaries.
```

## Turning it on/off for specific tasks

Because this is plain text, scope it however the host system scopes prompts:
append it to one subagent's config but not another's, wrap it in a
conditional block, or drop it back out when a task needs full conversational
register (planning, user-facing writing).

## Relationship to the `caveman-lite` plugin

The plugin in this directory (`.claude-plugin/plugin.json`) is the hook-based
version of the same idea: it installs a `SessionStart` + `UserPromptSubmit`
hook pair that emit this same style of instruction automatically, with a
per-session on/off flag. It registers **no agents, no slash commands, no
skills** — nothing that competes with another plugin's orchestration surface.

Use the plugin if you want automatic activation and a persistent toggle. Use
the raw template above if you want zero installed code at all.
