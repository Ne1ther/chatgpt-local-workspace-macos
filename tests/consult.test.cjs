// Real backend integration, including CLI processes while MCP owns state-v1/owner.lock.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const Ajv = require('ajv');
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

test('consultation bridge: bounded reads, access checks, immutable reports and concurrent lock-free CLI', { skip: process.platform !== 'darwin', timeout: 45000 }, async t => {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'local-workspace-check-consult-')));
  const consult = path.join(root, 'consult'), inbox = path.join(root, 'inbox');
  const exe = process.env.WORKSPACE_TEST_EXE || path.resolve(__dirname, '../dist-macos/ChatGPT Codex Workspace.app/Contents/Resources/Backend/workspace-server');
  const env = { ...process.env, WORKSPACE_EPHEMERAL_STATE: '1', WORKSPACE_STATE_DIR: path.join(root, 'state'), WORKSPACE_CONSULT_DIR: consult, CONTROL_PLANE_API_KEY: '', WORKSPACE_TUNNEL_ID: '', WORKSPACE_TUNNEL_HEALTH_FILE: '', CODEX_HOME: path.join(root, 'codex') };
  const child = spawn(exe, ['--mcp'], { stdio: ['pipe', 'pipe', 'pipe'], env });
  let seq = 0, buffer = '', stderr = ''; const pending = new Map();
  const exited = new Promise(resolve => child.once('close', resolve));
  child.stderr.on('data', b => { stderr += b; });
  child.stdout.on('data', b => {
    buffer += b; let at;
    while ((at = buffer.indexOf('\n')) >= 0) {
      const reply = JSON.parse(buffer.slice(0, at)); buffer = buffer.slice(at + 1);
      const p = pending.get(reply.id); if (p) { pending.delete(reply.id); clearTimeout(p.timer); p.resolve(reply); }
    }
  });
  const rpc = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++seq;
    pending.set(id, { resolve, timer: setTimeout(() => { pending.delete(id); reject(Error('RPC timeout: ' + stderr.slice(-1000))); }, 8000) });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
  const schemas = new Map();
  const tool = async (name, args, error = false) => {
    const reply = await rpc('tools/call', { name, arguments: args, _meta: { 'openai/session': 'consult-test' } });
    assert(!reply.error, JSON.stringify(reply)); assert.equal(reply.result.isError, error, JSON.stringify(reply.result));
    const validate = schemas.get(name); assert(validate(reply.result.structuredContent), JSON.stringify(validate.errors));
    return reply.result.structuredContent.result;
  };
  const cli = (args, code = 0) => {
    const r = spawnSync(exe, args, { env, encoding: 'utf8', timeout: 7000 });
    assert(!r.error, String(r.error)); assert.equal(r.status, code, r.stderr + r.stdout);
    assert(!r.stderr.includes('owner.lock'), r.stderr); return JSON.parse(r.stdout);
  };
  const brief = path.join(root, 'brief.md'), data = path.join(root, '中文 data.txt');
  fs.writeFileSync(brief, '# Evidence\nRead all files.\n'); fs.writeFileSync(data, 'a'.repeat(1023) + '中'.repeat(2000) + '\nend\n');
  try {
    await rpc('initialize');
    const list = (await rpc('tools/list')).result.tools;
    for (const d of list) schemas.set(d.name, new Ajv({ strict: false }).compile(d.outputSchema));
    await t.test('public metadata and real MCP owner lock', async () => {
      assert.equal(list.length, 25);
      assert.deepEqual(list.find(x => x.name === 'read_research_bundle').annotations, { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false });
      assert.deepEqual(list.find(x => x.name === 'submit_pro_report').annotations, { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false });
      assert(fs.existsSync(path.join(root, 'state', 'owner.lock')));
      // A second MCP process fails, demonstrating that the first process really owns the lock.
      const second = spawnSync(exe, ['--mcp'], { env, input: '', encoding: 'utf8', timeout: 5000 });
      assert.notEqual(second.status, 0); assert.match(second.stderr, /owner|already|state|lock/i);
    });
    let staged, report;
    await t.test('stage/status/list work while owner.lock is held', async () => {
      staged = cli(['--stage-consult', '--id', 'review-1', '--inbox', inbox, '--title', 'Test consultation', '--instructions', 'Evaluate evidence.', '--brief', brief, '--file', data]);
      assert(staged.ok); assert.equal(staged.file_count, 2); assert.match(staged.web_pro_prompt, /read_research_bundle.*review-1/); assert.match(staged.web_pro_prompt, /submit_pro_report/);
      assert.equal(cli(['--consult-status', '--id', 'review-1']).status, 'staged');
      assert.equal(cli(['--consult-status']).status, 'staged');
      assert.equal(cli(['--consult-list'])[0].consult_id, 'review-1');
      assert.equal(fs.statSync(consult).mode & 0o777, 0o700);
      for (const folder of ['sessions', 'receipts']) assert.equal(fs.statSync(path.join(consult, folder)).mode & 0o777, 0o700);
      assert.equal(cli(['--consult-status', '--id', 'review-1', '--wait-seconds', '1'], 2).status, 'staged');
      cli(['--stage-consult', '--id', 'review-1', '--inbox', inbox, '--file', brief], 1);
      cli(['--stage-consult', '--id', '../escape', '--inbox', inbox, '--file', brief], 1);
      cli(['--stage-consult', '--id', 'missing', '--inbox', inbox, '--file', path.join(root, 'missing')], 1);
      cli(['--consult-status', '--wait-seconds', '3601'], 1);
    });
    await t.test('bundle SHA, full-file facts, UTF-8 truncation and status', async () => {
      const read = await tool('read_research_bundle', { consult_id: 'review-1', max_bytes_per_file: 1024, total_max_bytes: 4096 });
      assert.equal(read.file_count, 2); assert.equal(read.bundle_sha256, staged.bundle_sha256); assert.equal(read.title, 'Test consultation'); assert.equal(read.instructions, 'Evaluate evidence.');
      assert.equal(read.truncated_count, 1); assert.equal(read.files[1].content, 'a'.repeat(1023)); assert.equal(read.files[1].line_count, 2);
      assert.equal(read.total_bytes, read.files.reduce((n, x) => n + Buffer.byteLength(x.content), 0));
      for (const f of read.files) { assert.equal(f.sha256, sha(fs.readFileSync(f.path))); assert.equal(f.size_bytes, fs.statSync(f.path).size); }
      const status = cli(['--consult-status', '--id', 'review-1']); assert.equal(status.status, 'reading'); assert.equal(status.bundle_sha256, read.bundle_sha256); assert(status.thread_id); assert(status.last_read_at);
      const fromManifest = await tool('read_research_bundle', { bundle_path: staged.bundle_path }); assert.equal(fromManifest.file_count, 2); assert.equal(fromManifest.consult_id, 'review-1');
      assert.equal((await tool('read_research_bundle', { bundle_path: brief })).file_count, 1);
      assert.equal((await tool('read_research_bundle', { bundle_path: JSON.stringify({ paths: [brief] }), paths: [brief] })).file_count, 1);
      await tool('read_research_bundle', { paths: [brief], max_bytes_per_file: 1023 }, true);
      await tool('read_research_bundle', { paths: Array(21).fill(brief) }, true);
      const budget = await tool('read_research_bundle', { paths: [data, brief], max_bytes_per_file: 262144, total_max_bytes: 4096 }); assert(budget.total_bytes <= 4096); assert.equal(budget.truncated_count, 2);
      await tool('read_research_bundle', { consult_id: 'explicit-paths', paths: [brief] }); assert.equal(cli(['--consult-status', '--id', 'explicit-paths']).status, 'reading');
    });
    await t.test('access boundary matches read_file: absolute paths, denied OS access and staged paths', async () => {
      await tool('read_research_bundle', { paths: ['relative.md'] }, true);
      await tool('read_research_bundle', { consult_id: '../escape' }, true);
      const denied = path.join(root, 'denied.txt'); fs.writeFileSync(denied, 'private'); fs.chmodSync(denied, 0);
      try {
        assert.equal((await tool('read_research_bundle', { paths: [denied] }, true)).error_code, 'ACCESS_DENIED');
        const manifest = path.join(root, 'denied.bundle.json'); fs.writeFileSync(manifest, JSON.stringify({ files: [{ path: denied }] }));
        assert.equal((await tool('read_research_bundle', { bundle_path: manifest }, true)).error_code, 'ACCESS_DENIED');
      } finally { fs.chmodSync(denied, 0o600); }
      const blocked = path.join(root, 'blocked'); fs.mkdirSync(blocked); fs.chmodSync(blocked, 0o500);
      try { assert.equal((await tool('submit_pro_report', { consult_id: 'blocked', inbox_dir: blocked, content: '# Report' }, true)).error_code, 'ACCESS_DENIED'); }
      finally { fs.chmodSync(blocked, 0o700); }
      await tool('submit_pro_report', { consult_id: 'relative', inbox_dir: 'relative', content: '# Report' }, true);
      await tool('submit_pro_report', { consult_id: '../../escape', inbox_dir: inbox, content: '# Report' }, true);
      await tool('submit_pro_report', { consult_id: 'no-inbox', content: '# Report' }, true);
      await tool('submit_pro_report', { consult_id: 'empty', inbox_dir: inbox, content: '  \n' }, true);
      await tool('submit_pro_report', { consult_id: 'bad-json', inbox_dir: inbox, content: '# Report', structured_json: '{bad' }, true);
      assert(!fs.existsSync(path.join(inbox, 'bad-json.md')));
    });
    await t.test('complete report, receipt SHA, immutable retry and repeated timestamp collisions', async () => {
      const content = '# Complete report\n\n结论与证据。\n';
      report = await tool('submit_pro_report', { consult_id: 'review-1', content, summary: 'Complete', structured_json: '{"verdict":"done"}' });
      assert.equal(report.sha256, sha(Buffer.from(content))); assert.equal(report.byte_length, Buffer.byteLength(content)); assert.equal(report.line_count, 3);
      assert.equal(fs.readFileSync(report.report_path, 'utf8'), content); assert.equal(JSON.parse(fs.readFileSync(report.structured_json_path)).verdict, 'done');
      assert.deepEqual(JSON.parse(fs.readFileSync(report.receipt_path)), report);
      assert.deepEqual(JSON.parse(fs.readFileSync(path.join(consult, 'receipts', 'review-1.json'))), report);
      assert.deepEqual(await tool('submit_pro_report', { consult_id: 'review-1', content }), report);
      for (let i = 0; i < 3; i++) {
        const next = await tool('submit_pro_report', { consult_id: 'review-1', content: content + i });
        assert.notEqual(next.report_path, report.report_path); assert.match(path.basename(next.report_path), /^review-1__\d{8}T\d{6}Z/);
        assert.equal(fs.readFileSync(report.report_path, 'utf8'), content); assert.equal(next.sha256, sha(fs.readFileSync(next.report_path)));
        assert.deepEqual(await tool('submit_pro_report', { consult_id: 'review-1', content: content + i }), next);
      }
      // Retry a timestamped collision after the clock changes.
      const delayed = await tool('submit_pro_report', { consult_id: 'review-1', content: content + 'delayed' });
      await new Promise(resolve => setTimeout(resolve, 1100));
      assert.deepEqual(await tool('submit_pro_report', { consult_id: 'review-1', content: content + 'delayed' }), delayed);
      const preexisting = path.join(inbox, 'same.md'); fs.writeFileSync(preexisting, '# Same bytes');
      const same = await tool('submit_pro_report', { consult_id: 'same', inbox_dir: inbox, content: '# Same bytes' }); assert.equal(same.report_path, preexisting);
      const reserved = path.join(inbox, 'reserved.receipt.json'); fs.writeFileSync(reserved, 'preserve this receipt');
      const safe = await tool('submit_pro_report', { consult_id: 'reserved', inbox_dir: inbox, content: '# New report' });
      assert.notEqual(safe.receipt_path, reserved); assert.equal(fs.readFileSync(reserved, 'utf8'), 'preserve this receipt');
      const complete = cli(['--consult-status', '--id', 'review-1', '--wait-seconds', '1']); assert.equal(complete.status, 'completed'); assert(complete.receipt); assert.equal(cli(['--consult-status']).status, 'completed');
      const standalone = await tool('submit_pro_report', { inbox_dir: path.join(root, 'new-inbox'), content: '# Standalone' }); assert.match(standalone.consult_id, /^pro-\d{8}T\d{6}Z$/);
    });
    await t.test('waiting CLI sees report completion without locking out MCP', async () => {
      cli(['--stage-consult', '--id', 'wait-1', '--inbox', inbox, '--file', brief]);
      const waiter = spawn(exe, ['--consult-status', '--id', 'wait-1', '--wait-seconds', '5'], { env }); let out = '', err = '';
      waiter.stdout.on('data', b => { out += b; }); waiter.stderr.on('data', b => { err += b; });
      const done = new Promise(resolve => waiter.once('close', resolve));
      await tool('submit_pro_report', { consult_id: 'wait-1', content: '# Wait done' });
      assert.equal(await done, 0, err); assert.equal(JSON.parse(out).status, 'completed');
    });
  } finally {
    child.stdin.end(); await exited;
    for (const p of pending.values()) clearTimeout(p.timer);
    fs.rmSync(root, { recursive: true, force: true });
  }
});
