#!/usr/bin/env node
'use strict';

// Re-downloadable build inputs only; never sweep apps, Git or user data.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const CACHE_PATHS = ['.tools', 'node_modules', 'macos/.build', 'macos/backend/bin', 'macos/backend/obj'];

function validateRoot(root) {
  root = fs.realpathSync(root);
  const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
  if (pkg.name !== 'local-workspace-dashboard' ||
      !fs.existsSync(path.join(root, 'macos/backend/WorkspaceBackend.csproj')) ||
      !fs.existsSync(path.join(root, 'scripts/build_and_run.sh'))) {
    throw new Error('Not a Local Workspace source checkout. Nothing removed.');
  }
  return root;
}

function checkedEntry(root, relative) {
  const target = path.join(root, relative);
  // Include parents and dangling symlinks; do not follow a cache into another project.
  let current = root;
  for (const component of relative.split('/')) {
    current = path.join(current, component);
    let stat;
    try { stat = fs.lstatSync(current); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
      throw new Error(`Refusing unexpected cache path: ${relative}. Nothing removed.`);
    }
  }
  const stat = fs.statSync(target);
  return { relative, target, dev: stat.dev, ino: stat.ino };
}

function openProcesses(target) {
  const result = spawnSync('/usr/sbin/lsof', ['-nP', '-F', 'p', '+D', target], {
    encoding: 'utf8', timeout: 15000, maxBuffer: 1024 * 1024,
  });
  if (result.error || ![0, 1].includes(result.status) || result.stderr.trim()) {
    throw new Error('Could not verify open files; nothing removed. Stop builds and try again.');
  }
  return [...result.stdout.matchAll(/^p(\d+)$/gm)].map(match => Number(match[1]));
}

function clean(root, { apply = false, inUse = openProcesses } = {}) {
  root = validateRoot(root);
  const entries = CACHE_PATHS.map(relative => checkedEntry(root, relative)).filter(Boolean);
  // Complete the entire preflight before removing anything.
  for (const entry of entries) {
    const owners = inUse(entry.target);
    if (owners.length) throw new Error(`Cache is in use: ${entry.relative} (PID ${owners.join(', ')}). Nothing removed.`);
  }
  if (apply) {
    for (const entry of entries) {
      const current = checkedEntry(root, entry.relative);
      if (!current || current.dev !== entry.dev || current.ino !== entry.ino) {
        throw new Error(`Cache changed during cleanup: ${entry.relative}. Stopped.`);
      }
      fs.rmSync(entry.target, { recursive: true });
    }
  }
  return entries.map(entry => entry.relative);
}

if (require.main === module) {
  try {
    const args = process.argv.slice(2);
    if (args.some(arg => !['--apply', '--dry-run'].includes(arg))) {
      throw new Error('Usage: node scripts/clean_macos.cjs [--apply | --dry-run]');
    }
    const apply = args.includes('--apply') && !args.includes('--dry-run');
    const entries = clean(path.join(__dirname, '..'), { apply });
    console.log(entries.length ? `${apply ? 'Removed' : 'Would remove'} build files:\n${entries.join('\n')}` : 'No build caches to remove.');
    console.log('Apps, source, Git, settings, Keychain and saved workspace history are preserved.');
    if (!apply && entries.length) console.log('Use --apply to remove these regenerable directories.');
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = { clean };
