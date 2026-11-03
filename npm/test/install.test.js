'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { parseChecksums, sha256, appPath, binaryPath, atLeast } = require('../lib/install');

test('parses shasum output, including binary-mode stars', () => {
  const a = 'a'.repeat(64), b = 'b'.repeat(64);
  const m = parseChecksums(`${a}  Vital-0.1.5.zip\n${b} *Vital.dmg\nnot a checksum line\n`);
  assert.strictEqual(m.get('Vital-0.1.5.zip'), a);
  assert.strictEqual(m.get('Vital.dmg'), b);
  assert.strictEqual(m.size, 2);
});

test('hashes file contents', () => {
  const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'vm-')), 'x');
  fs.writeFileSync(f, 'abc');
  assert.strictEqual(sha256(f), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
});

test('paths point at the app bundle binary', () => {
  assert.strictEqual(appPath('/Applications'), '/Applications/Vital.app');
  assert.strictEqual(binaryPath('/x'), '/x/Vital.app/Contents/MacOS/Vital');
});

test('compares versions numerically, not as text', () => {
  assert.ok(atLeast('0.1.5', '0.1.5') && atLeast('0.1.10', '0.1.5') && atLeast('1.0.0', '0.9.9'));
  assert.ok(!atLeast('0.1.4', '0.1.5') && !atLeast('0.0.9', '0.1.0'));
});
