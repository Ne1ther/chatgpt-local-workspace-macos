#!/usr/bin/env node
const { spawnSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { isAbsolute, resolve, dirname } = require('node:path');

const defaultServer = '/Applications/ChatGPT Codex Workspace.app/Contents/Resources/Backend/workspace-server';
const [id, seconds = '0', ...extra] = process.argv.slice(2);

function readJSON(path) {
  if (typeof path !== 'string' || !isAbsolute(path)) throw Error('Expected an absolute receipt or bundle path');
  return JSON.parse(readFileSync(path, 'utf8'));
}

function verify() {
  if (!id || !/^[A-Za-z0-9._-]{1,80}$/.test(id) || id === '.' || id === '..' ||
      !/^\d+$/.test(seconds) || Number(seconds) > 3600 || extra.length) {
    throw Error('Usage: node scripts/verify-pro-consult.cjs <consult_id> [wait_seconds: 0..3600]');
  }
  const server = process.env.WORKSPACE_TEST_EXE || defaultServer;
  const response = spawnSync(server, ['--consult-status', '--id', id, '--wait-seconds', seconds], {
    encoding: 'utf8',
    timeout: (Number(seconds) + 10) * 1000,
  });
  if (response.error) throw response.error;
  if (response.status !== 0 && response.status !== 2) {
    throw Error(response.stdout.trim() || response.stderr.trim() || 'Unable to query consultation');
  }
  const session = JSON.parse(response.stdout);
  if (session.consult_id !== id) throw Error('Consultation ID does not match');
  if (session.status !== 'completed') {
    if (session.status !== 'staged' && session.status !== 'reading') throw Error('Consultation was not staged');
    process.exitCode = 2;
    return { ok: false, consult_id: id, status: session.status, last_read_at: session.last_read_at ?? null };
  }
  if (!session.last_read_at) throw Error('Report exists but the bundle has no recorded read');
  const manifest = readJSON(session.bundle_path);
  if (manifest.consult_id !== id || manifest.bundle_sha256 !== session.bundle_sha256) {
    throw Error('The bundle read by Web Pro does not match the staged manifest');
  }
  const receipt = session.receipt;
  if (!receipt || receipt.consult_id !== id || !/^[0-9a-f]{64}$/.test(receipt.sha256 ?? '')) {
    throw Error('Missing or invalid report receipt');
  }
  if (![receipt.report_path, receipt.receipt_path].every(file =>
    typeof file === 'string' && isAbsolute(file) && dirname(resolve(file)) === resolve(manifest.inbox_dir))) {
    throw Error('Report and receipt must be in the staged inbox');
  }
  const onDisk = readJSON(receipt.receipt_path);
  const bytes = readFileSync(receipt.report_path);
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  if (onDisk.consult_id !== id || onDisk.report_path !== receipt.report_path ||
      onDisk.sha256 !== sha256 || receipt.sha256 !== sha256 ||
      onDisk.byte_length !== bytes.length || receipt.byte_length !== bytes.length) {
    throw Error('Report bytes and receipt do not match');
  }
  return {
    ok: true, consult_id: id, status: 'verified',
    bundle_sha256: session.bundle_sha256, last_read_at: session.last_read_at,
    report_path: receipt.report_path, receipt_path: receipt.receipt_path,
    sha256, byte_length: bytes.length, summary: receipt.summary,
  };
}

try {
  console.log(JSON.stringify(verify()));
} catch (error) {
  console.log(JSON.stringify({ ok: false, consult_id: id ?? null, status: 'error', error: error.message }));
  process.exitCode = 1;
}
