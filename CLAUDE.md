# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`aaron-intelligence` is a Claude Code **plugin marketplace** (`.claude-plugin/marketplace.json`). It hosts two plugins of its own, `caveman-lite` and `pilotfish-agents`, and its README doubles as a curated list of other marketplaces/plugins worth installing. There is no build system, package manager, or test suite — it's marketplace metadata plus a handful of Node hook scripts and vendored agent definitions, run directly by the Claude Code CLI (no `npm install` step).

## Repo structure

- `.claude-plugin/marketplace.json` — marketplace manifest; lists plugins this repo hosts (`caveman-lite`, `pilotfish-agents`) with a `source` path relative to repo root.
- `plugins/caveman-lite/` — one hosted plugin:
  - `.claude-plugin/plugin.json` — plugin manifest, wires `SessionStart` and `UserPromptSubmit` hooks to the scripts in `hooks/`.
  - `hooks/caveman-config.js` — shared config resolver (env var → `~/.config/caveman/config.json` → default `full`) and the symlink-safe flag-file read/write helpers (`safeWriteFlag`/`readFlag`) all other hook scripts import.
  - `hooks/caveman-activate.js` — `SessionStart` hook; writes the mode flag and emits the ruleset text (per intensity level) as hidden session context.
  - `hooks/caveman-mode-tracker.js` — `UserPromptSubmit` hook; reinforces the active mode each turn.
  - `hooks/caveman-set-mode.js` — invoked by the `/caveman-lite` command to deterministically switch/clear the mode flag.
  - `commands/caveman-lite.md` — the `/caveman-lite [off|lite|full|ultra|wenyan|wenyan-lite|wenyan-ultra]` slash command definition.
  - `caveman-lite.md` — zero-runtime, copy-pasteable prompt-only version of the same behavior, for contexts where even hooks are unwanted.
  - `README.md` — plugin-level docs (what's included/excluded, config resolution order, valid modes).
- `plugins/pilotfish-agents/` — the other hosted plugin, a vendored (point-in-time copy, not a live mirror) subset of [`Nanako0129/pilotfish`](https://github.com/Nanako0129/pilotfish); named `pilotfish-agents` (not `pilotfish`) to avoid colliding with upstream's own name in the marketplace/install namespace:
  - `.claude-plugin/plugin.json` — plugin manifest; wires `SessionStart` and `UserPromptSubmit` hooks (see `hooks/`) plus the `agents/` dir. No commands.
  - `agents/` — six role subagent definitions (`scout.md`, `Explore.md`, `mech-executor.md`, `executor.md`, `verifier.md`, `security-executor.md`) from upstream's `templates/agents/`, with one standing local hardening (issue #9): every role is a leaf agent — `scout`/`Explore` via their `tools:` allowlist, the other four via `disallowedTools: Task, Agent, Workflow` plus a leaf-agent paragraph in the body — so subagents can't recursively spawn subagents. Preserve this delta when syncing upstream (see `UPGRADING.md`).
  - `ORCHESTRATION.md` — copy of upstream's `templates/claude-md.orchestration.md`; the main-session delegation policy. Plugins can't inject content into a user's global `CLAUDE.md`, so upstream ships this to paste manually — but the `SessionStart` hook here reads this same file and injects it as session context, making that paste optional.
  - `hooks/orchestrator-activate.js` — `SessionStart` hook; reads `ORCHESTRATION.md`, strips the `<!-- pilotfish:* -->` markers, emits the policy as hidden session context. Local addition, not from upstream (upstream has no hooks).
  - `hooks/orchestrator-reminder.js` — `UserPromptSubmit` hook; re-injects a one-paragraph delegation reminder every turn so the policy doesn't decay under a strong task prompt (the fix for issue #6, "pilotfish failed to trigger"). Both hooks honor `PILOTFISH_ORCHESTRATOR=off`.
  - `VERSION` — upstream version this vendor tracks; bump alongside `UPGRADING.md`'s sync steps.
  - `UPGRADING.md` — how to pull upstream changes into the vendored copy and re-sync any active global (non-plugin) install.
  - `README.md` — what's shipped vs. what requires manual `settings.json`/`CLAUDE.md` steps, both install modes, uninstall.
- `README.md` — repo-level docs: how to add this marketplace and install its plugins, plus the curated table of other plugins/marketplaces.

## Architecture notes for `caveman-lite`

- **Flag file** at `$CLAUDE_CONFIG_DIR/.caveman-lite-active` (default `~/.claude/.caveman-lite-active`) is the single source of truth for the current mode across a session. It's written/read exclusively through the symlink-safe helpers in `caveman-config.js` — never touch it with plain `fs.writeFileSync`/`readFileSync` elsewhere; the safety logic (O_NOFOLLOW, atomic temp+rename, size cap, mode whitelist) is there specifically to resist a local attacker planting a symlink at that predictable path.
- **Mode resolution order**: `CAVEMAN_DEFAULT_MODE` env var → `defaultMode` in `~/.config/caveman/config.json` (or `$XDG_CONFIG_HOME/caveman/config.json`) → hardcoded default `full`. This mirrors the upstream (non-lite) `caveman` plugin's config scheme intentionally, so the two are drop-in compatible on config.
- **Valid modes**: `off, lite, full, ultra, wenyan-lite, wenyan/wenyan-full, wenyan-ultra` — the canonical list lives in `VALID_MODES` in `caveman-config.js`; other scripts import it rather than redefining it.
- **Deliberately excluded** from this plugin (present in upstream `caveman` but not here, to avoid namespace collisions with other plugins' agents/commands): no `cavecrew-*` agents, no `/caveman-commit`, `/caveman-review`, `/caveman-compress`, `/caveman-stats`, no skills. Only hooks plus the single `/caveman-lite` command are registered.

## Making changes

- Adding a new plugin to the marketplace: create `plugins/<name>/` with its own `.claude-plugin/plugin.json`, then add an entry to `plugins` in `.claude-plugin/marketplace.json` and a row to the "Plugins hosted here" table in `README.md`.
- Adding a new caveman-lite intensity level: extend `VALID_MODES` in `hooks/caveman-config.js`, add its ruleset text to `RULESET_BY_LEVEL` in `hooks/caveman-activate.js`, and update the mode list in `commands/caveman-lite.md`'s `argument-hint` and in `plugins/caveman-lite/README.md`.
- There are no automated tests; verify hook changes by running the scripts directly with `node hooks/<script>.js` and inspecting stdout, or by installing the plugin locally and starting a session.
