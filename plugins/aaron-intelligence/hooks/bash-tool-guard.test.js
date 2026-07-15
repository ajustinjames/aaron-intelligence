'use strict';

// Dependency-free tests for the bash-tool-guard PreToolUse hook. Runs the hook
// as a child process with a synthetic PreToolUse payload on stdin and asserts
// on its stdout (deny JSON) / exit behavior. `node --test` only.

const { test } = require('node:test');
const assert = require('node:assert');
const { spawnSync } = require('node:child_process');
const path = require('node:path');

const HOOK = path.join(__dirname, 'bash-tool-guard.js');

// Run the hook with a Bash command (or a full payload) and return its parsed
// decision: { denied: bool, reason: string|null }.
function run(command, { toolName = 'Bash', env = {} } = {}) {
  const payload = JSON.stringify({
    tool_name: toolName,
    tool_input: { command },
  });
  const res = spawnSync('node', [HOOK], {
    input: payload,
    encoding: 'utf8',
    env: { ...process.env, ...env },
  });
  assert.strictEqual(res.status, 0, 'hook must always exit 0 (fail-open contract)');
  const out = res.stdout.trim();
  if (!out) return { denied: false, reason: null };
  const parsed = JSON.parse(out);
  const hso = parsed.hookSpecificOutput || {};
  return {
    denied: hso.permissionDecision === 'deny',
    reason: hso.permissionDecisionReason || null,
  };
}

// ---- should DENY (bash used as a file tool) --------------------------------

test('denies: cat of a file', () => {
  assert.ok(run('cat README.md').denied);
});

test('denies: head of a file', () => {
  assert.ok(run('head -n 20 src/index.js').denied);
});

test('denies: tail of a file (not -f)', () => {
  assert.ok(run('tail -50 server.log').denied);
});

test('denies: sed in-place edit', () => {
  const r = run("sed -i 's/foo/bar/g' config.yml");
  assert.ok(r.denied);
  assert.match(r.reason, /Edit tool/);
});

test('denies: perl in-place edit', () => {
  assert.ok(run("perl -pi -e 's/a/b/' file.txt").denied);
});

test('denies: echo redirect to file', () => {
  const r = run('echo "hello" > greeting.txt');
  assert.ok(r.denied);
  assert.match(r.reason, /Write tool/);
});

test('denies: printf append to file', () => {
  assert.ok(run('printf "line\\n" >> out.txt').denied);
});

test('denies: only the offending segment in a compound command', () => {
  assert.ok(run('npm run build && cat dist/index.html').denied);
});

// ---- should ALLOW (genuine shell work) -------------------------------------

test('allows: cat piped into a program', () => {
  assert.strictEqual(run('cat access.log | grep 500 | wc -l').denied, false);
});

test('allows: tail -f (live follow)', () => {
  assert.strictEqual(run('tail -f server.log').denied, false);
});

test('allows: echo to stdout (no redirect)', () => {
  assert.strictEqual(run('echo "build complete"').denied, false);
});

test('allows: redirect inside a quoted string is not a real redirect', () => {
  assert.strictEqual(run('echo "use a > b to compare"').denied, false);
});

test('allows: standalone awk data processing', () => {
  assert.strictEqual(run("awk '{sum+=$1} END {print sum}' nums.txt").denied, false);
});

test('allows: program output captured to a log file', () => {
  assert.strictEqual(run('npm test > test-results.txt').denied, false);
});

test('allows: grep (has Grep tool but commonly legit in pipelines)', () => {
  assert.strictEqual(run('grep -r TODO src/').denied, false);
});

test('allows: git and other ordinary commands', () => {
  assert.strictEqual(run('git status && npm ci').denied, false);
});

// ---- fail-open / config guarantees -----------------------------------------

test('allows: non-Bash tool payloads are ignored', () => {
  assert.strictEqual(run('cat file', { toolName: 'Read' }).denied, false);
});

test('allows: AARON_INTELLIGENCE_GUARD=off disables the guard', () => {
  assert.strictEqual(
    run('cat README.md', { env: { AARON_INTELLIGENCE_GUARD: 'off' } }).denied,
    false
  );
});

test('fail-open: malformed stdin exits 0 without denying', () => {
  const res = spawnSync('node', [HOOK], { input: 'not json', encoding: 'utf8' });
  assert.strictEqual(res.status, 0);
  assert.strictEqual(res.stdout.trim(), '');
});
