import { PathLink, AddressValue } from './path-link.jsx';
import { ImageView } from './image-view.jsx';
import { Icon, SpinIcon, fileIcon } from './icons.jsx';
import { useState } from 'react';
import { CodeBlock, LineWindow } from './code-block.jsx';
import { bytes, duration, splitPath } from '@/lib/format.js';
import { OPERATIONS } from '@/lib/labels.js';
import { liveElapsed } from '@/lib/rows.js';
import { INFO_LABELS, consultField, consultNumber } from '@/lib/consult.js';

const Counts = ({ added, removed }) => (
  <span className="counts tabular"><span className="plus">+{added || 0}</span> <span className="minus">−{removed || 0}</span></span>
);

// Label / value facts under a block head ("位置", "写入方式").
const Facts = ({ rows }) => {
  const list = rows.filter(row => row && row.value !== undefined && row.value !== null && row.value !== '');
  if (!list.length) return null;
  return (
    <div className="rows">
      {list.map((row, index) => (
        <div key={index} className={'row' + (row.stack ? ' stack' : '')}>
          <span className="label">{row.label}</span>
          <span className={'value' + (row.mono ? ' mono' : '')}><AddressValue value={row.value} /></span>
        </div>
      ))}
    </div>
  );
};

// The same facts as one quiet wrapped line, for block feet.
const FactLine = ({ rows }) => rows.filter(row => row && row.value).map((row, index) => (
  <span key={index} className="fact-item"><span className="label">{row.label}</span><span className={row.mono ? 'value mono' : 'value'}><AddressValue value={row.value} /></span></span>
));

const Note = ({ children }) => <div className="note">{children}</div>;
const Alert = ({ children }) => <div className="alert"><span className="mark"><Icon name="circleAlert" size={14} /></span><div>{children}</div></div>;
const Status = ({ children }) => <div className="code-status">{children}</div>;

export function Diff({ diff }) {
  if (!diff) return null;
  const rows = diff.rows || [];
  return (
    <>
      {rows.length
        ? <LineWindow lines={rows} limit={40} className="diff" render={(row, index) => (
            <div key={index} className={'diff-row ' + (row.kind || 'context')}>
              <span className="diff-no">{row.old_line == null ? '' : row.old_line}</span>
              <span className="diff-no">{row.new_line == null ? '' : row.new_line}</span>
              <span className="diff-mark">{row.kind === 'add' ? '+' : row.kind === 'remove' ? '-' : ' '}</span>
              <span className="diff-text">{row.text || ''}</span>
            </div>
          )} />
        : null}
      {diff.identical ? <Note>写入内容与原有内容完全一致。</Note> : null}
      {diff.truncated ? <Note>差异较大，这里只显示一部分。</Note> : null}
      {diff.coarse ? <Note>差异按行尾对齐，可能不是最小改动。</Note> : null}
    </>
  );
}
const diffText = diff => (diff && diff.rows ? diff.rows.map(row => (row.kind === 'add' ? '+' : row.kind === 'remove' ? '-' : ' ') + (row.text || '')).join('\n') : '');

const MODE = {
  add: '新建文件', replace: '整体覆盖原有内容', edit: '精确替换第一处匹配', update: '按补丁更新',
};

// One block per structured detail kind, mirroring src/WorkspaceDetail.cs.
export function DetailViews({ row, now }) {
  const detail = row.detail;
  if (!detail) return null;
  const kind = detail.kind;

  if ((row.tool === 'read_research_bundle' || row.tool === 'submit_pro_report') && (kind === 'info' || kind === 'consult')) return <ConsultView row={row} />;
  if (kind === 'image') return <ImageView key={row.id} detail={detail} />;
  if (kind === 'workspace') return <>
    <CodeBlock icon="activity" title={detail.summary || '连接诊断'}><Facts rows={detail.info || []} /></CodeBlock>
    <CodeBlock icon="folder" title={'已登记工作区 · ' + (detail.workspaces || []).length + ' 个对话'}>
      {(detail.workspaces || []).length
        ? <div className="workspace-locations">{detail.workspaces.map((item, index) => <div key={index}><strong>{item.title}</strong><PathLink value={item.path} /></div>)}</div>
        : <Note>尚未登记工作区。登记对话后会在这里显示目录。</Note>}
    </CodeBlock>
    <CodeBlock icon="squareTerminal" title={'可用工具 · ' + (detail.tools || []).length + ' 个'}>
      <div className="tool-list">{(detail.tools || []).map(tool => <code className="chip" key={tool}>{tool}</code>)}</div>
    </CodeBlock>
  </>;

  if (kind === 'write') {
    // A rejected write reports paths only: no operation, size or diff may be shown.
    const rejected = detail.applied === false && !detail.is_preview;
    const root = detail.root || '';
    return (
      <>
        {detail.partial ? <Alert>补丁没有全部写入，下面只有已经生效的文件带改动。</Alert> : null}
        {(detail.files || []).map((file, index) => {
          const diff = file.diff || {};
          const facts = [{ label: '位置', value: file.path, mono: true }];
          if (file.previous_path) facts.push({ label: '移动自', value: file.previous_path, mono: true });
          if (detail.is_preview) facts.push({ label: '结果', value: '预览，未修改文件' });
          if (rejected) facts.push({ label: '结果', value: '这次调用没有写入这个文件' });
          if (!rejected && file.size_bytes) facts.push({ label: '写入大小', value: bytes(file.size_bytes) });
          if (!rejected && MODE[file.operation]) facts.push({ label: '写入方式', value: MODE[file.operation] });
          const added = file.added ?? diff.added, removed = file.removed ?? diff.removed;
          const { dir, name } = splitPath(file.path, root);
          const op = detail.is_preview ? '预览' : rejected ? '未写入' : OPERATIONS[file.operation] || '';
          return (
            <CodeBlock key={index} icon={fileIcon(file.path)} dir={dir} title={file.name || name} hint={file.path}
              right={<>{op ? <span className={'tag' + (rejected ? ' failed' : '')}>{op}</span> : null}{!rejected && (added || removed) ? <Counts added={added} removed={removed} /> : null}</>}
              copy={rejected ? '' : diffText(file.diff)} copyLabel="复制改动" foot={<FactLine rows={facts} />}>
              {rejected ? <Note>这次调用没有写入这个文件，下面只列出路径。</Note> : <Diff diff={file.diff} />}
            </CodeBlock>
          );
        })}
        {detail.replace
          ? <CodeBlock icon="filePen" title="替换文本">
              <div className="row stack"><span className="label">替换后</span><div className="card-text mono">{detail.replace.after.text || '（空）'}</div></div>
              <div className="row stack"><span className="label">原内容</span><div className="card-text mono">{detail.replace.before.text || '（空）'}</div></div>
            </CodeBlock>
          : null}
        {detail.omitted_files ? <Note>另有 {detail.omitted_files} 个文件未在此处展开。</Note> : null}
        {detail.root ? <Note>工作目录 <PathLink value={detail.root} /></Note> : null}
      </>
    );
  }

  if (kind === 'read') {
    const content = detail.content || [];
    const read = (detail.reads || [])[0] || {};
    const name = detail.name || read.name || detail.path || '';
    const size = detail.file_bytes == null ? '' : bytes(detail.file_bytes);
    const range = read.returned_count ? '第 ' + read.start_line + '–' + read.end_line + ' 行' : '未读到内容';
    const tail = detail.at_end ? '读到文件结尾' : detail.next_line ? '可继续从第 ' + detail.next_line + ' 行' : '';
    const facts = (detail.binary ? [size] : [size, range, tail]).filter(Boolean);
    // A read is about the file itself: the block shows its text, the path stays in the
    // title's tooltip instead of taking a row of its own.
    return (
      <>
        <CodeBlock icon={detail.binary ? 'file' : fileIcon(name)} title={name} hint={detail.path}
          right={<span className="tag">{detail.binary ? '不是文本' : range}</span>}
          copy={content.map(line => line.text).join('\n')} copyLabel="复制内容"
          foot={<>{facts.map((fact, index) => <span key={index}>{fact}</span>)}{detail.truncated ? <span className="bad">内容超过 10 KB，只展开了一部分</span> : null}</>}>
          {content.length
            ? <LineWindow lines={content} limit={24} className="file-body" render={(line, index) => (
                <div key={index} className="file-line">
                  <span className="file-no">{line.n == null ? '' : line.n}</span>
                  <span className="file-text">{line.text === '' ? '\u00a0' : line.text}</span>
                </div>
              )} />
            : <Note>{detail.binary ? '这个文件不是文本文件。' : read.empty && !detail.is_error ? '文件是空的，没有内容可以展开。' : '这次没有读到内容。'}</Note>}
        </CodeBlock>
        {(detail.notes || []).map((note, index) => <Note key={index}>{note}</Note>)}
      </>
    );
  }

  if (kind === 'search') {
    const matches = detail.matches || [];
    const notes = [];
    if (detail.complete === false) notes.push('结果是部分结果。');
    if (detail.truncated) notes.push('已达到扫描预算。');
    if (detail.skipped_paths) notes.push(detail.skipped_paths + ' 个路径被跳过。');
    if (detail.scanned_files) notes.push('已扫描 ' + detail.scanned_files + ' 个文件。');
    if (detail.note) notes.push(detail.note);
    return (
      <CodeBlock icon="search" title={detail.query ? '“' + detail.query + '”' : detail.pattern || '*'}
        right={<span className="tag tabular">{detail.returned_count} 处</span>} foot={notes.length ? notes.join(' ') : null}>
        {matches.length
          ? <LineWindow lines={matches} limit={12} unit="处" className="matches" render={(match, index) => {
              const { dir } = splitPath(match.path, detail.root);
              return (
                <div key={index} className="match">
                  <div className="match-place">
                    <Icon name={fileIcon(match.path)} size={14} className="match-icon" />
                    <span className="match-name"><PathLink value={match.path}>{match.name || match.path}</PathLink></span>
                    <span className="place tabular">{match.line == null ? '' : ':' + match.line}{match.column == null ? '' : ':' + match.column}</span>
                    <span className="place dir">{dir}</span>
                  </div>
                  <div className="match-text">{match.text || ''}</div>
                </div>
              );
            }} />
          : <Note>没有匹配项。</Note>}
      </CodeBlock>
    );
  }

  if (kind === 'command') {
    const live = row.session;
    const running = live ? live.running : !!detail.running;
    const output = (live ? live.output : detail.output_tail) || '';
    const exitCode = live ? live.exit_code : detail.exit_code;
    const seconds = (live && live.elapsed_seconds != null ? live.elapsed_seconds : detail.elapsed_seconds) || 0;
    const elapsed = running ? liveElapsed(row, now) : seconds * 1000;
    const timedOut = (live && live.timed_out) || detail.timed_out;
    const stopped = (live && live.stopped) || detail.stopped;
    const command = detail.command || detail.summary || '';
    const lines = output.replace(/\r\n/g, '\n').replace(/\n$/, '').split('\n');
    return (
      <CodeBlock icon="squareTerminal" title={detail.shell || '终端'} copy={command} copyLabel="复制命令"
        foot={<>
          <span className={'exit ' + (running ? 'running' : exitCode ? 'bad' : '')}>
            {running ? <><SpinIcon size={12} /> 进行中</> : '退出码 ' + (exitCode == null ? '—' : exitCode)}
          </span>
          {timedOut ? <span className="bad">已超时</span> : null}
          {stopped ? <span className="bad">已停止</span> : null}
          <span className="tabular">运行 {duration(elapsed)}</span>
          {detail.cwd ? <PathLink value={detail.cwd} /> : null}
          {output ? <OutputCopy text={output} /> : null}
        </>}>
        <div className="command"><span className="prompt">$ </span>{command}</div>
        {output
          ? <LineWindow lines={lines} limit={24} fromEnd className="output" render={(line, index) => <div key={index} className="out-line">{line || '\u00a0'}</div>} />
          : <div className="output empty-output">{running ? '等待输出…' : '没有输出'}</div>}
      </CodeBlock>
    );
  }

  if (kind === 'list') {
    const entries = detail.entries || [];
    return (
      <CodeBlock icon="folderOpen" title={detail.path || '磁盘根目录'} hint={detail.path} right={<span className="tag tabular">{detail.total_entries} 项</span>}
        foot={detail.omitted ? '另有 ' + detail.omitted + ' 项未在此处展开。' : null}>
        {entries.length
          ? <LineWindow lines={entries} limit={30} unit="项" className="entries" render={(entry, index) => (
              <div key={index} className="entry">
                <span className="mark"><Icon name={entry.directory ? 'folder' : fileIcon(entry.name)} size={14} /></span>
                <span className="name"><PathLink value={entry.path}>{entry.name}</PathLink></span>
              </div>
            )} />
          : <Note>目录是空的。</Note>}
      </CodeBlock>
    );
  }

  if (kind === 'text') {
    const raw = String(detail.body || '');
    const lines = raw.replace(/\r\n/g, '\n').split('\n');
    return (
      <CodeBlock icon="gitCompare" title={detail.path || detail.text_label || '输出'} hint={detail.path}
        right={<>{detail.text_label && detail.path ? <span className="tag">{detail.text_label}</span> : null}{detail.added || detail.removed ? <Counts added={detail.added} removed={detail.removed} /> : null}</>}
        copy={raw} copyLabel="复制内容"
        foot={detail.exit_code || detail.timed_out || detail.truncated
          ? <>{detail.exit_code ? <span className="bad">退出码 {detail.exit_code}</span> : null}{detail.timed_out ? <span className="bad">已超时</span> : null}{detail.truncated ? <span>内容已截断</span> : null}</>
          : null}>
        {raw.trim()
          ? <LineWindow lines={lines} limit={40} className="text-body" render={(line, index) => (
              <div key={index} className={'text-line ' + (line.startsWith('+') && !line.startsWith('+++') ? 'add' : line.startsWith('-') && !line.startsWith('---') ? 'remove' : line.startsWith('@@') ? 'hunk' : '')}>{line || '\u00a0'}</div>
            )} />
          : <div className="text-body"><div className="text-line muted">（无输出）</div></div>}
      </CodeBlock>
    );
  }

  if (kind === 'plan') {
    const done = detail.done || 0, total = detail.total || 0;
    return (
      <CodeBlock icon="listChecks" title="计划" right={<span className="tag tabular">{done} / {total}</span>}>
        {detail.explanation ? <div className="card-text">{detail.explanation}</div> : null}
        <div className="steps">
          {(detail.steps || []).map((step, index) => (
            <div key={index} className={'plan-step ' + (step.status || 'pending')}>
              <span className="mark"><Icon name={step.status === 'completed' ? 'circleCheck' : step.status === 'in_progress' ? 'dot' : 'circle'} size={14} /></span>
              <span>{step.step}</span>
            </div>
          ))}
        </div>
      </CodeBlock>
    );
  }

  if (kind === 'info') {
    return (
      <CodeBlock icon="info" title={detail.summary || '信息'} hint={detail.target}>
        <Facts rows={detail.info || []} />
      </CodeBlock>
    );
  }

  return <Note>这次调用没有可展开的结构化详情。</Note>;
}

// Text action in the foot, so the head keeps one copy button (the command).
function OutputCopy({ text }) {
  const [done, setDone] = useState(false);
  const copy = async () => { try { await navigator.clipboard.writeText(text); setDone(true); setTimeout(() => setDone(false), 1400); } catch { /* clipboard denied */ } };
  return <button type="button" className="foot-action" onClick={copy}><Icon name={done ? 'check' : 'copy'} size={12} />{done ? '已复制' : '复制输出'}</button>;
}

// Web Pro consultation calls: a structured card instead of anonymous label/value rows.
// read_research_bundle shows the bundle, its byte budget and the pagination cursor;
// submit_pro_report shows where the report landed and how T3 Code can verify it.
const KNOWN_LABELS = new Set(Object.values(INFO_LABELS).flat());
function ConsultView({ row }) {
  const detail = row.detail;
  const field = key => consultField(detail, key);
  const extra = (detail.info || []).filter(item => item && !KNOWN_LABELS.has(item.label));
  if (row.tool === 'read_research_bundle') {
    const files = consultNumber(detail, 'file_count'), cut = consultNumber(detail, 'truncated_count');
    const offset = consultNumber(detail, 'offset_bytes'), next = consultNumber(detail, 'next_offset_bytes'), total = consultNumber(detail, 'total_bytes');
    const range = offset > 0 || next > 0
      ? '从第 ' + offset.toLocaleString() + ' 字节' + (next > 0 ? ' 读到第 ' + next.toLocaleString() + ' 字节' : ' 读到结尾')
      : '';
    const facts = [
      { label: '咨询编号', value: field('consult_id'), mono: true },
      { label: '文件', value: files ? files + ' 个' + (cut ? '，其中 ' + cut + ' 个按字节预算截断' : '，全部完整读取') : '' },
      { label: '本次读取', value: total ? bytes(total) : '' },
      { label: '读取范围', value: range },
      { label: '资料包指纹', value: field('bundle_sha256'), mono: true },
      ...extra,
    ];
    const list = Array.isArray(detail.files) ? detail.files : [];
    return (
      <>
        <CodeBlock icon="inbox" title={field('title') || '研究资料包'} hint={field('instructions') || undefined}
          right={<span className="tag tabular">{next > 0 ? '分段读取中' : '已读取'}</span>}
          copy={field('consult_id') || ''} copyLabel="复制咨询编号"
          foot={next > 0 ? <span>还有后续内容：下一次调用 read_research_bundle 时传 <code className="chip">offset_bytes: {next}</code> 继续读取。</span> : offset > 0 ? <span>这是续读的最后一段，资料包已读完。</span> : null}>
          <Facts rows={facts} />
          {field('instructions') ? <div className="row stack"><span className="label">研究要求</span><div className="card-text">{field('instructions')}</div></div> : null}
          {list.length
            ? <div className="entries">{list.map((file, index) => (
                <div key={index} className="entry">
                  <span className="mark"><Icon name={fileIcon(file.path)} size={14} /></span>
                  <span className="name"><PathLink value={file.path} />{file.size_bytes != null ? <span className="muted"> · {bytes(file.size_bytes)}</span> : null}{file.truncated ? <span className="danger"> · 已截断</span> : null}</span>
                </div>
              ))}</div>
            : null}
        </CodeBlock>
        <Note>Web Pro 读取资料包后，咨询状态会变为「Web Pro 读取中」；提交报告后变为「报告已归档」。</Note>
      </>
    );
  }
  const lines = consultNumber(detail, 'line_count'), size = consultNumber(detail, 'byte_length');
  const facts = [
    { label: '咨询编号', value: field('consult_id'), mono: true },
    { label: '报告文件', value: field('report_path'), mono: true },
    { label: '回执文件', value: field('receipt_path'), mono: true },
    { label: '大小', value: [lines ? lines + ' 行' : '', size ? bytes(size) : ''].filter(Boolean).join(' · ') },
    { label: 'SHA256', value: field('sha256'), mono: true },
    ...extra,
  ];
  return (
    <>
      <CodeBlock icon="fileText" title={field('title') || (field('report_path') ? splitPath(field('report_path')).name : '') || 'Pro 研究报告'} hint={field('report_path')}
        right={<span className="tag">报告已归档</span>} copy={field('report_path') || ''} copyLabel="复制报告路径">
        <Facts rows={facts} />
        {field('summary') ? <div className="row stack"><span className="label">摘要</span><div className="card-text">{field('summary')}</div></div> : null}
      </CodeBlock>
      <Note>报告已写入咨询收件箱，不会覆盖旧报告。可在时间线上方的「Web Pro 咨询」栏查看渲染后的报告，或复制 T3 回执交给 T3 Code 核对 SHA256 后继续任务。</Note>
    </>
  );
}
