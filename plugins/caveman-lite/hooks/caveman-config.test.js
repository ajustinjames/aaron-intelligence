#!/usr/bin/env node
// caveman-lite — tests for the symlink-safe flag helpers in caveman-config.js.
// Dependency-free; run with:  node --test caveman-config.test.js
//
// These exercise the REAL exported functions and the real flag-path handling.
// safeWriteFlag(flagPath, content) and readFlag(flagPath) both take the flag
// path as an explicit argument, so no env override is needed — each test points
// them at a file inside its own fresh temp dir.

const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { safeWriteFlag, readFlag } = require('./caveman-config');

// Fresh temp dir per test, auto-cleaned when the callback returns.
function withTempDir(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'caveman-test-'));
  try {
    return fn(dir);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

// Detect whether this platform lets us create symlinks (Windows often doesn't
// without elevation). If not, the two symlink tests note it and skip the
// symlink-specific assertion rather than failing spuriously.
function canSymlink(dir) {
  const target = path.join(dir, '.symcheck-target');
  const link = path.join(dir, '.symcheck-link');
  try {
    fs.writeFileSync(target, 'x');
    fs.symlinkSync(target, link);
    return true;
  } catch (e) {
    return false;
  } finally {
    try { fs.unlinkSync(link); } catch (e) {}
    try { fs.unlinkSync(target); } catch (e) {}
  }
}

test('readFlag returns a written valid mode and does not follow a symlink at the flag path', () => {
  withTempDir((dir) => {
    // Baseline: a normally-written valid flag reads back as that mode.
    const flagPath = path.join(dir, '.caveman-lite-active');
    safeWriteFlag(flagPath, 'ultra');
    assert.strictEqual(readFlag(flagPath), 'ultra');

    // Symlink case: plant a symlink at the flag path pointing to a sentinel
    // file whose content is itself a VALID mode ('lite'). If readFlag followed
    // the link it would return 'lite'; the symlink guard must make it null.
    const linkDir = fs.mkdtempSync(path.join(os.tmpdir(), 'caveman-link-'));
    try {
      const sentinel = path.join(linkDir, 'sentinel');
      fs.writeFileSync(sentinel, 'lite');
      const linkFlag = path.join(linkDir, '.caveman-lite-active');
      if (!canSymlink(linkDir)) {
        // eslint-disable-next-line no-console
        console.log('  (symlink unsupported on this platform — skipping symlink read assertion)');
        return;
      }
      fs.symlinkSync(sentinel, linkFlag);
      assert.strictEqual(
        readFlag(linkFlag),
        null,
        'readFlag must not read a valid mode through a symlinked flag path'
      );
    } finally {
      fs.rmSync(linkDir, { recursive: true, force: true });
    }
  });
});

test('readFlag rejects over-cap content and a non-whitelisted mode token', () => {
  withTempDir((dir) => {
    // Over the 64-byte cap: a regular file larger than MAX_FLAG_BYTES is
    // rejected on the size check before any bytes are read.
    const bigPath = path.join(dir, '.caveman-lite-active-big');
    fs.writeFileSync(bigPath, 'a'.repeat(100)); // 100 bytes > 64
    assert.strictEqual(readFlag(bigPath), null, 'over-cap flag must be rejected');

    // Under the cap but not a whitelisted mode token → rejected.
    const badPath = path.join(dir, '.caveman-lite-active-bad');
    fs.writeFileSync(badPath, 'not-a-real-mode');
    assert.strictEqual(readFlag(badPath), null, 'non-whitelisted token must be rejected');
  });
});

test('safeWriteFlag round-trips a valid mode', () => {
  withTempDir((dir) => {
    const flagPath = path.join(dir, '.caveman-lite-active');
    safeWriteFlag(flagPath, 'wenyan');
    assert.strictEqual(readFlag(flagPath), 'wenyan');
  });
});

test('safeWriteFlag refuses to write through a pre-planted symlink, leaving the target untouched', () => {
  withTempDir((dir) => {
    if (!canSymlink(dir)) {
      // eslint-disable-next-line no-console
      console.log('  (symlink unsupported on this platform — skipping symlink write assertion)');
      return;
    }
    // A target file the attacker wants clobbered.
    const targetDir = fs.mkdtempSync(path.join(os.tmpdir(), 'caveman-target-'));
    try {
      const target = path.join(targetDir, 'victim');
      fs.writeFileSync(target, 'SENTINEL');

      // Flag path is a symlink to the victim, planted before we write.
      const flagPath = path.join(dir, '.caveman-lite-active');
      fs.symlinkSync(target, flagPath);

      safeWriteFlag(flagPath, 'ultra');

      // The victim must be unchanged: the write was refused, not followed.
      assert.strictEqual(fs.readFileSync(target, 'utf8'), 'SENTINEL',
        'safeWriteFlag must not write through the symlink to the target');
    } finally {
      fs.rmSync(targetDir, { recursive: true, force: true });
    }
  });
});
