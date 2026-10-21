const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

test('macOS local self-check uses an ephemeral key and preserves unreadable state', { skip: process.platform !== 'darwin', timeout: 30000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'local-workspace-check-'));
  const state = path.join(root, 'state');
  const service = 'community.localworkspace.mac.state-encryption.test.ephemeral-' + path.basename(root);
  const exe = process.env.WORKSPACE_TEST_EXE || path.resolve(__dirname, '../dist-macos/ChatGPT Codex Workspace.app/Contents/Resources/Backend/workspace-server');
  const start = () => {
    const child = spawn(exe, ['--mcp'], { stdio: ['pipe', 'pipe', 'pipe'], env: {
      ...process.env, WORKSPACE_STATE_DIR: state, WORKSPACE_EPHEMERAL_STATE: '1',
      WORKSPACE_TEST_STATE_KEYCHAIN_SERVICE: service,
      CONTROL_PLANE_API_KEY: '', WORKSPACE_TUNNEL_ID: '', WORKSPACE_TUNNEL_HEALTH_FILE: '',
    } });
    let buffer = '', seq = 0;
    const pending = new Map();
    const done = new Promise(resolve => child.once('close', resolve));
    child.stdout.on('data', chunk => {
      buffer += chunk;
      let end;
      while ((end = buffer.indexOf('\n')) >= 0) {
        const value = JSON.parse(buffer.slice(0, end)); buffer = buffer.slice(end + 1);
        const waiting = pending.get(value.id);
        if (waiting) { clearTimeout(waiting.timer); pending.delete(value.id); waiting.resolve(value); }
      }
    });
    const rpc = (method, params = {}) => new Promise((resolve, reject) => {
      const id = ++seq;
      pending.set(id, { resolve, timer: setTimeout(() => reject(Error('Self-check RPC timed out: ' + method)), 5000) });
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
    });
    return { rpc, call: (name, args) => rpc('tools/call', { name, arguments: args || {} }), async stop() {
      child.stdin.end();
      const timer = setTimeout(() => child.kill('SIGTERM'), 2000);
      await done;
      clearTimeout(timer);
      for (const entry of pending.values()) clearTimeout(entry.timer);
    } };
  };
  let app = start();
  try {
    await app.rpc('initialize');
    const registered = await app.call('register_conversation', { title: 'Ephemeral check', path: root });
    assert(!registered.error && !registered.result.isError);
    const written = await app.call('write_file', { path: path.join(root, 'check.txt'), content: 'ephemeral-secret-fixture', thread_id: registered.result.structuredContent.result.thread_id });
    assert(!written.error && !written.result.isError);
    await app.stop(); app = null;
    const files = fs.readdirSync(state).filter(name => name.endsWith('.bin'));
    assert(files.length > 0);
    const original = new Map(files.map(name => [name, fs.readFileSync(path.join(state, name))]));
    for (const bytes of original.values()) {
      assert.equal(bytes.subarray(0, 8).toString(), 'LWSMAC01');
      assert(!bytes.includes(Buffer.from('ephemeral-secret-fixture')));
    }
    const item = spawnSync('/usr/bin/security', ['find-generic-password', '-s', service, '-a', 'state-v1'], { stdio: 'pipe', timeout: 5000 });
    assert.equal(item.status, 44, 'self-check must not create a Keychain item');
    app = start();
    await app.rpc('initialize');
    const reopened = await app.call('get_workspace_status');
    assert(reopened.error || reopened.result.isError, 'ephemeral state must refuse to reopen without its previous in-memory key');
    await app.stop(); app = null;
    for (const [name, bytes] of original) assert.deepEqual(fs.readFileSync(path.join(state, name)), bytes, 'failed reopen must preserve saved state');
  } finally {
    if (app) await app.stop();
    fs.rmSync(root, { recursive: true, force: true });
  }
});
