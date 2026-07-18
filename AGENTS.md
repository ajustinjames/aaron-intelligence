# AGENTS.md

This file provides guidance to coding agents working in this repository.

## What this repo is

`aaron-intelligence` is a Claude Code **plugin marketplace** (`.claude-plugin/marketplace.json`). It hosts four plugins of its own, `caveman-lite`, `pilotfish-agents`, `cross-model-delegate`, and `aaron-intelligence` (the marketplace and this hosted plugin deliberately share a name), and its README doubles as a curated list of other marketplaces/plugins worth installing. There is no build system or package manager; a small GitHub Actions CI (`.github/workflows/ci.yml`) syntax-checks hooks, validates manifests, and runs the dependency-free `node --test` suites — everything runs directly via the Claude Code CLI or `node`, no `npm install` step.

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
  - `agents/` — six role subagent definitions (`scout.md`, `Explore.md`, `mech-executor.md`, `executor.md`, `verifier.md`, `security-executor.md`) from upstream's `templates/agents/`, with one standing local hardening (issues #9, #14): every role is a leaf agent, enforced via a `tools:` allowlist (fails closed) plus a leaf-agent paragraph in the body — so subagents can't recursively spawn subagents. Preserve this delta when syncing upstream (see `UPGRADING.md`).
  - `ORCHESTRATION.md` — copy of upstream's `templates/claude-md.orchestration.md`; the main-session delegation policy. Plugins can't inject content into a user's global `CLAUDE.md`, so upstream ships this to paste manually — but the `SessionStart` hook here reads this same file and injects it as session context, making that paste optional.
  - `hooks/orchestrator-activate.js` — `SessionStart` hook; reads `ORCHESTRATION.md`, strips the `<!-- pilotfish:* -->` markers, emits the policy as hidden session context. Local addition, not from upstream (upstream has no hooks).
  - `hooks/orchestrator-reminder.js` — `UserPromptSubmit` hook; re-injects a one-paragraph delegation reminder every turn so the policy doesn't decay under a strong task prompt (the fix for issue #6, "pilotfish failed to trigger"). Both hooks honor `PILOTFISH_ORCHESTRATOR=off`.
  - `VERSION` — upstream version this vendor tracks; bump alongside `UPGRADING.md`'s sync steps.
  - `UPGRADING.md` — how to pull upstream changes into the vendored copy and re-sync any active global (non-plugin) install.
  - `README.md` — what's shipped vs. what requires manual `settings.json`/`CLAUDE.md` steps, both install modes, uninstall.
- `plugins/cross-model-delegate/` — a skill-only plugin (no hooks/agents/commands): `skills/cross-model-delegate/SKILL.md` defines when and how to shell out to OpenAI Codex (`codex`) or Google Antigravity CLI (`agy`) for work that can run on their separate subscriptions instead of Anthropic tokens. Referenced from `ORCHESTRATION.md`'s routing table; off by default unless `codex`/`agy` are on `PATH`, and honors `CROSS_MODEL_DELEGATE=off`.
- `plugins/aaron-intelligence/` — Aaron's personal-enhancement plugin: a **grab-bag of hooks/skills/commands tuned to how he works**, meant to grow over time (not single-purpose). Its `.claude-plugin/plugin.json` inlines a `PreToolUse` hook (matcher `Bash`).
  - `hooks/bash-tool-guard.js` — the first component. Soft-blocks Bash commands that stand in for the file tools (`cat`/`head`/`tail`/`less`/`more <file>` → Read; `sed -i`/`perl -i` → Edit; `echo`/`printf`/`cat`/`tee` `> file` → Write/Edit) by returning the modern PreToolUse `deny` JSON (`hookSpecificOutput.permissionDecision`), whose reason Claude re-plans around. **Precision-first, fail-open:** anything in a pipe, `tail -f`, stdout-only echo, standalone `awk`/`sed`/`grep`/`find`, and program-output redirects are intentionally allowed; any parse error or oversized/malformed input allows the command. Off via `AARON_INTELLIGENCE_GUARD=off`. Quotes are masked before operator detection so `>`/`|` inside string literals don't false-positive.
  - `hooks/bash-tool-guard.test.js` — `node --test` suite (run in CI); assert deny/allow by spawning the hook with synthetic PreToolUse payloads. When adding a new component to this plugin, give it its own section in the plugin README's Components table and, if it has logic, its own `*.test.js`.
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
