// Directory identity is the complete path, never just its last component.
// Keep POSIX case sensitivity and preserve drive roots for the shared Windows UI.
export function directoryPath(path) {
  if (!path) return '';
  let value = String(path);
  if (/^(?:[a-z]:[\\/]|\\\\)/i.test(value)) value = value.replace(/\\/g, '/');
  if (value === '/' || /^[a-z]:\/$/i.test(value)) return value;
  return value.replace(/\/+$/, '');
}

export function groupDirectories(conversations, query = '') {
  const groups = new Map(), needle = query.trim().toLocaleLowerCase();
  for (const conversation of conversations || []) {
    const path = directoryPath(conversation.path);
    const title = path ? path.split('/').filter(Boolean).pop() || path : '未设置目录';
    if (needle && ![path, title, conversationLabel(conversation), conversationIdentity(conversation)].some(value => value.toLocaleLowerCase().includes(needle))) continue;
    if (!groups.has(path)) groups.set(path, { id: path, path, title, conversations: [] });
    groups.get(path).conversations.push(conversation);
  }
  const recency = row => Date.parse(row.stats?.last_at || row.created_at || '') || 0;
  for (const group of groups.values()) group.conversations.sort((a, b) => recency(b) - recency(a));
  return [...groups.values()].sort((a, b) => Number(!a.path) - Number(!b.path) || Math.max(...b.conversations.map(recency)) - Math.max(...a.conversations.map(recency)));
}

export const conversationCode = row => String(row.thread_id || '').replace(/^thread-/, '').slice(-6).toUpperCase();
export const conversationSource = row => row.source === 'codex' ? 'Codex' : row.source === 'chatgpt' ? 'ChatGPT' : '本地会话';
export function conversationDate(row) {
  const date = new Date(row.created_at || '');
  if (!Number.isFinite(date.getTime())) return '';
  const pad = value => String(value).padStart(2, '0');
  return `${pad(date.getMonth() + 1)}/${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}
export function conversationLabel(row) {
  if (row.display_title) return row.display_title;
  const directory = directoryPath(row.path).split('/').filter(Boolean).pop();
  const placeholder = !row.title || row.title === directory || ['ChatGPT', 'ChatGPT 对话'].includes(row.title);
  return placeholder ? '未命名会话 #' + conversationCode(row) : row.title;
}
export const conversationIdentity = row => '#' + conversationCode(row) + ' · ' + conversationSource(row) + (conversationDate(row) ? ' · ' + conversationDate(row) : '');
export const conversationSummary = row => [
  conversationSource(row),
  conversationDate(row),
  typeof row.stats?.calls === 'number' ? (row.stats.calls ? row.stats.calls + ' 次' : '暂无操作') : '',
].filter(Boolean).join(' · ');
