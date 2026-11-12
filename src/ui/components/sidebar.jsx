import { useMemo, useState } from 'react';
import { cn } from 'cn';
import { Button } from '@/components/ui/button';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';
import { Icon, SpinIcon } from './icons.jsx';
import { since } from '@/lib/format.js';
import { groupDirectories, conversationLabel, conversationSummary } from '@/lib/directories.js';

// The app mark, hand-tuned at 20px: an obsidian-titanium rounded tile holding the Conduit Vault —
// left local bracket "[", top-right cloud portal "┐", sapphire ">" chevron, and cyan "_" live baseline.
const MARK = 'data:image/svg+xml,' + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 20 20'><rect x='1' y='1' width='18' height='18' rx='4.5' fill='#10131c'/><rect x='1.5' y='1.5' width='17' height='17' rx='4' fill='none' stroke='#a8c4ff' stroke-opacity='.22'/><path d='M6.8 5.2H5.4a1.2 1.2 0 0 0-1.2 1.2v7.2a1.2 1.2 0 0 0 1.2 1.2h1.4' fill='none' stroke='#eef3fb' stroke-width='1.55' stroke-linecap='round' stroke-linejoin='round'/><path d='M12.4 5.2h2.2a1.2 1.2 0 0 1 1.2 1.2v2.2' fill='none' stroke='#8cb2f0' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/><path d='M8.5 7.4 11.3 10l-2.8 2.6' fill='none' stroke='#3d8bff' stroke-width='1.65' stroke-linecap='round' stroke-linejoin='round'/><line x1='11.8' y1='14.8' x2='15.6' y2='14.8' stroke='#66ccff' stroke-width='1.65' stroke-linecap='round'/></svg>");

// Right side of a conversation: a spinner while something runs, else the failed count.
function Badge({ stats, total }) {
  if (!stats) return null;
  if (stats.running > 0) return <span className="thread-meta" title={stats.running + ' 个调用进行中'}><SpinIcon size={14} /></span>;
  if (total) return stats.calls ? <span className="thread-meta tabular">{stats.calls}</span> : null;
  if (stats.failed > 0) return <span className="thread-meta failed tabular" title={stats.failed + ' 次调用失败'}><Icon name="circleAlert" size={12} />{stats.failed}</span>;
  return null;
}

// One quiet meta line under the title: source · last activity.
function Sub({ source, stats, now }) {
  const parts = [];
  if (source) parts.push(<span key="s">{source}</span>);
  if (stats && stats.lastAt) parts.push(<span key="t" className="tabular">{since(stats.lastAt, now) === '刚刚' ? '刚刚' : since(stats.lastAt, now) + '前'}</span>);
  if (!parts.length) return null;
  return <span className="thread-sub">{parts.map((part, index) => [index ? <i key={'d' + index} className="sep">·</i> : null, part])}</span>;
}

function Row({ id, title, icon, initial, active, stats, total, now, rail, onClick, pressed = true, source, sub = false, subtitle, trail = null }) {
  const button = (
    <button type="button" id={id} className={cn('thread', active && 'active', sub && 'two-line')} aria-label={title}
      title={rail ? undefined : title} aria-pressed={pressed ? !!active : undefined} onClick={onClick}>
      <span className="thread-glyph">{icon ? <Icon name={icon} /> : <><Icon name="chat" className="glyph-icon" /><span className="thread-initial">{initial}</span></>}</span>
      <span className="thread-text">
        <b>{title}</b>
        {subtitle ? <span className="thread-sub">{subtitle}</span> : sub ? <Sub source={source} stats={stats} now={now} /> : null}
      </span>
      {trail || <Badge stats={stats} total={total} />}
    </button>
  );
  if (!rail) return button;
  // Collapsed to the icon rail, the name only survives as a tooltip.
  return (
    <Tooltip>
      <TooltipTrigger asChild>{button}</TooltipTrigger>
      <TooltipContent side="right">{title}</TooltipContent>
    </Tooltip>
  );
}

// Conversation switcher. Top: all conversations (its row lines up with the header's title row;
// the browser page adds the brand above it), then the registered ones, newest activity first;
// the unassigned bucket and diagnostics stay at the bottom, the version quietly on the
// diagnostics row. The collapse toggle lives in the main header so it never needs a row here.
export function Sidebar({ conversations, thread, collapsed, rail: railAuto, loaded, stats, sources, now, version, onSelect, onSetup, onDiagnostics }) {
  const pick = id => onSelect(id ? 'thread=' + encodeURIComponent(id) : '');
  const list = conversations || [];
  const rail = collapsed || railAuto;
  const [query, setQuery] = useState('');
  const [closed, setClosed] = useState(() => new Set());
  const [expandedGroups, setExpandedGroups] = useState(() => new Set());
  const directories = useMemo(() => groupDirectories(list, rail ? '' : query), [list, query, rail]);
  const toggleDirectory = id => setClosed(previous => {
    const next = new Set(previous);
    if (next.has(id)) next.delete(id); else next.add(id);
    return next;
  });
  return (
    <aside className="sidebar" aria-label="工作区">
      <div className="sidebar-head">
        <span className="brand">{MARK ? <img className="brand-mark" src={MARK} alt="" aria-hidden="true" /> : null}本地工作区</span>
      </div>
      <nav id="threads" className="thread-list" aria-label="对话列表">
        <Row title="全部操作" icon="layers" active={thread === ''} stats={stats && stats['']} total now={now} rail={rail} onClick={() => pick('')} />
        <div className="section-label">
          <span>工作目录{directories.length ? <em className="tabular">{directories.length}</em> : null}</span>
          <Button id="setup-toggle" variant="ghost" size="icon-xs" aria-label="登记对话" title="登记对话" onClick={onSetup}><Icon name="plus" size={14} /></Button>
        </div>
        {!rail && list.length > 0 ? <label className="directory-search"><Icon name="search" size={14} /><input
          aria-label="搜索目录或对话" placeholder="搜索目录或对话" value={query} onChange={event => setQuery(event.target.value)} /></label> : null}
        {directories.map(directory => {
          const expanded = expandedGroups.has(directory.id) || !!query.trim();
          const visible = expanded ? directory.conversations : directory.conversations.filter((item, index) => index < 3 || item.thread_id === thread);
          const remaining = directory.conversations.length - visible.length;
          return <section className="directory-group" key={directory.id}>
          {!rail ? <button type="button" className="directory-toggle" aria-expanded={!closed.has(directory.id)}
            title={directory.path || '登记对话时可关联本地文件夹'} onClick={() => toggleDirectory(directory.id)}>
            <Icon name={directory.path ? 'folder' : 'inbox'} size={16} />
            <span className="directory-label"><b>{directory.title}</b><span>{directory.path || '对话尚未关联文件夹'}</span></span>
            <span className="directory-count tabular">{directory.conversations.length}</span><Icon name="chevronRight" size={12} />
          </button> : null}
          {rail || !closed.has(directory.id) ? visible.map(item => (
          <Row key={item.thread_id} title={conversationLabel(item, directory.conversations)} icon="chat" sub subtitle={conversationSummary(item)}
            source={sources[item.thread_id]} active={item.thread_id === thread} stats={stats && stats[item.thread_id]} now={now} rail={rail}
            onClick={() => pick(item.thread_id)} />
          )) : null}
          {!rail && !query.trim() && !closed.has(directory.id) && directory.conversations.length > 3 && (expanded || remaining > 0) ? <button type="button" className="conversation-more" aria-expanded={expanded}
            onClick={() => setExpandedGroups(previous => { const next = new Set(previous); if (next.has(directory.id)) next.delete(directory.id); else next.add(directory.id); return next; })}>
            {expanded ? '收起较早会话' : `显示其余 ${remaining} 个会话`}
          </button> : null}
        </section>})}
        {query && !directories.length ? <p className="thread-empty">没有匹配的目录或对话</p> : null}
        {loaded && list.length === 0 ? <p className="thread-empty">还没有登记的对话。点 + 登记后，调用会按对话归类。</p> : null}
      </nav>
      <div className="sidebar-foot">
        <Row id="unassigned" title="未归属操作" icon="inbox" active={thread === 'unassigned'} stats={stats && stats.unassigned} now={now} rail={rail} onClick={() => pick('unassigned')} />
        <Row id="diagnostics" title="诊断连接" icon="activity" pressed={false} rail={rail} onClick={onDiagnostics}
          trail={version ? <span id="footer" className="thread-meta version tabular" title={'本地工作区版本 ' + version}>v{version}</span> : null} />
      </div>
    </aside>
  );
}
