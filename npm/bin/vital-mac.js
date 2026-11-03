#!/usr/bin/env node
'use strict';
const { install, uninstall } = require('../lib/install');

const USAGE = `vital-mac: install and manage Vital (https://github.com/soumyyy/vital)

  vital-mac install [--force]   Download the notarized release, verify it and put it in /Applications
  vital-mac uninstall           Remove Vital and its fan helper
  vital-mac help

After installing, the "vital" command reports on your Mac: vital status | apps | history.`;

async function main(argv) {
  const [cmd = 'install', ...rest] = argv;
  switch (cmd) {
    case 'install': await install({ force: rest.includes('--force') }); break;
    case 'uninstall': uninstall(); break;
    case 'help': case '--help': case '-h': console.log(USAGE); break;
    default: console.error(`vital-mac: unknown command '${cmd}'\n\n${USAGE}`); process.exitCode = 2;
  }
}

main(process.argv.slice(2)).catch((e) => { console.error(`vital-mac: ${e.message}`); process.exitCode = 1; });
