// Consultation helpers shared by the consult band, the report reader and the timeline:
// one place for the three stages, the Web Pro instruction and the T3 receipt text.
import { bytes } from './format.js';

export const CONSULT_TOOLS = new Set(['read_research_bundle', 'submit_pro_report']);

// The server reports consult calls as `info` rows (label/value pairs) and may also carry the raw
// fields; read either, so new fields (offset_bytes, next_offset_bytes…) show up without a UI change.
export const INFO_LABELS = {
  title: ['资料包', '标题', '报告标题'], consult_id: ['咨询编号', 'consult_id'], file_count: ['文件数'], truncated_count: ['截断文件数'],
  bundle_sha256: ['资料包 SHA256', 'SHA256'], total_bytes: ['读取字节', '本次读取', 'total_bytes'],
  offset_bytes: ['起始偏移', '偏移', '续读位置', 'offset_bytes'], next_offset_bytes: ['下次偏移', '续读偏移', '下一段', 'next_offset_bytes'],
  report_path: ['报告', '报告文件'], receipt_path: ['收据', '回执'], sha256: ['SHA256', '报告 SHA256'],
  line_count: ['行数'], byte_length: ['字节', '报告大小'], summary: ['摘要'], status: ['状态'],
};
export function consultField(detail, key) {
  if (!detail) return undefined;
  for (const source of [detail, detail.result, detail.receipt]) {
    if (source && source[key] !== undefined && source[key] !== null && source[key] !== '') return source[key];
  }
  const labels = INFO_LABELS[key] || [key];
  for (const label of labels) {
    const row = (detail.info || []).find(item => item && item.label === label && item.value !== undefined && item.value !== null && item.value !== '');
    if (row) return row.value;
  }
  return undefined;
}
export const consultNumber = (detail, key) => { const value = Number(consultField(detail, key)); return Number.isFinite(value) ? value : 0; };

export const CONSULT_STAGES = [
  { key: 'staged', label: '已打包' },
  { key: 'reading', label: 'Web Pro 读取中' },
  { key: 'completed', label: '报告已归档' },
];

export const stageIndex = status => CONSULT_STAGES.findIndex(stage => stage.key === status);
export const stageLabel = status => (CONSULT_STAGES[stageIndex(status)] || {}).label || '状态未知';

// Newest activity first: archived reports, then reads, then staging.
export const consultTime = consult => {
  const times = [consult?.receipt?.created_at, consult?.last_read_at, consult?.staged_at].map(value => Date.parse(value || '')).filter(Number.isFinite);
  return times.length ? Math.max(...times) : 0;
};

export function consultsFor(snapshot, thread) {
  const list = Array.isArray(snapshot?.consults) ? snapshot.consults.filter(item => item && item.consult_id) : [];
  return list.filter(item => !thread || !item.thread_id || item.thread_id === 'unassigned' || item.thread_id === thread).sort((a, b) => consultTime(b) - consultTime(a));
}

// What the user pastes into ChatGPT Web Pro. The server's own prompt wins when present.
export function proPrompt(consult) {
  if (consult?.web_pro_prompt) return consult.web_pro_prompt;
  const id = consult?.consult_id || '';
  return [
    '请使用 ChatGPT Codex Workspace 连接器完成这次研究咨询：',
    '1. 调用 read_research_bundle，参数 consult_id: "' + id + '"，完整读取资料包；若返回 next_offset_bytes，请用 offset_bytes 继续读取直到读完。',
    consult?.instructions ? '2. 按资料包说明完成研究：' + consult.instructions : '2. 按资料包内的说明完成研究。',
    '3. 调用 submit_pro_report，参数 consult_id: "' + id + '"，提交完整的 Markdown 报告（含标题与摘要）。',
  ].join('\n');
}

// Plain-text receipt for handing the archived report back to T3 Code.
export function t3Receipt(consult, report) {
  const receipt = { ...(consult?.receipt || {}), ...(report || {}) };
  const lines = ['[Web Pro 报告回执]', 'consult_id: ' + (consult?.consult_id || '')];
  const title = report?.title || consult?.title;
  if (title) lines.push('标题: ' + title);
  if (receipt.report_path) lines.push('报告: ' + receipt.report_path);
  if (receipt.sha256) lines.push('SHA256: ' + receipt.sha256);
  const size = [receipt.line_count != null ? receipt.line_count + ' 行' : '', receipt.byte_length != null ? bytes(receipt.byte_length) : ''].filter(Boolean).join(' · ');
  if (size) lines.push('大小: ' + size);
  if (receipt.created_at) lines.push('归档时间: ' + receipt.created_at);
  if (consult?.bundle_sha256) lines.push('资料包 SHA256: ' + consult.bundle_sha256);
  if (receipt.summary) lines.push('摘要: ' + receipt.summary);
  lines.push('', '请读取上面的报告文件，核对 SHA256 后继续任务。');
  return lines.join('\n');
}
