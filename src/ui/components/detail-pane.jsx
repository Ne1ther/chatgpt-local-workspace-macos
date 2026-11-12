import { useState } from 'react';
import { PathLink } from './path-link.jsx';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { DetailViews, Diff } from './views.jsx';
import { CodeBlock } from './code-block.jsx';
import { Icon, SpinIcon, fileIcon } from './icons.jsx';
import { duration, splitPath, stamp } from '@/lib/format.js';
import { titleOf } from '@/lib/labels.js';
import { isRunning, liveElapsed, staleServer, stateText } from '@/lib/rows.js';
import { iconOf } from '@/lib/phrase.js';

// W3C traceparent is "version-traceid-spanid-flags"; show just enough of the trace id to correlate.
const traceShort = value => {
  const parts = String(value).split('-');
  return (parts.length >= 2 ? parts[1] : parts[0]).slice(0, 8);
};

export const metaOf = (row, now) => {
  const running = isRunning(row);
  return [stateText(row), '开始 ' + stamp(row.started_at), '耗时 ' + duration(liveElapsed(row, now)), running && !/进行|运行/.test(stateText(row)) ? '仍在运行' : '', row.trace ? 'trace ' + traceShort(row.trace) : ''].filter(Boolean).join(' · ');
};

export const Empty = ({ icon = 'info', title, hint, children, id, tone }) => (
  <div className={'empty' + (tone ? ' ' + tone : '')} id={id}>
    <span className="empty-icon"><Icon name={icon} size={20} /></span>
    <div className="empty-title">{title}</div>
    {hint ? <div className="empty-hint">{hint}</div> : null}
    {children ? <div className="empty-actions">{children}</div> : null}
  </div>
);

// What one call actually did: shared by the inline expansion and the right inspector.
export function DetailBody({ row, now, snapshot, inline }) {
  const detail = row.detail;
  return (
    <>
      {detail && detail.is_error && detail.error ? (
        <div className="alert">
          <span className="mark"><Icon name="circleAlert" size={14} /></span>
          <div>{detail.error}{detail.next_action ? <p className="recovery-hint">{detail.next_action}</p> : null}</div>
        </div>
      ) : null}
      <DetailViews row={row} now={now} />
      {!detail
        ? <Empty title="这次调用没有结构化详情" hint={staleServer(snapshot)
            ? '当前服务端是旧版本，没有返回文件、行号与命令输出。更新本地工作区插件并重启后，这里会显示每次调用实际做了什么。'
            : '调用返回后这里会显示它所做的事。'} />
        : null}
      {detail && detail.target && !['read', 'image', 'command'].includes(detail.kind)
        ? <div className="detail-foot" title={detail.target}><PathLink value={detail.target} /></div>
        : null}
      {!inline && (detail?.change_id || row?.id)
        ? (
          <details className="evidence">
            <summary>执行证据</summary>
            {row?.id ? <p>活动 ID：{row.id}</p> : null}
            {detail?.before_sha256 ? <p className="mono">修改前：{detail.before_sha256}<br />修改后：{detail.after_sha256}</p> : null}
            {detail?.change_id ? <p>文件恢复记录 ID：{detail.change_id}。可用检查器顶部的「还原」先预览再撤销此记录；应用前会核对文件是否已被其他操作修改，命令产生的外部效果不在恢复范围内。</p> : null}
          </details>
        )
        : null}
    </>
  );
}

// Local endpoints answer JSON, but a proxy or crash page may not: keep the real status.
async function readJson(response) {
  const text = await response.text();
  try { return text ? JSON.parse(text) : {}; } catch { return {}; }
}
const isConflict = error => error.code === 'UNDO_CONFLICT' || /UNDO_CONFLICT/.test(error.message || '');

// 「还原」: preview first (apply=0), then apply=1 only after the user confirms. The server
// re-checks every file hash on both calls, so a file edited since this call is never overwritten.
function RevertChange({ changeId, onNotice, onRefresh }) {
  const [open, setOpen] = useState(false);
  const [phase, setPhase] = useState('idle'); // loading | preview | applying | conflict | error
  const [preview, setPreview] = useState(null);
  const [message, setMessage] = useState('');
  const call = async apply => {
    const bootstrap = await fetch('/api/local-actions', { cache: 'no-store', signal: AbortSignal.timeout(5000) });
    const access = await readJson(bootstrap);
    if (!bootstrap.ok || !access.token) throw Error('无法读取本地操作凭证：' + (access.error || '服务返回 HTTP ' + bootstrap.status));
    const response = await fetch('/api/restore-change?id=' + encodeURIComponent(changeId) + '&apply=' + (apply ? 1 : 0), {
      method: 'POST', cache: 'no-store', headers: { 'X-Workspace-Token': access.token }, signal: AbortSignal.timeout(15000),
    });
    const result = await readJson(response);
    if (!response.ok || result.error) {
      const error = Error(result.error || result.message || '服务返回 HTTP ' + response.status);
      error.code = result.code || result.error_code || '';
      throw error;
    }
    return result;
  };
  const fail = caught => {
    setMessage(caught.name === 'TimeoutError' ? '本地服务没有及时响应，请稍后重试。' : caught.message);
    setPhase(isConflict(caught) ? 'conflict' : 'error');
  };
  const start = async () => {
    setOpen(true); setPhase('loading'); setPreview(null); setMessage('');
    try { setPreview(await call(false)); setPhase('preview'); } catch (caught) { fail(caught); }
  };
  const confirm = async () => {
    setPhase('applying');
    try {
      await call(true);
      setOpen(false);
      onNotice?.('已安全还原文件改动');
      onRefresh?.();
    } catch (caught) { fail(caught); }
  };
  const files = (preview && preview.files) || [];
  return (
    <>
      <Button id="revert-change" variant="ghost" size="sm" title="校验文件哈希并预览还原此改动" onClick={start}><Icon name="undo" size={14} />还原</Button>
      <Dialog open={open} onOpenChange={value => { if (phase !== 'applying') setOpen(value); }}>
        <DialogContent id="revert-dialog" className="revert-dialog">
          <DialogHeader>
            <DialogTitle>{phase === 'conflict' ? '无法安全还原' : '还原这次文件改动？'}</DialogTitle>
            <DialogDescription>
              {phase === 'conflict'
                ? '文件在这次改动之后又被修改过。为避免覆盖新的内容，已拒绝自动还原。'
                : '会把下列文件恢复到这次调用之前的内容。应用前会再次核对文件哈希；命令产生的外部效果不在还原范围内。'}
            </DialogDescription>
          </DialogHeader>
          {phase === 'loading' ? <div className="report-state"><SpinIcon size={14} />正在校验文件哈希并生成还原预览…</div> : null}
          {phase === 'conflict' || phase === 'error'
            ? <div className="alert" id="revert-alert"><span className="mark"><Icon name="circleAlert" size={14} /></span><div>{phase === 'conflict' ? '检测到冲突（UNDO_CONFLICT）：' : '还原失败：'}<span className="mono">{message}</span>{phase === 'conflict' ? <p className="recovery-hint">请先检查该文件的当前内容；如仍需撤销，可在原对话中让助手基于最新内容手动修改。</p> : null}</div></div>
            : null}
          {(phase === 'preview' || phase === 'applying') && files.length
            ? <div className="revert-files">
                {files.map((file, index) => {
                  const { dir, name } = splitPath(file.path || '');
                  const diff = file.diff || {};
                  return (
                    <CodeBlock key={index} icon={fileIcon(file.path)} dir={dir} title={name || file.path} hint={file.path}
                      right={diff.added || diff.removed ? <span className="counts tabular"><span className="plus">+{diff.added || 0}</span> <span className="minus">−{diff.removed || 0}</span></span> : null}>
                      <Diff diff={file.diff} />
                    </CodeBlock>
                  );
                })}
              </div>
            : null}
          {phase === 'preview' && !files.length ? <div className="note">预览没有返回文件差异；确认后仍会先核对哈希再写入。</div> : null}
          <DialogFooter>
            <Button variant="outline" size="sm" disabled={phase === 'applying'} onClick={() => setOpen(false)}>{phase === 'conflict' || phase === 'error' ? '关闭' : '取消'}</Button>
            {phase === 'preview' || phase === 'applying'
              ? <Button id="revert-confirm" variant="destructive" size="sm" disabled={phase === 'applying'} onClick={confirm}>
                  {phase === 'applying' ? <SpinIcon size={14} /> : <Icon name="undo" size={14} />}{phase === 'applying' ? '正在还原…' : '确认还原' + (files.length > 1 ? ' ' + files.length + ' 个文件' : '')}
                </Button>
              : null}
            {phase === 'error' ? <Button variant="default" size="sm" onClick={start}>重试</Button> : null}
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

// Right-hand inspector: the selected call at full height. Docked as a resizable column on
// wide windows, a drawer over the stream on narrow ones.
export function DetailPane({ row, now, snapshot, onCopy, copied, onClose, width, onResize, docked, onNotice, onRefresh }) {
  const startDrag = event => {
    if (!docked) return;
    event.preventDefault();
    const startX = event.clientX, startWidth = width;
    const move = moved => onResize(startWidth + (startX - moved.clientX));
    const up = () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); document.body.classList.remove('resizing'); };
    document.body.classList.add('resizing');
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  };
  const keys = event => {
    if (event.key === 'ArrowLeft') { event.preventDefault(); onResize(width + 16); }
    if (event.key === 'ArrowRight') { event.preventDefault(); onResize(width - 16); }
  };
  const changeId = row && row.detail && row.detail.change_id && !row.detail.is_error ? row.detail.change_id : '';
  return (
    <section className={'detail-column' + (docked ? ' docked' : ' drawer')} aria-label="调用详情" style={docked ? { width } : undefined}
      onKeyDown={event => { if (!docked && event.key === 'Escape') onClose(); }}>
      {docked
        ? <div id="inspector-resize" className="resize-handle" role="separator" aria-orientation="vertical" aria-label="调整检查器宽度"
            aria-valuenow={Math.round(width)} tabIndex={0} onPointerDown={startDrag} onKeyDown={keys} />
        : null}
      <div className="detail-head">
        <div className="detail-line">
          {row ? <Icon name={iconOf(row)} size={16} className="detail-icon" /> : <Icon name="panelRight" size={16} className="detail-icon" />}
          <h2 id="detail-title" title={row ? (row.detail && row.detail.target) || row.target || '' : ''}>
            {row ? titleOf(row.tool) : '检查器'}
          </h2>
          <span className="spacer" />
          {changeId ? <RevertChange key={changeId} changeId={changeId} onNotice={onNotice} onRefresh={onRefresh} /> : null}
          <Button id="copy-detail" variant="ghost" size="sm" hidden={!row} onClick={onCopy}><Icon name={copied ? 'check' : 'copy'} size={14} />{copied ? '已复制' : '复制'}</Button>
          <Button id="inspector-close" variant="ghost" size="icon-sm" aria-label="关闭检查器" title="关闭检查器" onClick={onClose}><Icon name="x" /></Button>
        </div>
        {row ? <div id="detail-state" className="detail-meta">{metaOf(row, now)}</div> : <div className="detail-meta">未选择调用</div>}
      </div>
      <div id="detail-body" tabIndex={0} aria-label="调用详情内容">
        {row
          ? <DetailBody row={row} now={now} snapshot={snapshot} />
          : <Empty icon="panelRight" title="选择一次调用" hint="这里显示它读取了哪些文件与行号、写入或替换了什么内容、执行了哪条命令以及返回结果。" />}
      </div>
    </section>
  );
}
