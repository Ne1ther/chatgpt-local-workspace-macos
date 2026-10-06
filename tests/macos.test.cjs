// Real macOS backend integration: isolated temporary files, no account required.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, execFileSync } = require('node:child_process');
const Ajv = require('ajv');

test('macOS: all 28 tools, isolation, POSIX process lifecycle and MCP compatibility', { timeout: 90000 }, async t => {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-mac-integration-')));
  const stateService = 'community.localworkspace.mac.state-encryption.test.' + path.basename(root);
  const exe = process.env.WORKSPACE_TEST_EXE || path.resolve(__dirname, '../dist-macos/ChatGPT Codex Workspace.app/Contents/Resources/Backend/workspace-server');
  const child = spawn(exe, ['--mcp'], { stdio: ['pipe', 'pipe', 'pipe'], env: {
    ...process.env, WORKSPACE_TUNNEL_ID: 'tunnel_0123456789abcdef0123456789abcdef',
    CONTROL_PLANE_API_KEY: 'sk-offline-config-fixture-not-a-real-key', WORKSPACE_TUNNEL_HEALTH_FILE: '', WORKSPACE_STATE_DIR: path.join(root, '.state'),
    WORKSPACE_TEST_STATE_KEYCHAIN_SERVICE: stateService
  } });
  let buffer = '', stderr = '', seq = 0, base = '';
  const pending = new Map(), seen = new Set(), schemas = new Map();
  let publicHttpsVerified = false;
  const rejectPending = error => {
    for (const waiter of pending.values()) { clearTimeout(waiter.timer); waiter.reject(error); }
    pending.clear();
  };
  const exited = new Promise(resolve => child.once('close', () => {
    rejectPending(Error('Test backend closed before responding'));
    resolve();
  }));
  child.on('error', rejectPending);
  child.stdin.on('error', rejectPending);
  child.stderr.on('data', data => {
    stderr += data;
    const found = stderr.match(/\[Dashboard\] (http:\/\/127\.0\.0\.1:\d+\/)/);
    if (found) base = found[1];
  });
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', data => {
    buffer += data;
    let index;
    while ((index = buffer.indexOf('\n')) >= 0) {
      const value = JSON.parse(buffer.slice(0, index)); buffer = buffer.slice(index + 1);
      const waiter = pending.get(value.id);
      if (waiter) { pending.delete(value.id); clearTimeout(waiter.timer); waiter.resolve(value); }
    }
  });
  const rpc = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++seq;
    const label = method + (params.name ? ` (${params.name})` : '');
    pending.set(id, { resolve, reject, timer: setTimeout(() => {
      pending.delete(id);
      reject(Error(`Timeout: ${label}\n${stderr.slice(-1500)}`));
    }, 20000) });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
  const call = async (name, args = {}, session = 'mac-test-A', allowError = false) => {
    seen.add(name);
    const answer = await rpc('tools/call', { name, arguments: args, _meta: { 'openai/session': session } });
    assert(!answer.error, JSON.stringify(answer));
    if (!allowError) assert(!answer.result.isError, JSON.stringify(answer));
    const validate = schemas.get(name);
    if (validate) assert(validate(answer.result.structuredContent), `${name}: ${JSON.stringify(validate.errors)}`);
    return answer.result;
  };
  const result = async (...args) => (await call(...args)).structuredContent.result;
  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
  const tool = async (name, args, session) => result(name, args, session);
  try {
    const init = await rpc('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'mac-integration', version: '1' } });
    assert.equal(init.result.protocolVersion, '2025-06-18');
    const list = (await rpc('tools/list')).result.tools;
    assert.equal(list.length, 28);
    const ajv = new Ajv({ strict: false });
    for (const item of list) schemas.set(item.name, ajv.compile(item.outputSchema));
    assert(list.find(x => x.name === 'exec_command').inputSchema.properties.shell.enum.includes('zsh'));
    const status = await tool('get_workspace_status');
    assert.equal(status.default_shell, 'zsh'); assert.equal(status.tool_count, 28);
    assert(status.executable.endsWith('workspace-server')); assert.equal(status.host_session_observed, true);
    const conversation = await tool('register_conversation', { path: root, title: 'macOS 中文检查' });
    assert(conversation.thread_id);
    const fixture = path.join(root, '中文 空格', "quote ' double\".txt");
    await tool('create_directory', { path: path.dirname(fixture) });
    await tool('write_file', { path: fixture, content: 'alpha\nbeta\n' });
    assert((await tool('read_file', { path: fixture, limit: 1 })).next_line === 2);
    assert((await call('write_file', { path: fixture, content: 'do not overwrite' }, undefined, true)).isError);
    await tool('edit_file', { path: fixture, old_text: 'beta', new_text: '中文 gamma' });
    assert.equal(fs.readFileSync(fixture, 'utf8'), 'alpha\n中文 gamma\n');
    assert.equal((await tool('file_info', { path: fixture })).size_bytes, fs.statSync(fixture).size);
    assert.equal((await tool('list_directory', { path: path.dirname(fixture) })).returned_count, 1);
    assert.equal((await tool('search_files', { path: root, pattern: '*.txt' })).matches.length, 1);
    assert.equal((await tool('search_text', { path: root, query: 'gamma' })).matches.length, 1);
    assert.equal((await tool('show_changes', { path: root })).count, 1);
    const history = await tool('workspace_history', { path: root });
    const edited = history.changes.find(change => change.tool === 'edit_file');
    assert(edited, 'edited file is journaled');
    await tool('restore_change', { change_id: edited.id });
    assert.equal(fs.readFileSync(fixture, 'utf8'), 'alpha\n中文 gamma\n', 'restore defaults to preview');
    const plan = [{ step: 'Verify macOS port', status: 'in_progress' }];
    await tool('update_plan', { path: root, plan });
    assert.equal((await tool('check_task_completion', { path: root })).can_finish, false);
    const opened = await tool('open_workspace', { path: root });
    assert.equal(opened.default_shell, 'zsh'); assert(opened.shells.some(s => s.name === 'zsh' && s.available));
    assert.equal(opened.plan.plan[0].step, plan[0].step);
    const patch = body => tool('apply_patch', { cwd: root, patch: `*** Begin Patch\n${body}\n*** End Patch` });
    await patch('*** Add File: patch.txt\n+one\n+two');
    await patch('*** Update File: patch.txt\n@@\n one\n-two\n+three');
    assert.equal(fs.readFileSync(path.join(root, 'patch.txt'), 'utf8'), 'one\nthree\n');
    await patch('*** Update File: patch.txt\n*** Move to: moved.txt');
    assert(!fs.existsSync(path.join(root, 'patch.txt')));
    await patch('*** Delete File: moved.txt');
    await patch('*** Add File: mac:filename.txt\n+valid POSIX name');
    assert.equal(fs.readFileSync(path.join(root, 'mac:filename.txt'), 'utf8'), 'valid POSIX name\n');
    const alias = root + '-alias';
    fs.symlinkSync(root, alias);
    try {
      await tool('write_file', { path: path.join(alias, 'alias.txt'), content: 'before\n' });
      await tool('apply_patch', { cwd: alias, patch: '*** Begin Patch\n*** Update File: alias.txt\n@@\n-before\n+after\n*** End Patch' });
      assert((await tool('show_changes', { path: alias })).files.some(f => f.path.endsWith('/alias.txt')));
      assert((await tool('read_workspace_activity', { path: alias })).activity.some(a => a.tool === 'apply_patch'));
    } finally { fs.unlinkSync(alias); }
    const script = path.join(root, 'executable.sh');
    fs.writeFileSync(script, '#!/bin/sh\necho before\n', { mode: 0o755 });
    await patch('*** Update File: executable.sh\n@@\n-echo before\n+echo after');
    assert.equal(fs.statSync(script).mode & 0o777, 0o755, 'patches preserve macOS executable permissions');
    const executableEdit = await call('edit_file', { path: script, old_text: 'after', new_text: 'guarded' });
    assert.equal(fs.statSync(script).mode & 0o777, 0o755, 'guarded edits preserve executable permissions');
    await tool('restore_change', { change_id: executableEdit.structuredContent.result.change_id, apply: true });
    assert.equal(fs.statSync(script).mode & 0o777, 0o755, 'file restore preserves executable permissions');
    for (const name of ['../escape.txt', '../' + path.basename(root).toUpperCase() + '/escape.txt']) {
      const bad = await call('apply_patch', { cwd: root, patch: `*** Begin Patch\n*** Add File: ${name}\n+bad\n*** End Patch` }, undefined, true);
      assert(bad.isError);
    }
    fs.symlinkSync(os.tmpdir(), path.join(root, 'outside'));
    assert((await call('apply_patch', { cwd: root, patch: '*** Begin Patch\n*** Add File: outside/escape.txt\n+bad\n*** End Patch' }, undefined, true)).isError);
    const atomic = await call('apply_patch', { cwd: root, patch: '*** Begin Patch\n*** Add File: never-written.txt\n+bad\n*** Update File: missing.txt\n@@\n-a\n+b\n*** End Patch' }, undefined, true);
    assert(atomic.isError); assert(!fs.existsSync(path.join(root, 'never-written.txt')));
    const bom = path.join(root, 'bom.txt');
    fs.writeFileSync(bom, Buffer.concat([Buffer.from([239,187,191]), Buffer.from('before\r\n')]));
    await tool('edit_file', { path: bom, old_text: 'before', new_text: 'after' });
    assert(fs.readFileSync(bom).equals(Buffer.concat([Buffer.from([239,187,191]), Buffer.from('after\r\n')])));
    for (const shell of ['zsh', 'bash', 'sh']) {
      const execution = await tool('exec_command', { cwd: root, shell, cmd: "printf '%s' 'quoted \"value\" 中文 $HOME'", yield_time_ms: 3000 });
      assert.equal(execution.output, 'quoted "value" 中文 $HOME'); assert.equal(execution.exit_code, 0);
      assert(execution.shell_executable.endsWith('/' + shell), 'real shell executable is reported');
    }
    const stdin = await tool('exec_command', { cwd: root, cmd: 'read -r value; printf "received:%s" "$value"', yield_time_ms: 0 });
    await tool('write_stdin', { session_id: stdin.session_id, chars: 'hello 中文\n' });
    const inputResult = await tool('poll_command', { session_id: stdin.session_id, yield_ms: 3000 });
    assert(inputResult.full_output.includes('received:hello 中文'));
    assert.equal((await tool('read_command', { session_id: stdin.session_id })).output_mode, 'snapshot');
    assert((await tool('list_commands')).commands.length >= 4);
    const tree = await tool('exec_command', { cwd: root, cmd: 'sleep 60 & echo $!; wait', yield_time_ms: 300 });
    const sleeper = Number(tree.output.trim()); assert(sleeper > 0);
    assert.equal((await tool('stop_command', { session_id: tree.session_id })).running, false);
    await delay(200);
    try { const state = execFileSync('/bin/ps', ['-o', 'stat=', '-p', String(sleeper)], { encoding: 'utf8' }); assert(state.trim().startsWith('Z') || state.trim() === ''); } catch (error) { if (error.code === 'ERR_ASSERTION') throw error; }
    const timer = await tool('exec_command', { cwd: root, cmd: 'sleep 60', timeout_seconds: 1, yield_time_ms: 0 });
    await delay(1300);
    const timed = (await call('read_command', { session_id: timer.session_id }, undefined, true)).structuredContent.result;
    assert.equal(timed.timed_out, true); assert.equal(timed.running, false);
    const imageBytes = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXioAAAAASUVORK5CYII=', 'base64');
    const imagePath = path.join(root, 'pixel.png'); fs.writeFileSync(imagePath, imageBytes);
    const image = await call('read_image', { path: imagePath });
    assert.equal(image.content[1].mimeType, 'image/png');
    assert.deepEqual(Buffer.from(image.content[1].data, 'base64'), imageBytes);
    assert.deepEqual(Buffer.from(await (await fetch(new URL(image.structuredContent.result.preview_url, base))).arrayBuffer()), imageBytes);
    const git = (...args) => execFileSync('git', args, { cwd: root, stdio: 'pipe' });
    git('init', '-q'); fs.writeFileSync(path.join(root, 'tracked.txt'), 'before\n'); git('add', 'tracked.txt');
    git('-c', 'user.name=Mac Test', '-c', 'user.email=mac@example.invalid', 'commit', '-qm', 'fixture');
    fs.writeFileSync(path.join(root, 'tracked.txt'), 'after\n');
    assert((await tool('git_status', { path: root })).output.includes('tracked.txt'));
    assert((await tool('git_diff', { path: root })).output.includes('+after'));
    const imported = path.join(root, 'license-import.txt');
    const importedResult = await call('import_file', { path: imported, file: { file_id: 'public-license-fixture', download_url: 'https://raw.githubusercontent.com/CSL19980820/chatgpt-local-workspace/main/LICENSE' } }, undefined, true);
    if (importedResult.isError && importedResult.structuredContent.result.message === 'Private and loopback download addresses are not allowed.') {
      assert(!fs.existsSync(imported), 'blocked download must not leave a destination');
      await t.test('real public HTTPS attachment download', { skip: 'Public fixture resolves to private/fake-IP addresses on this network; keep the download guard enabled.' }, () => {});
      fs.writeFileSync(imported, 'existing destination fixture\n');
    } else {
      assert(!importedResult.isError, JSON.stringify(importedResult));
      await t.test('real public HTTPS attachment download', () => assert(fs.readFileSync(imported, 'utf8').includes('MIT License')));
      publicHttpsVerified = true;
    }
    assert((await call('import_file', { path: imported, file: { file_id: 'fixture', download_url: 'https://example.com/file' } }, undefined, true)).isError);
    const b = await tool('register_conversation', { path: root, title: 'Second conversation' }, 'mac-test-B');
    assert.notEqual(b.thread_id, conversation.thread_id);
    const activity = await tool('read_workspace_activity', { path: root });
    assert(activity.activity.every(a => a.thread_id === conversation.thread_id));
    const mismatch = await call('read_command', { session_id: stdin.session_id }, 'mac-test-B', true);
    assert(mismatch.isError);
    const meta = { 'io.modelcontextprotocol/protocolVersion': '2026-07-28', 'io.modelcontextprotocol/clientCapabilities': { elicitation: {}, extensions: { 'io.modelcontextprotocol/tasks': {} } } };
    const discover = await rpc('server/discover', { _meta: meta });
    assert.equal(discover.result.resultType, 'complete');
    const arguments = { path: fixture, content: 'confirmed', overwrite: true };
    const confirmation = await rpc('tools/call', { name: 'write_file', arguments, _meta: meta });
    assert.equal(confirmation.result.resultType, 'input_required');
    assert(fs.readFileSync(fixture, 'utf8').includes('gamma'));
    const accepted = await rpc('tools/call', { name: 'write_file', arguments, _meta: meta, requestState: confirmation.result.requestState, inputResponses: { confirm: { action: 'accept' } } });
    assert(!accepted.result.isError); assert.equal(fs.readFileSync(fixture, 'utf8'), 'confirmed');
    const task = await rpc('tools/call', { name: 'exec_command', arguments: { cwd: root, cmd: 'sleep 0.3; printf modern-task', yield_time_ms: 0 }, _meta: meta });
    assert.equal(task.result.resultType, 'task');
    await delay(600);
    const completed = await rpc('tasks/get', { taskId: task.result.taskId, _meta: meta });
    assert.equal(completed.result.status, 'completed');
    // Mark recovery only after every expected failure has been observed and checked.
    const lastIssue = await tool('check_task_completion', { path: root });
    const proof = await call('file_info', { path: fixture });
    await tool('update_plan', { path: root,
      explanation: 'Expected failure cases verified; all integration checks passed.',
      resolved_issue_id: lastIssue.last_issue_id,
      recovery_note: 'All intentional refusal/timeout fixtures were inspected; successful file inspection proves the runtime remains healthy.',
      recovery_evidence_id: proof.structuredContent.activity_id,
      plan: [{ step: plan[0].step, status: 'completed', evidence: 'All 28 tools exercised against isolated macOS fixtures.' }] });
    assert.equal((await tool('check_task_completion', { path: root })).can_finish, true);
    assert.equal((await fetch(base)).status, 200);
    assert.equal((await fetch(new URL('/api/snapshot', base), { headers: { Origin: 'https://example.com' } })).status, 403);
    assert.equal((await fetch(new URL('/api/open?target=' + encodeURIComponent(root), base), { method: 'POST' })).status, 403);
    const snapshot = await (await fetch(new URL('/api/snapshot', base))).json();
    assert(snapshot.conversations.length >= 2); assert(snapshot.activity.length > 10);
    const diagnostics = await (await fetch(new URL('/api/diagnostics', base))).json();
    assert.equal(diagnostics.checks.find(c => c.label === '配置自检').status, 'pass');
    assert.equal(diagnostics.checks.find(c => c.label === '隧道就绪').status, 'unavailable');
    assert.deepEqual([...seen].sort(), list.map(x => x.name).sort());
    for (const name of fs.readdirSync(path.join(root, '.state')).filter(name => name.endsWith('.bin'))) {
      assert.equal(fs.statSync(path.join(root, '.state', name)).mode & 0o777, 0o600, 'encrypted state is owner-only');
    }
    t.diagnostic('PASS: every advertised tool invoked, schema validation, legacy/modern negotiation, confirmation, tasks, session isolation, process-tree stop, timeout, same-origin dashboard. Public HTTPS import: ' + (publicHttpsVerified ? 'verified' : 'not verified on this fake/private-DNS network'));
  } finally {
    const term = setTimeout(() => child.kill('SIGTERM'), 3000);
    const kill = setTimeout(() => child.kill('SIGKILL'), 5000);
    let deadline;
    try {
      child.stdin.end();
      await Promise.race([exited, new Promise((_, reject) => {
        deadline = setTimeout(() => reject(Error('Test backend did not stop within 7 seconds')), 7000);
      })]);
    } finally {
      clearTimeout(term); clearTimeout(kill); clearTimeout(deadline);
      rejectPending(Error('Test backend stopped'));
      try {
        // Delete only this disposable item; never read or alter the user's key.
        try { execFileSync('/usr/bin/security', ['delete-generic-password', '-s', stateService, '-a', 'state-v1'], { stdio: 'pipe', timeout: 5000 }); }
        catch (error) { if (error.status !== 44) throw Error('Could not delete the isolated test Keychain item'); }
      } finally { fs.rmSync(root, { recursive: true, force: true }); }
    }
  }
});
