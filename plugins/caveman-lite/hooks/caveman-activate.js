#!/usr/bin/env node
// caveman-lite — Claude Code SessionStart activation hook
//
// Runs on every session start:
//   1. Writes flag file at $CLAUDE_CONFIG_DIR/.caveman-lite-active
//   2. Emits the caveman ruleset (filtered to the active intensity level) as
//      hidden SessionStart context
//
// Unlike the full caveman plugin, there is no skills/ dir to read the
// ruleset from — this plugin ships hooks only. The ruleset below is the
// single source of truth.

const path = require('path');
const os = require('os');
const { getDefaultMode, safeWriteFlag } = require('./caveman-config');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.caveman-lite-active');

const mode = getDefaultMode();

// "off" mode — skip activation entirely, don't write flag or emit rules
if (mode === 'off') {
  try { require('fs').unlinkSync(flagPath); } catch (e) {}
  process.stdout.write('OK');
  process.exit(0);
}

safeWriteFlag(flagPath, mode);

const modeLabel = mode === 'wenyan' ? 'wenyan-full' : mode;

const RULESET_BY_LEVEL = {
  lite: 'Drop articles (a/an/the) and filler (just/really/basically/actually/simply). Keep sentences whole otherwise. All technical substance stays.',
  full:
    'Respond terse like smart caveman. All technical substance stay. Only fluff die.\n\n' +
    '## Rules\n\n' +
    'Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries (sure/certainly/of course/happy to), hedging. ' +
    'Fragments OK. Short synonyms (big not extensive, fix not "implement a solution for"). Technical terms exact. Code blocks unchanged. Errors quoted exact.\n\n' +
    'Pattern: `[thing] [action] [reason]. [next step].`',
  ultra:
    'Max compression. Fragments, dropped subjects, no connective tissue where meaning survives. ' +
    'Technical terms, numbers, identifiers, and code stay exact — never compress inside them.',
  'wenyan-full':
    'Respond in the spirit of classical terse register: short declarative fragments, no filler, no hedging. ' +
    'All technical substance, identifiers, and code stay in plain modern English/code — only the connective prose compresses.',
};
RULESET_BY_LEVEL['wenyan-lite'] = RULESET_BY_LEVEL.lite;
RULESET_BY_LEVEL['wenyan-ultra'] = RULESET_BY_LEVEL.ultra;

const rules = RULESET_BY_LEVEL[modeLabel] || RULESET_BY_LEVEL.full;

let output =
  'CAVEMAN MODE ACTIVE — level: ' + modeLabel + '\n\n' +
  rules + '\n\n' +
  '## Persistence\n\n' +
  'ACTIVE EVERY RESPONSE. No revert after many turns. Still active if unsure. Off only: "stop caveman" / "normal mode".\n\n' +
  'Current level: **' + modeLabel + '**. Switch: `/caveman lite|full|ultra` (typed as plain text — caveman-lite registers no slash command).\n\n' +
  '## Auto-Clarity\n\n' +
  'Drop caveman for: security warnings, irreversible action confirmations, multi-step sequences where fragment order risks misread, user asks to clarify or repeats question. Resume caveman after clear part done.\n\n' +
  '## Boundaries\n\n' +
  'Code/commits/PRs: write normal. "stop caveman" or "normal mode": revert. Level persists until changed or session end.';

process.stdout.write(output);
