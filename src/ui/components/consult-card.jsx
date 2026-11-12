import { useEffect, useRef, useState } from 'react';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Icon, SpinIcon } from './icons.jsx';
import { PathLink } from './path-link.jsx';
import { Markdown } from '@/lib/markdown.jsx';
import { writeClipboard } from '@/lib/clipboard.js';
import { CONSULT_STAGES, consultsFor, proPrompt, stageIndex, stageLabel, t3Receipt } from '@/lib/consult.js';
import { bytes, stamp } from '@/lib/format.js';

const stored = (key, fallback) => { try { const value = localStorage.getItem(key); return value == null ? fallback : value === 'true'; } catch { return fallback; } };
const store = (key, value) => { try { localStorage.setItem(key, String(value)); } catch { /* private mode */ } };

// Three-stage pill: 已打包 -> Web Pro 读取中 -> 报告已归档, with the passed stages as ticks.
export function StagePill({ status, compact }) {
  const index = stageIndex(status);
  return (
    <span className={'consult-pill ' + (index < 0 ? 'unknown' : status)} title={CONSULT_STAGES.map((stage, at) => (at <= index ? '● ' : '○ ') + stage.label).join('  ')}>
      {compact ? null : (
        <span className="consult-stages" aria-hidden="true">
          {CONSULT_STAGES.map((stage, at) => <i key={stage.key} className={at <= index ? 'on' : ''} />)}
        </span>
      )}
      {status === 'reading' ? <SpinIcon size={11} /> : null}
      <span>{stageLabel(status)}</span>
    </span>
  );
}

// Text button that confirms a copy in place for a moment.
function CopyAction({ id, text, label, done = '已复制', variant = 'ghost', icon = 'copy', onFail }) {
  const [copied, setCopied] = useState(false);
  const timer = useRef(null);
  useEffect(() => () => clearTimeout(timer.current), []);
  const copy = async event => {
    event.stopPropagation();
    if (!(await writeClipboard(text))) { onFail?.('无法写入剪贴板，请手动复制。'); return; }
    setCopied(true);
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setCopied(false), 1500);
  };
  return <Button id={id} variant={variant} size="xs" onClick={copy}><Icon name={copied ? 'check' : icon} size={13} />{copied ? done : label}</Button>;
}

// The archived report: fetched on open, rendered Markdown (headings, lists, code, quotes,
// math) or the raw text, plus the receipt T3 Code needs to pick the report back up.
export function ReportDialog({ consult, open, onOpenChange, onNotice }) {
  const [state, setState] = useState({ loading: false, error: '', report: null });
  const [raw, setRaw] = useState(false);
  const id = consult?.consult_id || '';
  useEffect(() => {
    if (!open || !id) return undefined;
    const abort = new AbortController();
    setState({ loading: true, error: '', report: null });
    (async () => {
      try {
        const response = await fetch('/api/consult-report?id=' + encodeURIComponent(id), { cache: 'no-store', signal: abort.signal });
        const text = await response.text();
        let value = {};
        try { value = text ? JSON.parse(text) : {}; } catch { value = {}; }
        if (!response.ok) throw Error((value && value.error) || '服务返回 HTTP ' + response.status);
        if (typeof value.content !== 'string') throw Error('报告内容为空');
        setState({ loading: false, error: '', report: value });
      } catch (caught) {
        if (caught.name !== 'AbortError') setState({ loading: false, error: caught.message, report: null });
      }
    })();
    return () => abort.abort();
  }, [open, id]);

  const report = state.report;
  const receipt = { ...(consult?.receipt || {}), ...(report || {}) };
  const facts = [
    receipt.line_count != null ? receipt.line_count + ' 行' : '',
    receipt.byte_length != null ? bytes(receipt.byte_length) : '',
    receipt.created_at ? '归档于 ' + stamp(receipt.created_at) : '',
  ].filter(Boolean);
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent id="consult-report" className="report-dialog" aria-describedby="consult-report-summary">
        <DialogHeader>
          <DialogTitle>{report?.title || consult?.title || 'Web Pro 研究报告'}</DialogTitle>
          <DialogDescription id="consult-report-summary">{receipt.summary || '由 ChatGPT Web Pro 通过 submit_pro_report 归档的研究报告。'}</DialogDescription>
        </DialogHeader>
        <div className="report-toolbar">
          <div className="segmented" role="group" aria-label="报告显示方式">
            <button type="button" className="segment" data-state={raw ? 'off' : 'on'} aria-pressed={!raw} onClick={() => setRaw(false)}>渲染</button>
            <button type="button" className="segment" data-state={raw ? 'on' : 'off'} aria-pressed={raw} onClick={() => setRaw(true)}>原文</button>
          </div>
          <span className="report-facts tabular">{facts.join(' · ')}</span>
          <span className="report-actions">
            <CopyAction id="copy-report" text={report?.content || ''} label="复制原文" variant="ghost" onFail={onNotice} />
            <CopyAction id="copy-receipt" text={t3Receipt(consult, report)} label="复制 T3 回执" done="回执已复制" variant="outline" icon="link" onFail={onNotice} />
          </span>
        </div>
        <div className="report-body" tabIndex={0} aria-label="报告内容">
          {state.loading
            ? <div className="report-state"><SpinIcon size={14} />正在读取报告…</div>
            : state.error
              ? <div className="alert"><span className="mark"><Icon name="circleAlert" size={14} /></span><div>无法读取报告：{state.error}</div></div>
              : report
                ? (raw ? <pre className="report-raw">{report.content}</pre> : <Markdown source={report.content} />)
                : null}
        </div>
        {receipt.report_path || receipt.sha256
          ? <div className="report-foot">
              {receipt.report_path ? <span className="fact-item"><span className="label">报告文件</span><span className="value mono"><PathLink value={receipt.report_path} /></span></span> : null}
              {receipt.sha256 ? <span className="fact-item"><span className="label">SHA256</span><span className="value mono">{receipt.sha256}</span></span> : null}
            </div>
          : null}
      </DialogContent>
    </Dialog>
  );
}

function ConsultItem({ consult, grouped, threadName, onReport, onNotice }) {
  const meta = [
    grouped && consult.thread_id ? threadName(consult.thread_id) : '',
    consult.file_count != null ? consult.file_count + ' 个文件' : '',
    consult.staged_at ? '打包于 ' + stamp(consult.staged_at) : '',
    consult.last_read_at && consult.status !== 'staged' ? '读取于 ' + stamp(consult.last_read_at) : '',
  ].filter(Boolean);
  return (
    <li className="consult-item" data-id={consult.consult_id} data-status={consult.status}>
      <StagePill status={consult.status} />
      <div className="consult-main">
        <span className="consult-title" title={consult.instructions || consult.title || consult.consult_id}>{consult.title || consult.consult_id}</span>
        <span className="consult-meta">{meta.join(' · ')}{consult.receipt?.summary ? <span className="consult-summary"> — {consult.receipt.summary}</span> : null}</span>
      </div>
      <span className="consult-actions">
        <CopyAction text={proPrompt(consult)} label="复制 Pro 指令" done="指令已复制" onFail={onNotice} />
        {consult.status === 'completed'
          ? <Button variant="outline" size="xs" className="consult-report-open" onClick={() => onReport(consult)}><Icon name="fileText" size={13} />查看报告</Button>
          : null}
      </span>
    </li>
  );
}

// A flat band above the stream, like the plan: collapsed, the newest consultation and its
// stage; expanded, every consultation with its instruction and report actions.
export function ConsultCard({ snapshot, thread, threadName, onNotice }) {
  const [open, setOpen] = useState(() => stored('workspace-consult-open', false));
  const [reading, setReading] = useState(null);
  const list = consultsFor(snapshot, thread);
  if (!list.length) return null;
  const lead = list[0];
  const toggle = value => { setOpen(value); store('workspace-consult-open', value); };
  const done = list.filter(item => item.status === 'completed').length;
  return (
    <Collapsible id="consult-card" className="consult-card" open={open} onOpenChange={toggle}>
      <div className="consult-inner">
        <div className="consult-heading">
          <CollapsibleTrigger id="consult-toggle" className="consult-head" title={open ? '收起 Web Pro 咨询' : '展开 Web Pro 咨询'}>
            <Icon name="inbox" size={16} className="consult-icon" />
            <span className="consult-name">Web Pro 咨询</span>
            <span id="consult-count" className="consult-count tabular">{done}/{list.length}</span>
            <StagePill status={lead.status} compact />
            <span className="consult-current" title={lead.title || lead.consult_id}>{lead.title || lead.consult_id}</span>
            <Icon name="chevron" size={16} className="chevron" />
          </CollapsibleTrigger>
          {lead.status === 'completed'
            ? <Button variant="ghost" size="xs" className="consult-quick" onClick={() => setReading(lead)}>查看报告</Button>
            : <CopyAction text={proPrompt(lead)} label="复制 Pro 指令" done="指令已复制" onFail={onNotice} />}
        </div>
        <CollapsibleContent id="consult-body" className="consult-body">
          <ul className="consult-list">
            {list.map(consult => <ConsultItem key={consult.consult_id} consult={consult} grouped={!thread} threadName={threadName} onReport={setReading} onNotice={onNotice} />)}
          </ul>
        </CollapsibleContent>
      </div>
      <ReportDialog consult={reading} open={!!reading} onOpenChange={value => { if (!value) setReading(null); }} onNotice={onNotice} />
    </Collapsible>
  );
}
