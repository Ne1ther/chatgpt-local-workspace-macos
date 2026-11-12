// A small, dependency-free Markdown reader for Web Pro consultation reports.
// Blocks: ATX headings, paragraphs, nested lists (bullets, numbers, task boxes), fenced code,
// blockquotes, tables, rules and display math ($$…$$ / \[…\]). Inline: code, bold, italic,
// strikethrough, http(s) links and inline math ($…$ / \(…\)). Math is typeset with Unicode
// symbols, sub/superscripts and stacked fractions; the original TeX stays in the tooltip.
// Everything renders as React elements: report text is never injected as HTML.

const GREEK = {
  alpha: 'α', beta: 'β', gamma: 'γ', delta: 'δ', epsilon: 'ε', varepsilon: 'ε', zeta: 'ζ', eta: 'η', theta: 'θ', vartheta: 'ϑ',
  iota: 'ι', kappa: 'κ', lambda: 'λ', mu: 'μ', nu: 'ν', xi: 'ξ', pi: 'π', rho: 'ρ', sigma: 'σ', tau: 'τ', upsilon: 'υ',
  phi: 'φ', varphi: 'φ', chi: 'χ', psi: 'ψ', omega: 'ω', Gamma: 'Γ', Delta: 'Δ', Theta: 'Θ', Lambda: 'Λ', Xi: 'Ξ', Pi: 'Π',
  Sigma: 'Σ', Phi: 'Φ', Psi: 'Ψ', Omega: 'Ω',
};
const SYMBOLS = {
  times: '×', cdot: '·', div: '÷', pm: '±', mp: '∓', le: '≤', leq: '≤', ge: '≥', geq: '≥', neq: '≠', ne: '≠', approx: '≈',
  sim: '∼', simeq: '≃', equiv: '≡', propto: '∝', infty: '∞', partial: '∂', nabla: '∇', sum: '∑', prod: '∏', int: '∫',
  oint: '∮', iint: '∬', sqrt: '√', to: '→', rightarrow: '→', leftarrow: '←', Rightarrow: '⇒', Leftarrow: '⇐',
  leftrightarrow: '↔', Leftrightarrow: '⇔', mapsto: '↦', in: '∈', notin: '∉', subset: '⊂', subseteq: '⊆', supset: '⊃',
  cup: '∪', cap: '∩', forall: '∀', exists: '∃', emptyset: '∅', varnothing: '∅', ldots: '…', cdots: '⋯', dots: '…',
  langle: '⟨', rangle: '⟩', hbar: 'ħ', ell: 'ℓ', Re: 'ℜ', Im: 'ℑ', degree: '°', circ: '∘', star: '⋆', ast: '∗',
  lfloor: '⌊', rfloor: '⌋', lceil: '⌈', rceil: '⌉', neg: '¬', land: '∧', lor: '∨', perp: '⊥', parallel: '∥',
  quad: '\u2003', qquad: '\u2003\u2003', ',': '\u2009', ';': '\u2005', '!': '', ' ': ' ', '{': '{', '}': '}', '|': '‖',
};
const FUNCTIONS = new Set(['sin', 'cos', 'tan', 'cot', 'sec', 'csc', 'log', 'ln', 'exp', 'lim', 'max', 'min', 'sup', 'inf', 'det', 'arg', 'dim', 'ker', 'sinh', 'cosh', 'tanh', 'arcsin', 'arccos', 'arctan', 'Pr', 'gcd', 'deg']);
const IGNORED = new Set(['left', 'right', 'big', 'Big', 'bigg', 'Bigg', 'displaystyle', 'textstyle', 'limits', 'nolimits']);

// Reads one TeX argument at index i: a {group}, a \command or a single character.
function readGroup(tex, i) {
  while (tex[i] === ' ') i++;
  if (tex[i] === '{') {
    let depth = 0, j = i;
    for (; j < tex.length; j++) {
      if (tex[j] === '\\') { j++; continue; }
      if (tex[j] === '{') depth++;
      else if (tex[j] === '}' && --depth === 0) break;
    }
    return { text: tex.slice(i + 1, j), end: j + 1 };
  }
  if (tex[i] === '\\') {
    const match = /^\\([A-Za-z]+|.)/.exec(tex.slice(i));
    return { text: match ? match[0] : '\\', end: i + (match ? match[0].length : 1) };
  }
  return { text: tex[i] || '', end: i + 1 };
}

// TeX -> React nodes. Handles the subset reports actually use; unknown commands keep their name.
function typeset(tex, key = 'm') {
  const out = [];
  let text = '', n = 0;
  const flush = () => { if (text) { out.push(text); text = ''; } };
  const push = node => { flush(); out.push(node); };
  for (let i = 0; i < tex.length;) {
    const ch = tex[i];
    if (ch === '\\') {
      const match = /^\\([A-Za-z]+|.)/.exec(tex.slice(i));
      const name = match ? match[1] : '';
      i += match ? match[0].length : 1;
      if (name === 'frac' || name === 'dfrac' || name === 'tfrac') {
        const top = readGroup(tex, i), bottom = readGroup(tex, top.end);
        i = bottom.end;
        push(<span key={key + n++} className="md-frac"><span className="md-num">{typeset(top.text, key + n + 'a')}</span><span className="md-den">{typeset(bottom.text, key + n + 'b')}</span></span>);
      } else if (name === 'sqrt') {
        const arg = readGroup(tex, i);
        i = arg.end;
        push(<span key={key + n++} className="md-sqrt">√<span className="md-radicand">{typeset(arg.text, key + n + 'r')}</span></span>);
      } else if (['text', 'textrm', 'mathrm', 'operatorname', 'textbf', 'mathbf', 'mathit', 'mathcal', 'mathbb', 'boldsymbol', 'vec', 'hat', 'bar', 'tilde', 'overline', 'dot'].includes(name)) {
        const arg = readGroup(tex, i);
        i = arg.end;
        const accent = { vec: '\u20d7', hat: '\u0302', bar: '\u0304', tilde: '\u0303', overline: '\u0305', dot: '\u0307' }[name];
        const upright = /^(text|textrm|mathrm|operatorname)$/.test(name);
        push(<span key={key + n++} className={upright ? 'md-upright' : name === 'textbf' || name === 'mathbf' || name === 'boldsymbol' ? 'md-bold' : undefined}>{typeset(arg.text, key + n + 't')}{accent || null}</span>);
      } else if (GREEK[name]) text += GREEK[name];
      else if (SYMBOLS[name] !== undefined) text += SYMBOLS[name];
      else if (FUNCTIONS.has(name)) push(<span key={key + n++} className="md-upright">{name}</span>);
      else if (IGNORED.has(name)) { /* sizing hints */ }
      else if (name === '\\') push(<br key={key + n++} />);
      else text += name;
    } else if (ch === '^' || ch === '_') {
      const arg = readGroup(tex, i + 1);
      i = arg.end;
      const Tag = ch === '^' ? 'sup' : 'sub';
      push(<Tag key={key + n++}>{typeset(arg.text, key + n + 's')}</Tag>);
    } else if (ch === '{' || ch === '}') { i++; }
    else if (ch === '&') { text += '\u2003'; i++; }
    else { text += ch; i++; }
  }
  flush();
  return out;
}

const MathInline = ({ tex }) => <span className="md-math" title={tex}>{typeset(tex.trim())}</span>;
const MathBlock = ({ tex }) => <div className="md-math-block" title={tex} role="math" aria-label={tex}>{typeset(tex.trim())}</div>;

// Inline grammar, tried in order at every position.
const INLINE = [
  { re: /^`([^`]+)`/, make: (m, k) => <code key={k}>{m[1]}</code> },
  { re: /^\\\((.+?)\\\)/, make: (m, k) => <MathInline key={k} tex={m[1]} /> },
  // $x$ but not prices like $5 or "$ 10": no space inside the delimiters, no digit after the close.
  { re: /^\$(?!\$)(?!\s)((?:\\\$|[^$\n])+?)(?<!\s)\$(?!\d)/, make: (m, k) => <MathInline key={k} tex={m[1]} /> },
  { re: /^\*\*(.+?)\*\*/, make: (m, k, r) => <strong key={k}>{r(m[1])}</strong> },
  { re: /^__(.+?)__/, make: (m, k, r) => <strong key={k}>{r(m[1])}</strong> },
  { re: /^~~(.+?)~~/, make: (m, k, r) => <del key={k}>{r(m[1])}</del> },
  { re: /^\*(?!\s)(.+?)(?<!\s)\*/, make: (m, k, r) => <em key={k}>{r(m[1])}</em> },
  { re: /^_(?!\s)(.+?)(?<!\s)_(?![A-Za-z0-9])/, make: (m, k, r) => <em key={k}>{r(m[1])}</em> },
  { re: /^\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/, make: (m, k, r) => /^https?:\/\//i.test(m[2]) ? <a key={k} href={m[2]} target="_blank" rel="noopener noreferrer">{r(m[1])}</a> : <span key={k} className="md-link" title={m[2]}>{r(m[1])}</span> },
  { re: /^<?(https?:\/\/[^\s<>()]+[^\s<>().,;:!?'"])>?/, make: (m, k) => <a key={k} href={m[1]} target="_blank" rel="noopener noreferrer">{m[1]}</a> },
];
const SPECIAL = /[`\\$*_~\[h<]/;

export function inline(source, prefix = 'i') {
  const out = [];
  let text = '', n = 0;
  const recurse = value => inline(value, prefix + n + '.');
  for (let i = 0; i < source.length;) {
    if (SPECIAL.test(source[i]) && !(source[i] === '_' && /[A-Za-z0-9]/.test(source[i - 1] || ''))) {
      const rest = source.slice(i);
      let hit = null;
      for (const rule of INLINE) { const m = rule.re.exec(rest); if (m) { hit = { m, rule }; break; } }
      if (hit) {
        if (text) { out.push(text); text = ''; }
        out.push(hit.rule.make(hit.m, prefix + n++, recurse));
        i += hit.m[0].length;
        continue;
      }
      if (source[i] === '\\' && /[\\`*_{}\[\]()#+\-.!$|~]/.test(source[i + 1] || '')) { text += source[i + 1]; i += 2; continue; }
    }
    text += source[i++];
  }
  if (text) out.push(text);
  return out;
}

const LIST = /^(\s*)([-*+]|\d{1,9}[.)])\s+(.*)$/;
const FENCE = /^\s*(`{3,}|~{3,})\s*([\w+#.-]*)/;
const RULE = /^\s{0,3}([-*_])(\s*\1){2,}\s*$/;
const TABLE_SEP = /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/;
const cells = line => line.trim().replace(/^\|/, '').replace(/\|$/, '').split(/(?<!\\)\|/).map(cell => cell.trim().replace(/\\\|/g, '|'));
const indentOf = line => line.match(/^\s*/)[0].replace(/\t/g, '    ').length;

function List({ lines, prefix }) {
  const first = LIST.exec(lines[0]);
  const ordered = /\d/.test(first[2]);
  const base = indentOf(lines[0]);
  const items = [];
  for (const line of lines) {
    const match = LIST.exec(line);
    if (match && indentOf(line) <= base + 1) items.push({ head: match[3], rest: [] });
    else if (items.length) items[items.length - 1].rest.push(line);
  }
  const Tag = ordered ? 'ol' : 'ul';
  const start = ordered ? parseInt(first[2], 10) : undefined;
  return (
    <Tag start={start && start !== 1 ? start : undefined}>
      {items.map((item, index) => {
        const task = /^\[([ xX])\]\s+(.*)$/.exec(item.head);
        const body = task ? task[2] : item.head;
        const nested = item.rest.length ? blocks(item.rest.map(line => line.slice(Math.min(indentOf(line), base + 2))).join('\n'), prefix + index + '.') : null;
        return (
          <li key={index} className={task ? 'md-task' : undefined}>
            {task ? <span className={'md-check' + (task[1] !== ' ' ? ' done' : '')} aria-label={task[1] !== ' ' ? '已完成' : '未完成'}>{task[1] !== ' ' ? '✓' : ''}</span> : null}
            {inline(body, prefix + index + 'h')}
            {nested}
          </li>
        );
      })}
    </Tag>
  );
}

// Block grammar: returns an array of React elements for one Markdown document (or fragment).
export function blocks(source, prefix = 'b') {
  const lines = String(source || '').replace(/\r\n?/g, '\n').split('\n');
  const out = [];
  let i = 0, n = 0;
  const key = () => prefix + n++;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) { i++; continue; }

    const fence = FENCE.exec(line);
    if (fence) {
      const marker = fence[1], body = [];
      for (i++; i < lines.length && !lines[i].trim().startsWith(marker); i++) body.push(lines[i]);
      i++;
      out.push(<pre key={key()} className="md-code" data-lang={fence[2] || undefined}>{fence[2] ? <span className="md-code-lang">{fence[2]}</span> : null}<code>{body.join('\n')}</code></pre>);
      continue;
    }

    const trimmed = line.trim();
    if (trimmed.startsWith('$$') || trimmed.startsWith('\\[')) {
      const close = trimmed.startsWith('$$') ? '$$' : '\\]';
      const opening = trimmed.slice(2);
      if (opening.trim().endsWith(close) && opening.trim().length >= close.length) {
        out.push(<MathBlock key={key()} tex={opening.trim().slice(0, -close.length)} />); i++; continue;
      }
      const body = [opening];
      for (i++; i < lines.length && !lines[i].trim().endsWith(close); i++) body.push(lines[i]);
      if (i < lines.length) body.push(lines[i].trim().slice(0, -close.length));
      i++;
      out.push(<MathBlock key={key()} tex={body.join('\n')} />);
      continue;
    }

    const heading = /^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/.exec(line);
    if (heading) {
      const Tag = 'h' + Math.min(heading[1].length + 1, 6);
      out.push(<Tag key={key()} className={'md-h' + heading[1].length}>{inline(heading[2], prefix + n + 'h')}</Tag>);
      i++; continue;
    }

    if (RULE.test(line)) { out.push(<hr key={key()} />); i++; continue; }

    if (/^\s{0,3}>/.test(line)) {
      const body = [];
      for (; i < lines.length && /^\s{0,3}>/.test(lines[i]); i++) body.push(lines[i].replace(/^\s{0,3}>\s?/, ''));
      out.push(<blockquote key={key()}>{blocks(body.join('\n'), prefix + n + 'q')}</blockquote>);
      continue;
    }

    if (line.includes('|') && i + 1 < lines.length && TABLE_SEP.test(lines[i + 1])) {
      const head = cells(line), aligns = cells(lines[i + 1]).map(cell => cell.startsWith(':') && cell.endsWith(':') ? 'center' : cell.endsWith(':') ? 'right' : undefined);
      const body = [];
      for (i += 2; i < lines.length && lines[i].includes('|') && lines[i].trim(); i++) body.push(cells(lines[i]));
      const t = key();
      out.push(
        <div key={t} className="md-table-wrap">
          <table>
            <thead><tr>{head.map((cell, c) => <th key={c} style={aligns[c] ? { textAlign: aligns[c] } : undefined}>{inline(cell, t + 'h' + c)}</th>)}</tr></thead>
            <tbody>{body.map((row, r) => <tr key={r}>{head.map((_, c) => <td key={c} style={aligns[c] ? { textAlign: aligns[c] } : undefined}>{inline(row[c] || '', t + r + '.' + c)}</td>)}</tr>)}</tbody>
          </table>
        </div>
      );
      continue;
    }

    if (LIST.test(line)) {
      const body = [line];
      const base = indentOf(line);
      for (i++; i < lines.length; i++) {
        const next = lines[i];
        if (!next.trim()) {
          // A blank line ends the list unless the list (or an item body) continues after it.
          const after = lines[i + 1];
          if (after !== undefined && (LIST.test(after) && indentOf(after) >= base || (after.trim() && indentOf(after) > base))) { body.push(''); continue; }
          break;
        }
        if (LIST.test(next) || indentOf(next) > base) { body.push(next); continue; }
        if (FENCE.test(next) || /^\s{0,3}(#{1,6}\s|>)/.test(next) || RULE.test(next)) break;
        body.push(' '.repeat(base + 2) + next.trim()); // lazy continuation of the last item
      }
      out.push(<List key={key()} lines={body.filter((entry, index) => entry || index < body.length - 1)} prefix={prefix + n + 'l'} />);
      continue;
    }

    const para = [];
    for (; i < lines.length && lines[i].trim(); i++) {
      if (para.length && (FENCE.test(lines[i]) || LIST.test(lines[i]) || /^\s{0,3}(#{1,6}\s|>)/.test(lines[i]) || RULE.test(lines[i]) || /^\s*(\$\$|\\\[)/.test(lines[i]))) break;
      para.push(lines[i].trim());
    }
    const p = key();
    out.push(<p key={p}>{para.flatMap((text, index) => index ? [<br key={p + 'br' + index} />, ...inline(text, p + index + '.')] : inline(text, p + '0.'))}</p>);
  }
  return out;
}

export function Markdown({ source, className }) {
  return <div className={'md' + (className ? ' ' + className : '')}>{blocks(source)}</div>;
}
