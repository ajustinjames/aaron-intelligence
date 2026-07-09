#!/usr/bin/env node
// pilotfish-agents — SessionStart hook
//
// Injects the orchestration delegation policy (ORCHESTRATION.md, with its
// begin/end markers stripped) as hidden session context on every session
// start. This is what makes the plugin self-contained: upstream pilotfish
// requires pasting the same policy into ~/.claude/CLAUDE.md by hand because
// plugins can't write that file — but a plugin CAN ship a hook, and a hook
// can deliver the policy as context. So the manual CLAUDE.md paste becomes
// optional (see README).
//
// Fires only in the main session — subagent role invocations are Task-tool
// calls, not session starts, so the policy never reaches a role agent. That
// matches the policy's own "main-session-only" scope.
//
// Off switch: set PILOTFISH_ORCHESTRATOR=off to suppress both this hook and
// the per-turn reminder (orchestrator-reminder.js).

const fs = require('fs');
const path = require('path');

if ((process.env.PILOTFISH_ORCHESTRATOR || '').trim().toLowerCase() === 'off') {
  process.stdout.write('OK');
  process.exit(0);
}

const pluginRoot = process.env.CLAUDE_PLUGIN_ROOT || path.join(__dirname, '..');
const policyPath = path.join(pluginRoot, 'ORCHESTRATION.md');

try {
  const raw = fs.readFileSync(policyPath, 'utf8');
  // Strip the <!-- pilotfish:begin --> / <!-- pilotfish:end --> / version
  // marker comments — they're for CLAUDE.md block management, not context.
  const policy = raw
    .replace(/<!--\s*pilotfish:(begin|end)\s*-->/g, '')
    .replace(/<!--\s*pilotfish v[^>]*-->/g, '')
    .trim();

  process.stdout.write(
    'PILOTFISH ORCHESTRATOR MODE ACTIVE — you are the main session.\n\n' +
    policy + '\n\n' +
    'This policy is reinforced every turn. It is not passive prose you may ' +
    'let decay under a strongly-worded task: default to delegating execution, ' +
    'and pick the cheapest role that can plausibly succeed before reaching for ' +
    'a pricier one.'
  );
} catch (e) {
  // If ORCHESTRATION.md is unreadable, fail silent rather than break session start.
  process.stdout.write('OK');
}
