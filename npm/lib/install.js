'use strict';
// Downloads the notarized Vital release from GitHub, verifies it, and installs it. No install scripts run
// when this package is added: nothing is downloaded until the user runs `vital-mac install`.
const { createHash } = require('node:crypto');
const { execFileSync, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const REPO = 'soumyyy/vital';
const DEFAULT_APPS = '/Applications';
const FIRST_WITH_COMMAND_LINE = '0.1.5';

function appPath(dir = DEFAULT_APPS) { return path.join(dir, 'Vital.app'); }
function binaryPath(dir = DEFAULT_APPS) { return path.join(appPath(dir), 'Contents', 'MacOS', 'Vital'); }

function sha256(file) {
  const hash = createHash('sha256');
  hash.update(fs.readFileSync(file));
  return hash.digest('hex');
}

// "<hex>  <name>" lines, as `shasum -a 256` writes them.
function parseChecksums(text) {
  const out = new Map();
  for (const line of text.split('\n')) {
    const m = /^([0-9a-f]{64})\s+\*?(.+?)\s*$/.exec(line);
    if (m) out.set(m[2], m[1]);
  }
  return out;
}

async function getJSON(url) {
  const res = await fetch(url, { headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'vital-mac' } });
  if (!res.ok) throw new Error(`GitHub answered ${res.status} for ${url}`);
  return res.json();
}

async function download(url, dest) {
  const res = await fetch(url, { headers: { 'User-Agent': 'vital-mac' }, redirect: 'follow' });
  if (!res.ok) throw new Error(`Download failed (${res.status}): ${url}`);
  fs.writeFileSync(dest, Buffer.from(await res.arrayBuffer()));
}

function installedVersion(dir = DEFAULT_APPS) {
  try {
    const out = execFileSync('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleShortVersionString', path.join(appPath(dir), 'Contents', 'Info.plist')], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    return out.trim();
  } catch { return null; }
}

async function install({ dir = DEFAULT_APPS, force = false, open = true, log = console.log } = {}) {
  if (process.platform !== 'darwin' || process.arch !== 'arm64') throw new Error('Vital needs a Mac with Apple silicon.');
  const have = installedVersion(dir);
  const release = await getJSON(`https://api.github.com/repos/${REPO}/releases/latest`);
  const version = String(release.tag_name || '').replace(/^v/, '');
  if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error(`Unexpected release tag: ${release.tag_name}`);
  if (have && !force) {
    log(have === version ? `Vital ${have} is already installed.` : `Vital ${have} is installed; ${version} is available. Run "vital-mac install --force" or use Update Software in Vital.`);
    return { version: have, changed: false };
  }
  const asset = (name) => (release.assets || []).find((a) => a.name === name);
  const zip = asset(`Vital-${version}.zip`), sums = asset('SHA256SUMS');
  if (!zip || !sums) throw new Error(`Release ${version} has no Vital-${version}.zip and SHA256SUMS`);

  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'vital-mac-'));
  try {
    log(`Downloading Vital ${version}…`);
    const zipFile = path.join(work, zip.name), sumsFile = path.join(work, 'SHA256SUMS');
    await download(zip.browser_download_url, zipFile);
    await download(sums.browser_download_url, sumsFile);

    const expected = parseChecksums(fs.readFileSync(sumsFile, 'utf8')).get(zip.name);
    if (!expected) throw new Error(`SHA256SUMS does not list ${zip.name}`);
    if (sha256(zipFile) !== expected) throw new Error('Checksum mismatch: the download is not the published release. Nothing was installed.');

    const out = path.join(work, 'out');
    execFileSync('/usr/bin/ditto', ['-x', '-k', zipFile, out]);
    const staged = path.join(out, 'Vital.app');
    execFileSync('/usr/bin/codesign', ['--verify', '--deep', '--strict', staged], { stdio: 'pipe' });
    const gate = spawnSync('/usr/sbin/spctl', ['--assess', '--type', 'execute', staged], { encoding: 'utf8' });
    if (gate.status !== 0) throw new Error(`macOS would not open this app: ${gate.stderr.trim()}`);

    if (have) spawnSync('/usr/bin/osascript', ['-e', 'tell application id "dev.soumya.vital" to quit']);
    fs.mkdirSync(dir, { recursive: true });
    const target = appPath(dir), old = `${target}.old-${process.pid}`;
    if (fs.existsSync(target)) fs.renameSync(target, old);
    try { execFileSync('/usr/bin/ditto', [staged, target]); }
    catch (e) { if (fs.existsSync(old)) { fs.rmSync(target, { recursive: true, force: true }); fs.renameSync(old, target); } throw e; }
    fs.rmSync(old, { recursive: true, force: true });
    log(`Installed Vital ${version} in ${dir}.`);
    if (open) spawnSync('/usr/bin/open', ['-a', target]);
    return { version, changed: true };
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}

function uninstall({ dir = DEFAULT_APPS, log = console.log } = {}) {
  const bin = binaryPath(dir);
  if (!fs.existsSync(appPath(dir))) { log('Vital is not installed.'); return false; }
  spawnSync('/usr/bin/osascript', ['-e', 'tell application id "dev.soumya.vital" to quit']);
  if (fs.existsSync(bin)) spawnSync(bin, ['--unregister-fan-helper'], { stdio: 'inherit' });   // removes the optional fan helper
  fs.rmSync(appPath(dir), { recursive: true, force: true });
  log('Vital was removed. Its settings and history (~/Library/Application Support/Vital) were kept.');
  return true;
}

// True when `a` is the same as or newer than `b` (dotted numbers).
function atLeast(a, b) {
  const x = a.split('.').map(Number), y = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) { if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0); }
  return true;
}

module.exports = { atLeast, FIRST_WITH_COMMAND_LINE, install, uninstall, installedVersion, parseChecksums, sha256, appPath, binaryPath };
