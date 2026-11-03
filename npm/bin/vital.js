#!/usr/bin/env node
'use strict';
// `vital status | apps | history`: runs the command line built into Vital.app.
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const { binaryPath, installedVersion, atLeast, FIRST_WITH_COMMAND_LINE } = require('../lib/install');

const candidates = [binaryPath(), binaryPath(`${process.env.HOME}/Applications`)];
const bin = candidates.find((p) => fs.existsSync(p));
if (!bin) {
  console.error('vital: Vital is not installed. Run "npx vital-mac install" first.');
  process.exit(1);
}
// Older releases have no command line and would open a second menu bar app instead.
const dir = bin.replace(/\/Vital\.app\/.*$/, '');
const have = installedVersion(dir);
if (!have || !atLeast(have, FIRST_WITH_COMMAND_LINE)) {
  console.error(`vital: Vital ${have || '?'} has no command line. Run "vital-mac install --force" to get ${FIRST_WITH_COMMAND_LINE} or newer.`);
  process.exit(1);
}
// argv0 "vital" is how the app knows it was started from a terminal.
const child = spawn(bin, process.argv.slice(2), { argv0: 'vital', stdio: 'inherit' });
child.on('exit', (code, signal) => process.exit(code ?? (signal ? 1 : 0)));
