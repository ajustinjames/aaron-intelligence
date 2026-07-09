# Upgrading the vendored copy

This plugin is a point-in-time vendor of [`Nanako0129/pilotfish`](https://github.com/Nanako0129/pilotfish), not a live mirror. Nothing pulls upstream changes automatically. To sync:

## 1. Check for a new version

```
curl -fsSL https://raw.githubusercontent.com/Nanako0129/pilotfish/main/VERSION
```

Compare against `plugins/pilotfish-agents/VERSION` in this repo. If they match, stop — you're current. If newer, read the changelog for what changed:

```
curl -fsSL https://raw.githubusercontent.com/Nanako0129/pilotfish/main/CHANGELOG.md
```

## 2. Diff and apply template changes

For each of the six agent files and the orchestration template, fetch upstream and diff against the vendored copy:

```
for f in scout Explore mech-executor executor verifier security-executor; do
  curl -fsSL "https://raw.githubusercontent.com/Nanako0129/pilotfish/main/templates/agents/$f.md" \
    | diff - "plugins/pilotfish-agents/agents/$f.md"
done
curl -fsSL "https://raw.githubusercontent.com/Nanako0129/pilotfish/main/templates/claude-md.orchestration.md" \
  | diff - "plugins/pilotfish-agents/ORCHESTRATION.md"
```

Apply upstream changes to the vendored files. If you've locally customized an agent (tuned a prompt, changed a `model`/`effort` field), reconcile by hand rather than blind-overwrite — same rule the upstream runbook itself follows for user customizations.

## 3. Bump versions

- `plugins/pilotfish-agents/VERSION` → new upstream version string. This file always tracks the vendored upstream version, nothing else.
- `plugins/pilotfish-agents/.claude-plugin/plugin.json` → bump `version`. This is the plugin's **own** release version and may be ahead of `VERSION`: local features that aren't from upstream (e.g. the `SessionStart`/`UserPromptSubmit` orchestrator hooks, added in plugin `1.2.0` while tracking upstream `1.1.1`) bump this independently. When syncing a new upstream, carry those local additions forward and bump the minor/patch as appropriate rather than snapping back to the upstream string.
- Update the commit SHA and version noted in `README.md`'s attribution line.

## 4. Re-sync the active global install (if you run one)

The global copies under `~/.claude/agents/` and the orchestration block in `~/.claude/CLAUDE.md` don't auto-update from the plugin. After updating the vendored copies here, mirror them:

```
for f in scout Explore mech-executor executor verifier security-executor; do
  cp "plugins/pilotfish-agents/agents/$f.md" ~/.claude/agents/$f.md
done
```

For `~/.claude/CLAUDE.md`, replace the content between `<!-- pilotfish:begin -->` and `<!-- pilotfish:end -->` (inclusive) with the new `plugins/pilotfish-agents/ORCHESTRATION.md` — this is idempotent, matching the upstream runbook's own upgrade behavior.

Restart your Claude Code session afterward.
