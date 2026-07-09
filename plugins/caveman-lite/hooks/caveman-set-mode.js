#!/usr/bin/env node
// caveman-lite — deterministic mode switch, invoked by the /caveman-lite command.
// Writes (or clears) the same flag file the hooks read, so this is the
// canonical way to change level — no reliance on regex-matching raw prompt text.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDefaultMode, safeWriteFlag, VALID_MODES } = require('./caveman-config');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.caveman-lite-active');

const arg = (process.argv[2] || '').trim().toLowerCase();

let mode;
if (!arg) {
  mode = getDefaultMode();
} else if (arg === 'off' || arg === 'stop' || arg === 'disable') {
  mode = 'off';
} else if (arg === 'wenyan-full') {
  mode = 'wenyan';
} else if (VALID_MODES.includes(arg)) {
  mode = arg;
} else {
  process.stdout.write(
    `Unknown caveman level "${arg}". Valid: ${VALID_MODES.join(', ')}.`
  );
  process.exit(0);
}

if (mode === 'off') {
  try { fs.unlinkSync(flagPath); } catch (e) {}
  process.stdout.write('Caveman mode off.');
} else {
  safeWriteFlag(flagPath, mode);
  const label = mode === 'wenyan' ? 'wenyan-full' : mode;
  process.stdout.write(`Caveman mode set to: ${label}`);
}
