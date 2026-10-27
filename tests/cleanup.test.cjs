'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { clean } = require('../scripts/clean_macos.cjs');

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'local-workspace-cleanup-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const files = {
    'package.json': JSON.stringify({ name: 'local-workspace-dashboard' }),
    'macos/backend/WorkspaceBackend.csproj': 'project',
    'scripts/build_and_run.sh': 'build',
    '.tools/dotnet/dotnet': 'sdk',
    'node_modules/react/index.js': 'module',
    'macos/.build/release/app': 'build',
    'macos/backend/bin/release/server': 'build',
    'macos/backend/obj/cache': 'build',
    'dist-macos/Preview.app/runtime': 'keep app',
    'src/file.cs': 'keep source',
    '.git/objects/history': 'keep git',
    'state/changes.bin': 'keep history',
    'settings.json': 'keep settings',
  };
  for (const [name, contents] of Object.entries(files)) {
    const file = path.join(root, name);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, contents);
  }
  return { root, files };
}

test('cleanup previews and removes only rebuildable directories, then is idempotent', t => {
  const { root, files } = fixture(t);
  assert.equal(clean(root, { inUse: () => [] }).length, 5);
  for (const [name, contents] of Object.entries(files)) assert.equal(fs.readFileSync(path.join(root, name), 'utf8'), contents);
  const removed = clean(root, { apply: true, inUse: () => [] });
  for (const name of removed) assert.equal(fs.existsSync(path.join(root, name)), false);
  for (const name of ['dist-macos/Preview.app/runtime', 'src/file.cs', '.git/objects/history', 'state/changes.bin', 'settings.json']) {
    assert.equal(fs.readFileSync(path.join(root, name), 'utf8'), files[name]);
  }
  assert.deepEqual(clean(root, { apply: true, inUse: () => [] }), []);
});

test('an active build prevents all deletion', t => {
  const { root } = fixture(t);
  assert.throws(() => clean(root, { apply: true, inUse: p => p.endsWith('node_modules') ? [123] : [] }), /in use/);
  assert.equal(fs.readFileSync(path.join(root, '.tools/dotnet/dotnet'), 'utf8'), 'sdk');
});

test('macOS open-file inspection protects a real open cache file', { skip: process.platform !== 'darwin' }, t => {
  const { root } = fixture(t);
  const descriptor = fs.openSync(path.join(root, '.tools/dotnet/dotnet'), 'r');
  t.after(() => fs.closeSync(descriptor));
  assert.throws(() => clean(root, { apply: true }), /in use/);
  assert.equal(fs.existsSync(path.join(root, 'node_modules')), true);
});

test('cleanup rejects cache parent symlinks and wrong projects', t => {
  const { root } = fixture(t);
  fs.rmSync(path.join(root, 'macos/backend'), { recursive: true });
  fs.symlinkSync(path.join(root, 'state'), path.join(root, 'macos/backend'));
  fs.writeFileSync(path.join(root, 'state/WorkspaceBackend.csproj'), 'project');
  fs.mkdirSync(path.join(root, 'state/bin'));
  assert.throws(() => clean(root, { apply: true, inUse: () => [] }), /unexpected cache path/);
  assert.equal(fs.existsSync(path.join(root, '.tools')), true);
  assert.equal(fs.readFileSync(path.join(root, 'state/changes.bin'), 'utf8'), 'keep history');
  fs.writeFileSync(path.join(root, 'package.json'), '{"name":"another-project"}');
  assert.throws(() => clean(root, { apply: true, inUse: () => [] }), /Not a Local Workspace/);
});
