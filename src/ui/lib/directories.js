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
    if (needle && ![path, title, conversation.title || ''].some(value => value.toLocaleLowerCase().includes(needle))) continue;
    if (!groups.has(path)) groups.set(path, { id: path, path, title, conversations: [] });
    groups.get(path).conversations.push(conversation);
  }
  // Keep server recency order, with conversations lacking a directory at the end.
  return [...groups.values()].sort((a, b) => Number(!a.path) - Number(!b.path));
}
