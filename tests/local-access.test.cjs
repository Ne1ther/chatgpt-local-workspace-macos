const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, execFileSync } = require('node:child_process');

test('actual backend access checks preserve files and distinguish denial, missing paths and caller authority', { skip: process.platform !== 'darwin', timeout: 30000 }, async () => {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'local-workspace-check-access-')));
  const project = path.join(root, 'project'), blocked = path.join(root, 'blocked');
  fs.mkdirSync(project); fs.mkdirSync(blocked);
  const original = Buffer.from('existing user data\n');
  fs.writeFileSync(path.join(project, 'keep.txt'), original);
  fs.writeFileSync(path.join(blocked, 'private.txt'), 'permission fixture');
  const exe = process.env.WORKSPACE_TEST_EXE || path.resolve(__dirname, '../dist-macos/ChatGPT Codex Workspace.app/Contents/Resources/Backend/workspace-server');
  const child = spawn(exe, ['--mcp'], { stdio: ['pipe', 'pipe', 'pipe'], env: {
    ...process.env, WORKSPACE_EPHEMERAL_STATE: '1', WORKSPACE_STATE_DIR: path.join(root, 'state'),
    CODEX_HOME: path.join(root, 'codex'), CONTROL_PLANE_API_KEY: '', WORKSPACE_TUNNEL_ID: '', WORKSPACE_TUNNEL_HEALTH_FILE: '',
  } });
  const pending = new Map(); let seq = 0, buffer = '', base = '';
  const exited = new Promise(resolve => child.once('close', resolve));
  child.stderr.on('data', bytes => { const match = bytes.toString().match(/\[Dashboard\] (http:\/\/127\.0\.0\.1:\d+\/)/); if (match) base = match[1]; });
  child.stdout.on('data', bytes => {
    buffer += bytes; let end;
    while ((end = buffer.indexOf('\n')) >= 0) {
      const reply = JSON.parse(buffer.slice(0, end)); buffer = buffer.slice(end + 1);
      const waiter = pending.get(reply.id);
      if (waiter) { clearTimeout(waiter.timer); pending.delete(reply.id); waiter.resolve(reply); }
    }
  });
  const rpc = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++seq;
    pending.set(id, { resolve, timer: setTimeout(() => reject(Error('access RPC timed out')), 7000) });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
  const tool = async (name, args = {}) => {
    const reply = await rpc('tools/call', { name, arguments: args, _meta: { 'openai/session': 'access-test' } });
    assert(!reply.error, JSON.stringify(reply));
    return reply.result;
  };
  try {
    await rpc('initialize');
    assert.equal((await rpc('tools/list')).result.tools.length, 23);
    const policy = (await tool('get_workspace_status')).structuredContent.result.access_policy;
    assert.equal(policy.privilege_escalation, false);
    assert.equal(policy.workspace_is_sandbox, false);
    assert.equal(policy.execution_identity, 'current_user');
    const budget = (await tool('exec_command', { cwd: project, cmd: 'sleep 60', timeout_seconds: 86400, yield_time_ms: 0 })).structuredContent.result;
    assert.equal(budget.timeout_seconds, 86400);
    assert(Date.parse(budget.deadline_at) - Date.now() > 86000000);
    const stopped = (await tool('write_stdin', { session_id: budget.session_id, chars: '\u0003' })).structuredContent.result;
    assert.equal(stopped.running, false);
    const modern = { 'openai/session': 'access-test', 'io.modelcontextprotocol/protocolVersion': '2026-07-28',
      'io.modelcontextprotocol/clientCapabilities': { extensions: { 'io.modelcontextprotocol/tasks': {} } } };
    const longTask = (await rpc('tools/call', { name: 'exec_command', arguments: { cwd: project, cmd: 'sleep 60', timeout_seconds: 86400, yield_time_ms: 0 }, _meta: modern })).result;
    assert.equal(longTask.resultType, 'task'); assert(longTask.ttlMs > 86400000);
    await rpc('tasks/cancel', { taskId: longTask.taskId, _meta: modern });
    assert.equal((await rpc('tasks/get', { taskId: longTask.taskId, _meta: modern })).result.status, 'cancelled');
    const tooLong = await tool('exec_command', { cwd: project, cmd: 'touch must-not-run', timeout_seconds: 86401 });
    assert.equal(tooLong.isError, true); assert(!fs.existsSync(path.join(project, 'must-not-run')));
    for (let n = 0; !base && n < 50; n++) await new Promise(resolve => setTimeout(resolve, 20));
    assert(base);
    const token = (await (await fetch(new URL('api/local-actions', base))).json()).token;
    const url = (target, write = '0') => { const u = new URL('api/check-access', base); u.searchParams.set('path', target); u.searchParams.set('write', write); return u; };
    const headers = { Origin: base.slice(0, -1), 'X-Workspace-Token': token };
    assert.equal((await fetch(url(project))).status, 405);
    assert.equal((await fetch(url(project), { method: 'POST' })).status, 403);
    assert.equal((await fetch(url(project), { method: 'POST', headers: { ...headers, Origin: 'https://external.invalid' } })).status, 403);
    assert.equal((await fetch(url(project), { method: 'POST', headers: { ...headers, 'X-Workspace-Token': 'invalid' } })).status, 403);
    assert.equal((await fetch(url(project), { method: 'POST', headers: { ...headers, 'Sec-Fetch-Site': 'cross-site' } })).status, 403);
    assert.equal((await fetch(url(project, 'yes'), { method: 'POST', headers })).status, 400);
    const check = async (target, write = '0') => {
      const response = await fetch(url(target, write), { method: 'POST', headers });
      assert.equal(response.status, 200); return response.json();
    };
    const readOnly = await check(project);
    assert.equal(readOnly.read.status, 'available'); assert.equal(readOnly.write.status, 'not_checked');
    const write = await check(project, '1');
    assert.equal(write.read.status, 'available'); assert.equal(write.write.status, 'available'); assert.equal(write.probe_file, null);
    assert.deepEqual(fs.readdirSync(project), ['keep.txt']);
    assert.deepEqual(fs.readFileSync(path.join(project, 'keep.txt')), original);
    const alias = path.join(root, 'alias'); fs.symlinkSync(project, alias);
    assert.equal((await check(alias)).canonical_path, project);
    const missing = path.join(root, 'does-not-exist');
    assert.equal((await check(missing)).read.status, 'missing'); assert(!fs.existsSync(missing));
    assert.equal((await check(path.join(project, 'keep.txt'), '1')).read.status, 'failed');
    fs.chmodSync(blocked, 0o000);
    const denied = await check(blocked, '1');
    assert.equal(denied.read.status, 'denied'); assert.equal(denied.write.status, 'denied');
    const deniedTool = await tool('read_file', { path: path.join(blocked, 'private.txt') });
    assert.equal(deniedTool.isError, true);
    assert.equal(deniedTool.structuredContent.result.error_code, 'ACCESS_DENIED');
    assert(deniedTool.structuredContent.result.next_action.includes('本地能力'));
    assert.equal(deniedTool.structuredContent.result.retry_after_user_action, true);
    const missingTool = await tool('read_file', { path: missing });
    assert.equal(missingTool.structuredContent.result.error_code, 'PATH_NOT_FOUND');
    const snapshot = await (await fetch(new URL('api/snapshot', base))).json();
    const failed = snapshot.activity.find(x => x.error_code === 'ACCESS_DENIED');
    assert(failed.detail.next_action.includes('本地能力'));
    fs.chmodSync(blocked, 0o700);
    assert.deepEqual(fs.readdirSync(blocked), ['private.txt']);
  } finally {
    fs.chmodSync(blocked, 0o700);
    child.stdin.end();
    const timer = setTimeout(() => child.kill('SIGTERM'), 2000);
    await exited; clearTimeout(timer);
    for (const item of pending.values()) clearTimeout(item.timer);
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('native health advice follows current evidence and preserves failure recovery scope', { skip: process.platform !== 'darwin', timeout: 30000 }, () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-advice-'));
  try {
    const main = path.join(directory, 'main.swift');
    fs.writeFileSync(main, `import Foundation
func row(_ id: String, _ status: String, _ target: String, _ code: String?) -> ActivityEntry {
    ActivityEntry(id: id, threadId: "a", tool: "read_file", target: target, status: status, startedAt: "2026-10-18T00:00:00.000Z", elapsedMs: 0, errorCode: code)
}
func advice(_ rows: [ActivityEntry], _ stale: Bool = false, _ observed: Bool = true) -> [WorkspaceAdvice] {
    WorkspaceHealthAdvisor.recommendations(state: .connected, stale: stale, observed: observed, activity: rows, access: nil)
}
let failed = row("denied", "failed", "/project/private", "ACCESS_DENIED")
assert(advice([failed]).contains { $0.id == "permission" })
assert(!advice([row("ok", "returned", "/project/private", nil), failed]).contains { $0.id == "permission" })
assert(advice([row("different", "returned", "/other", nil), failed]).contains { $0.id == "permission" })
assert(advice([], false, false).map(\\.id) == ["host"])
assert(advice([], true, false).map(\\.id) == ["stale"])
assert(advice([]).isEmpty)
let json = #"{"path":"/p","canonical_path":"/p","checked_at":"now","read":{"status":"available","message":"read","error_code":null},"write":{"status":"cleanup_required","message":"failed","error_code":"PROBE_CLEANUP_REQUIRED"},"probe_file":"/p/.probe","scope":"current check"}"#
let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
let report = try decoder.decode(LocalAccessReport.self, from: Data(json.utf8))
assert(report.read.passed && !report.write.passed)
let cleanup = WorkspaceHealthAdvisor.recommendations(state: .connected, stale: true, observed: false, activity: [failed], access: report)
assert(cleanup.first?.id == "probe-cleanup" && cleanup.count <= 3)
print("Native advice and report decoding passed")
`);
    const exe = path.join(directory, 'advice');
    execFileSync('xcrun', ['swiftc', 'macos/Sources/LocalWorkspace/Models/WorkspaceModels.swift', 'macos/Sources/LocalWorkspace/Models/LocalAccessReport.swift', main, '-o', exe], { stdio: 'pipe' });
    assert(execFileSync(exe, [], { encoding: 'utf8' }).includes('passed'));
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
