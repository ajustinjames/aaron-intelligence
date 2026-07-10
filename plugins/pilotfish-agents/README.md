# pilotfish-agents (vendored)

Vendored copy of the six role subagents from [`Nanako0129/pilotfish`](https://github.com/Nanako0129/pilotfish) — a global multi-model orchestration layer for Claude Code. Vendored at commit [`a395b25`](https://github.com/Nanako0129/pilotfish/commit/a395b258af00049e92876cedd1f4f07c258319ff) (tracks upstream `VERSION` `1.1.1`). Upstream is MIT-licensed; see [`LICENSE`](./LICENSE).

Named `pilotfish-agents` rather than `pilotfish` deliberately: this is a vendored subset, not the upstream project, and a plugin literally named `pilotfish` in this marketplace could collide with an official `pilotfish` plugin/marketplace upstream might ship in the future.

## What this ships

- `agents/scout.md`, `agents/Explore.md` — read-only reconnaissance (`Read,Glob,Grep` only), pinned to `haiku`. `Explore.md` intentionally shadows Claude Code's built-in Explore agent to keep exploration cheap.
- `agents/mech-executor.md` — mechanical, fully-specified execution (`sonnet`).
- `agents/executor.md` — judgment-requiring implementation (`opus`).
- `agents/verifier.md` — adversarial fresh-context verification, `Write`/`Edit`/`NotebookEdit` disallowed (`opus`).
- `agents/security-executor.md` — security-sensitive implementation/analysis, routed to `opus` deliberately (frontier models' safety classifiers can refuse benign defensive-security work on cheaper tiers) (`opus`, high effort).

All four write-capable roles (mech-executor, executor, verifier, security-executor) carry `disallowedTools: Task, Agent` in their frontmatter — a local hardening on top of upstream `1.1.1`. Upstream's fix for nested-agent spawning was prompt text only (the "never spawn further subagents" line in the orchestration template), and it demonstrably doesn't hold: executors given large bulk tasks were observed fanning out to their own subagents anyway. Removing the spawn tools makes the restriction structural instead of advisory. scout/Explore were already covered by their `tools:` allowlists.
- `ORCHESTRATION.md` — the main-session delegation policy (when to hand work to which role). Delivered to the session by the `SessionStart` hook below; also the content that goes between `<!-- pilotfish:begin -->` / `<!-- pilotfish:end -->` markers if you additionally paste it into a global `CLAUDE.md`.
- `hooks/orchestrator-activate.js` — `SessionStart` hook. Injects `ORCHESTRATION.md` (markers stripped) as session context, so the delegation policy ships with the plugin instead of requiring a manual `CLAUDE.md` paste.
- `hooks/orchestrator-reminder.js` — `UserPromptSubmit` hook. Re-injects a short one-paragraph reminder every turn. This is the piece upstream lacks: the policy is otherwise passive context that decays across a long session under a strongly-imperative task prompt, so the main session drifts back into running work inline or over-tiering (reaching for `executor`/opus on mechanical `mech-executor`/sonnet work). Set `PILOTFISH_ORCHESTRATOR=off` in your environment to disable both hooks.

## What this can't ship (plugin limitation, not an oversight)

Claude Code plugins can install `agents/` **and hooks**, but they **cannot** write to `~/.claude/settings.json`. One upstream piece stays manual:

| Piece | Where it'd go | Why it matters |
|---|---|---|
| `fallbackModel: ["opus", "sonnet"]` in `settings.json` | Global settings | Resilience — falls back on overload/unavailability. Independent of your `model` default; does not change it. |

The delegation policy that upstream can only deliver via a manual `CLAUDE.md` paste is shipped here by the `SessionStart` hook, so that paste is now **optional** — see Install mode 1.

**We deliberately do not set `model: "best"`** the way the upstream runbook suggests — that's a separate, optional choice about your main-session default model, orthogonal to installing the agents. Set it yourself only if you want it.

## Install mode 1 — plugin (portable, any machine)

```
/plugin marketplace add ajustinjames/aaron-intelligence   # if not already added
/plugin install pilotfish-agents@aaron-intelligence
```

Then, manually, once per machine:

1. Add `"fallbackModel": ["opus", "sonnet"]` to `~/.claude/settings.json` (or skip if you don't want the fallback behavior).
2. Restart your Claude Code session.

The delegation policy now loads automatically via the plugin's `SessionStart`/`UserPromptSubmit` hooks — no `CLAUDE.md` paste required. If you *already* pasted `ORCHESTRATION.md` between the pilotfish markers in `~/.claude/CLAUDE.md` (e.g. from a global install), you can remove that block to avoid duplicating the policy at session start; the hook covers it. To disable the hooks entirely, set `PILOTFISH_ORCHESTRATOR=off`.

## Install mode 2 — upstream runbook (global, non-portable)

Follow [`install/AGENT-INSTALL.md`](https://raw.githubusercontent.com/Nanako0129/pilotfish/main/install/AGENT-INSTALL.md) in the upstream repo directly against `~/.claude/`. This is what the vendored copy here was produced from. Our one deviation from that runbook: we never set `model: "best"` — we leave the existing `model` value untouched and only add `fallbackModel`.

## Shadowing

If you use both modes on the same machine (global install *and* this plugin installed), Claude Code resolves agents by `name:` frontmatter, and a user-level file at `~/.claude/agents/<role>.md` shadows the plugin's copy of the same name. The plugin copy becomes dormant but harmless — its purpose is portability to machines that don't yet have the global install.

## Uninstall

- Plugin only: `/plugin uninstall pilotfish-agents@aaron-intelligence`.
- Global install: delete the six files from `~/.claude/agents/` (only if their content matches these templates — diff first if you customized any), remove the block from `<!-- pilotfish:begin -->` through `<!-- pilotfish:end -->` (inclusive) in `~/.claude/CLAUDE.md`, and drop `fallbackModel` from `settings.json` if you added it.

## Keeping this in sync with upstream

See [`UPGRADING.md`](./UPGRADING.md).
