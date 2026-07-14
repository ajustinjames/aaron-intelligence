#!/usr/bin/env node
// aaron-intelligence — PreToolUse Bash guard
//
// Nudges Claude off using the shell as a substitute for its own file tools.
// Anthropic's Bash tool guidance is explicit: "Avoid using this tool to run
// cat, head, tail, sed, awk, or echo commands ... Instead, use the appropriate
// dedicated tool." When Claude reaches for those anyway (a real, documented
// failure mode — see anthropics/claude-code issues #21697, #31292), this hook
// DENIES the call with an instructive reason. A PreToolUse `deny` is soft: the
// command never runs, the reason is fed back, and Claude re-plans with
// Read/Edit/Write. Nothing is destroyed; nothing prompts the user.
//
// Design bias: PRECISION over recall. We only fire on commands that are clearly
// a stand-in for Read/Edit/Write. Anything that is genuine shell work — a pipe,
// `tail -f`, stdout-only echo, standalone awk/sed data-processing, grep/find —
// is left alone, because Read/Edit cannot do those and blocking them is pure
// friction. Better to miss a few substitutions than to wedge legitimate work.
//
// The hook is FAIL-OPEN: any parse/read error, unexpected shape, or oversized
// input exits 0 (allow). A guard that denies on its own bugs is worse than no
// guard. It only ever emits a `deny` when it is confident.
//
// Off switch: set AARON_INTELLIGENCE_GUARD=off to disable entirely.

'use strict';

// ---- fail-open helpers -----------------------------------------------------

// Allow the tool call and exit. PreToolUse treats a bare exit 0 with no JSON as
// "no decision; normal permission flow applies" — exactly what we want when we
// have nothing to say.
function allow() {
  process.exit(0);
}

// Deny the tool call using the modern PreToolUse JSON contract. The reason is
// surfaced back to Claude so it can retry with the right tool.
function deny(reason) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'deny',
        permissionDecisionReason: reason,
      },
    })
  );
  process.exit(0);
}

// Never let this hook throw out to the runtime — that would be a hard error on
// every Bash call. Any uncaught failure is treated as "allow".
process.on('uncaughtException', allow);

if ((process.env.AARON_INTELLIGENCE_GUARD || '').trim().toLowerCase() === 'off') {
  allow();
}

// ---- read hook input -------------------------------------------------------

// PreToolUse commands are tiny JSON blobs. Anything past this cap is not a
// well-formed hook payload we should be reasoning about — allow and move on.
const MAX_INPUT_BYTES = 262144; // 256 KiB

let raw = '';
try {
  const buf = require('fs').readFileSync(0); // fd 0 = stdin
  if (buf.length > MAX_INPUT_BYTES) allow();
  raw = buf.toString('utf8');
} catch (e) {
  allow();
}

let payload;
try {
  payload = JSON.parse(raw);
} catch (e) {
  allow();
}

if (!payload || typeof payload !== 'object') allow();
// Only guard Bash. The matcher already scopes this, but double-check so the
// hook is safe if wired more broadly.
if (payload.tool_name !== 'Bash') allow();

const command =
  payload.tool_input && typeof payload.tool_input.command === 'string'
    ? payload.tool_input.command
    : '';
if (!command.trim()) allow();

// ---- quote masking ---------------------------------------------------------
//
// Detecting shell operators (| > >>) and command names naively trips over
// string literals: `echo "a > b"` has no real redirect, `echo "a | b"` no real
// pipe. Build a MASKED copy where the *contents* of single/double-quoted spans
// are replaced with same-length filler, so operator/keyword detection sees only
// real shell syntax. The unmasked command is what we quote back to Claude.

function maskQuotes(s) {
  let out = '';
  let quote = null; // "'" or '"' when inside a quoted span
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (quote) {
      // Inside double quotes a backslash escapes the next char; single quotes
      // are literal (no escapes in POSIX sh).
      if (quote === '"' && c === '\\' && i + 1 < s.length) {
        out += 'xx';
        i++;
        continue;
      }
      if (c === quote) {
        quote = null;
        out += c;
      } else {
        out += 'x'; // mask the literal content
      }
    } else if (c === "'" || c === '"') {
      quote = c;
      out += c;
    } else {
      out += c;
    }
  }
  return out;
}

const masked = maskQuotes(command);

// Split into segments on top-level command separators (&& || ; and newlines),
// but NOT on `|` — a pipe stays inside its segment so we can tell whether a
// simple command participates in a pipeline. Indices align with `command`
// because masking preserves length.
function splitSegments(m, orig) {
  const segs = [];
  let start = 0;
  for (let i = 0; i < m.length; i++) {
    const two = m.slice(i, i + 2);
    if (two === '&&' || two === '||') {
      segs.push({ masked: m.slice(start, i), orig: orig.slice(start, i) });
      i++;
      start = i + 1;
    } else if (m[i] === ';' || m[i] === '\n') {
      segs.push({ masked: m.slice(start, i), orig: orig.slice(start, i) });
      start = i + 1;
    }
  }
  segs.push({ masked: m.slice(start), orig: orig.slice(start) });
  return segs;
}

// ---- detection rules -------------------------------------------------------

const READ_CMDS = ['cat', 'head', 'tail', 'less', 'more'];

// Return the first bare word (command name) of a segment, ignoring leading
// `sudo`/`command`/env-assignments and whitespace. Operates on masked text.
function leadingCmd(segMasked) {
  const words = segMasked.trim().split(/\s+/);
  let idx = 0;
  while (idx < words.length) {
    const w = words[idx];
    if (w === 'sudo' || w === 'command' || w === 'time' || w === 'nohup') {
      idx++;
      continue;
    }
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(w)) {
      // VAR=value prefix
      idx++;
      continue;
    }
    return { name: w.replace(/^.*\//, ''), rest: words.slice(idx + 1) };
  }
  return { name: '', rest: [] };
}

const findings = new Set();

for (const seg of splitSegments(masked, command)) {
  const m = seg.masked;
  if (!m.trim()) continue;

  const inPipeline = /\|/.test(m); // real pipe (quotes already masked out)
  const { name, rest } = leadingCmd(m);

  // Rule A — in-place stream edit. `sed -i`, `perl -i`, `perl -pi`. This is an
  // edit of a file on disk; it belongs to the Edit tool. Fires even inside a
  // pipeline (in-place editing has no business in one anyway).
  if (
    (name === 'sed' && /\s-[A-Za-z]*i\b|\s--in-place\b/.test(' ' + rest.join(' '))) ||
    (name === 'perl' && /\s-[A-Za-z]*i/.test(' ' + rest.join(' ')))
  ) {
    findings.add(
      '`' + name + ' -i` edits a file in place — use the Edit tool (or Read then Edit) instead.'
    );
    continue;
  }

  // Rule D — writing a file via redirect: `echo/printf/cat ... > file` or
  // `>> file`. Creating or appending file content is the Write/Edit tool's job.
  // Detect a real (unmasked) redirect operator in the segment. We scope the
  // writer to echo/printf/cat/tee to avoid flagging `program > logfile`, which
  // is capturing program output — legitimately a shell-only operation.
  if (
    /(^|[^0-9<>])>>?[^>]/.test(m) &&
    (name === 'echo' || name === 'printf' || name === 'cat' || name === 'tee')
  ) {
    findings.add(
      'Writing a file via `' +
        name +
        ' > file` — use the Write tool for new content, or Edit to change an existing file.'
    );
    continue;
  }

  // Rule C — reading a file: `cat/head/tail/less/more FILE` with no pipe. Skip
  // when piped (feeding a program is genuine shell work) and skip `tail -f/-F`
  // (a live follow, which Read cannot do). Only fire when there is a real file
  // argument, not a flag.
  if (!inPipeline && READ_CMDS.includes(name)) {
    if (name === 'tail' && rest.some((w) => /^-[A-Za-z]*[fF]/.test(w))) continue;
    const hasFileArg = rest.some((w) => w && !w.startsWith('-'));
    if (hasFileArg) {
      findings.add(
        '`' +
          name +
          ' <file>` reads a file — use the Read tool instead (it shows line numbers and handles ranges, images, and PDFs).'
      );
      continue;
    }
  }
}

if (findings.size === 0) allow();

const list = Array.from(findings)
  .map((f, i) => `  ${i + 1}. ${f}`)
  .join('\n');

deny(
  'This Bash command uses the shell where a dedicated Claude Code file tool is ' +
    'recommended:\n' +
    list +
    '\n\nRe-do it with the dedicated tool. If you genuinely need the shell here ' +
    '(a pipeline, streaming, or data processing Read/Edit cannot express), ' +
    'restructure the command so the file read/edit/write goes through Read/Edit/Write, ' +
    'or set AARON_INTELLIGENCE_GUARD=off to disable this guard for the session.'
);
