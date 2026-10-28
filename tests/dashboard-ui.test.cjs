// The dashboard ships as one React bundle, so the honest test renders the built page
// (src/dashboard.html) in a real browser and drives it: the chronological one-line stream,
// inline details, the three-pane inspector (open by default on wide windows, resizable),
// the plan band, filters, the ⋯ menu with its confirm dialog, dialogs in short windows,
// designed empty/error states and the neutral Codex-style palette.
// Uses the installed Chromium-family browser; skips with a clear message when absent.
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { launchDashboardBrowser } = require('../scripts/browser-launch.cjs');

const root = path.resolve(__dirname, '..');
const rowCount = 19; // scripts/sample-snapshot.cjs

const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

// The sample preview serves the built page plus sample-snapshot.cjs, so no live instance is touched.
async function startPreview() {
  const child = spawn(process.execPath, [path.join(root, 'scripts', 'dashboard-preview.cjs'), '--sample'], {
    cwd: root, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true,
  });
  const url = await new Promise((resolve, reject) => {
    let text = '';
    const timer = setTimeout(() => reject(new Error('预览服务没有启动')), 15000);
    child.stdout.on('data', chunk => {
      text += chunk;
      const match = text.match(/http:\/\/127\.0\.0\.1:\d+\//);
      if (match) { clearTimeout(timer); resolve(match[0]); }
    });
    child.on('error', error => { clearTimeout(timer); reject(error); });
  });
  return { url, stop: () => child.kill() };
}

// The preview script only serves GET /api/snapshot; the local-action endpoints are mocked
// in the page so the test never needs a running workspace.
const diagnosticsReport = {
  version: '2.4.0', checked_at: new Date().toISOString(), scope: '检查只读取状态：不会重启连接，也不会执行工作区命令。',
  versions: ['本地 MCP', '桌面程序', 'Tunnel Client', 'WebView2 SDK', 'WebView2 Runtime'].map((label, index) => ({
    label, running: index === 4 ? null : '2.4.' + index, installed: '2.4.' + (index === 2 ? 9 : index), restart_required: index === 2, detail: label + ' 的版本来源说明。',
  })),
  checks: Array.from({ length: 9 }, (_, index) => ({ label: '检查项 ' + (index + 1), status: ['pass', 'fail', 'pending', 'unavailable'][index % 4], detail: '第 ' + (index + 1) + ' 项检查的说明文字，足够长以便换行。'.repeat(2) })),
};

// "rgb(1, 2, 3)" / "rgba(1, 2, 3, 0.5)" -> { r, g, b, a }
const parseColor = value => {
  const match = /rgba?\(([^)]+)\)/.exec(value || '');
  if (!match) return null;
  const [r, g, b, a = 1] = match[1].split(',').map(part => parseFloat(part));
  return { r, g, b, a };
};
const hueOf = ({ r, g, b }) => {
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  if (!d) return { hue: 0, chroma: 0 };
  let hue = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  hue = (hue * 60 + 360) % 360;
  return { hue, chroma: d / 255 };
};

test('dashboard', { timeout: 180000 }, async t => {
  let launched;
  try {
    launched = await launchDashboardBrowser();
  } catch (error) {
    t.skip(error.message);
    return;
  }
  t.diagnostic('浏览器：' + launched.label + '（' + launched.path + '，' + launched.elapsed + ' ms）');

  const preview = await startPreview();
  const browser = launched.browser;
  const context = await browser.newContext({ viewport: { width: 1600, height: 900 } });
  const page = await context.newPage();
  const problems = [];
  page.on('console', message => { if (message.type() === 'error') problems.push(message.text() + ' ' + message.location().url); });
  page.on('pageerror', error => problems.push(String(error)));
  await page.route('**/api/diagnostics', route => route.fulfill({ contentType: 'application/json', body: JSON.stringify(diagnosticsReport) }));
  await page.goto(preview.url, { waitUntil: 'load' });
  await page.waitForSelector('#timeline .event');

  const rows = page.locator('#timeline .event');
  const rowWithText = text => page.locator('#timeline .event').filter({ hasText: text });
  const opened = () => page.locator('#timeline .event-wrap.open .event-detail');
  // Opens one row inline and returns its detail text; closes it again afterwards.
  const expand = async locator => {
    await locator.click();
    await delay(60);
    const wrap = locator.locator('xpath=..');
    const text = await wrap.locator('.event-detail').innerText();
    return { text, wrap, close: async () => { await locator.click(); await delay(40); } };
  };

  try {
    await t.test('宽窗口默认三栏：检查器打开并同步选中最新调用', async () => {
      assert.equal(await page.locator('.detail-column').isVisible(), true, '1600px 宽时检查器默认打开');
      assert.equal(await page.locator('#timeline .event.selected').count(), 1, '默认选中一行');
      assert.equal(await page.locator('#timeline .event.selected').getAttribute('data-id'), await rows.last().getAttribute('data-id'), '默认选中最新的调用');
      // 之后的就地展开测试在关闭检查器的两栏模式下进行。
      await page.click('#inspector-toggle');
      assert.equal(await page.locator('.detail-column').count(), 0);
    });

    await t.test('每次调用都有开始时间，进行中的调用持续计时', async () => {
      assert.equal(await rows.count(), rowCount);
      const titles = await rows.evaluateAll(nodes => nodes.map(node => node.getAttribute('title')));
      assert(titles.every(text => /开始 (今天|昨天|\d{2}-\d{2}) \d{2}:\d{2}:\d{2}/.test(text)), '每行都要能看到开始时间：' + titles.join(' | '));

      // sample-snapshot 里最新的一行是仍在运行的命令会话：它在时间线最底部。
      const live = rows.last();
      assert.match(await live.getAttribute('class'), /\blive\b/);
      assert.equal(await live.locator('.event-spin').count(), 1, '进行中的调用要有加载图标');
      assert.match(await live.locator('.event-title').innerText(), /^正在运行$/);
      assert.match(await live.locator('.event-elapsed').innerText(), /^\d+(\.\d+)? s$/);
      assert.match(await page.locator('#metric-live').innerText(), /1\s*进行中/);

      // 暂停轮询后，耗时靠本地计时继续累加，不受服务端时间戳影响。
      await page.click('#pause');
      assert.match(await page.locator('#connection').innerText(), /已暂停/);
      const before = parseFloat(await live.locator('.event-elapsed').innerText());
      await delay(1500);
      const after = parseFloat(await live.locator('.event-elapsed').innerText());
      assert(after > before, '暂停同步后耗时仍要增长：' + before + ' -> ' + after);
      await page.click('#pause');
      assert.match(await page.locator('#connection').innerText(), /实时/);
    });

    await t.test('时间线按时间正序排列、最新在底部，并按回合分组', async () => {
      const starts = await rows.evaluateAll(nodes => nodes.map(node => node.getAttribute('title').match(/(\d{2}):(\d{2}):(\d{2})/).slice(1).join('')));
      assert.deepEqual([...starts].sort(), starts, '调用要按开始时间从旧到新排列');
      assert((await page.locator('#timeline .turn-divider').count()) >= 2, '按时间间隔切出回合分隔线');
      const stuck = await page.locator('#stream').evaluate(node => node.scrollHeight - node.scrollTop - node.clientHeight);
      assert(stuck < 40, '打开时停在最新调用处，距底部 ' + stuck + 'px');
      // 一行一句：动词 + 对象，单行高度。
      const heights = await rows.evaluateAll(nodes => nodes.map(node => node.getBoundingClientRect().height));
      assert(heights.every(height => height <= 32), '每次调用只占一行：' + heights.join(','));
    });

    await t.test('每次调用都能就地展开结构化详情', async () => {
      for (let index = 0; index < rowCount; index += 1) {
        const row = rows.nth(index);
        const { text, close } = await expand(row);
        const label = await row.getAttribute('aria-label');
        assert(!text.includes('没有结构化详情'), label + ' 缺少详情');
        assert(!text.includes('没有可展开的结构化详情'), label + ' 缺少详情');
        assert(text.replace(/\s+/g, ' ').trim().length > 20, label + ' 详情过短：' + text);
        await close();
      }
      assert.equal(await opened().count(), 0, '再次点击收起详情');
    });

    await t.test('写入、读取、命令与搜索显示各自的字段', async () => {
      let open = await expand(rowWithText(/覆盖\s*dashboard\.css/));
      assert.match(open.text, /写入方式/);
      assert.match(open.text, /整体覆盖原有内容/);
      assert.match(open.text, /位置/);
      assert((await open.wrap.locator('.diff-row.add').count()) > 0, '写入要给出改动行');
      assert.match(await rowWithText(/覆盖\s*dashboard\.css/).locator('.counts').innerText(), /\+3\s*−2/);
      await open.close();

      // 读取展示文件内容本身，不再用位置和行号占位。
      open = await expand(rowWithText('WorkspaceDetail.cs'));
      assert((await open.wrap.locator('.file-line').count()) >= 20, '读取要展开文本内容');
      assert.match(open.text, /精确替换/);
      assert.match(open.text, /读到文件结尾|可继续从第 118 行/);
      assert(!open.text.includes('起始行'), '读取不再逐项罗列位置与行号');
      assert(!open.text.includes('位置'), '读取不再展示位置');
      assert(!open.text.includes('src/WorkspaceDetail.cs'), '读取不再重复完整路径');
      assert.match(await open.wrap.locator('.card-title').innerText(), /^WorkspaceDetail\.cs$/);
      assert.match(await open.wrap.locator('.card-title').getAttribute('title'), /src\/WorkspaceDetail\.cs$/);
      await open.close();

      // 不是文本的文件不展开内容，但有明确的大小与结论。
      open = await expand(rowWithText('local-workspace.ico'));
      assert.match(open.text, /不是文本/);
      assert.match(open.text, /23\.8 KB/);
      assert.equal(await open.wrap.locator('.file-line').count(), 0, '非文本文件不展开内容');
      await open.close();

      open = await expand(rowWithText('npm run build:ui'));
      assert.match(open.text, /退出码 0/);
      assert.match(open.text, /Dashboard built/);
      await open.close();

      const failedRun = rowWithText('dashboard-ui.test.cjs').filter({ hasText: '运行' });
      assert.match(await failedRun.locator('.event-fail').innerText(), /退出 1/);

      open = await expand(rowWithText('command-output'));
      assert.match(open.text, /4 处/);
      assert.equal(await open.wrap.locator('.match').count(), 4);
      await open.close();
    });

    await t.test('被拒绝的写入只列出路径，不谎报替换', async () => {
      const open = await expand(rowWithText(/未写入\s*dashboard\.css/));
      assert.match(open.text, /已经存在/);
      assert.match(open.text, /未写入/);
      assert.match(open.text, /这次调用没有写入这个文件/);
      assert(!open.text.includes('写入方式'), '失败的写入不能声称写入方式');
      assert(!open.text.includes('写入大小'), '失败的写入不能给出写入大小');
      assert.equal(await open.wrap.locator('.diff-row').count(), 0, '失败的写入不能给出改动');
      await open.close();
    });

    await t.test('右侧检查器可开关、可调宽度，对每一次调用都给出结构化详情', async () => {
      assert.equal(await page.locator('.detail-column').count(), 0, '用户关闭后保持关闭');
      await page.click('#inspector-toggle');
      assert.equal(await page.locator('.detail-column').isVisible(), true);
      for (let index = 0; index < rowCount; index += 1) {
        await rows.nth(index).click();
        await delay(50);
        assert.equal(await page.locator('#timeline .event.selected').getAttribute('data-id'), await rows.nth(index).getAttribute('data-id'), '选中行与检查器同步');
        const text = (await page.locator('#detail-body').innerText()).replace(/\s+/g, ' ').trim();
        const title = await page.locator('#detail-title').innerText();
        assert(!text.includes('没有结构化详情'), title + ' 缺少详情');
        assert(text.length > 40, title + ' 详情过短：' + text);
        assert.match(await page.locator('#detail-state').innerText(), /开始 (今天|昨天|\d{2}-\d{2}) \d{2}:\d{2}:\d{2}/);
      }
      assert.equal(await opened().count(), 0, '检查器打开时不在行内重复展开');
      assert.equal(await page.locator('#timeline .event.selected').count(), 1);
      // 方向键在行之间移动，检查器跟着切换。
      await rows.nth(3).focus();
      await page.keyboard.press('ArrowDown');
      assert.equal(await page.locator('#timeline .event.selected').getAttribute('data-id'), await rows.nth(4).getAttribute('data-id'), '方向键切换选中行');
      // 分隔条可用键盘调宽，宽度有上下限。
      const before = (await page.locator('.detail-column').boundingBox()).width;
      await page.focus('#inspector-resize');
      await page.keyboard.press('ArrowLeft');
      await page.keyboard.press('ArrowLeft');
      const after = (await page.locator('.detail-column').boundingBox()).width;
      assert(Math.abs(after - before - 32) <= 1, '检查器加宽 32px：' + before + ' -> ' + after);
      for (let index = 0; index < 40; index += 1) await page.keyboard.press('ArrowRight');
      assert((await page.locator('.detail-column').boundingBox()).width >= 320 - 1, '检查器不窄于 320px');
      await page.click('#inspector-close');
      assert.equal(await page.locator('.detail-column').count(), 0);
    });

    await t.test('彩色组件区分操作类型，浅深色正文清晰且减少动态效果可用', async () => {
      await page.mouse.move(0, 0);
      await delay(250); // let the 120 ms hover/selection transitions settle
      const report = await page.evaluate(() => {
        const out = { gradients: [], animations: [], edges: [], hues: [], rowColors: new Set(), rowBackgrounds: new Set() };
        for (const sheet of document.styleSheets) {
          for (const rule of sheet.cssRules) if (/gradient\(/.test(rule.cssText)) out.gradients.push(rule.cssText.slice(0, 120));
        }
        for (const node of document.querySelectorAll('body *')) {
          const style = getComputedStyle(node);
          const name = node.tagName.toLowerCase() + '.' + String(node.className && node.className.baseVal !== undefined ? node.className.baseVal : node.className).split(' ').join('.');
          if (/gradient\(/.test(style.backgroundImage)) out.gradients.push(name);
          if (style.animationName !== 'none' && style.animationIterationCount === 'infinite' && !(node.matches('svg.spin'))) out.animations.push(name + ' ' + style.animationName);
          for (const side of ['Left', 'Right']) {
            if (parseFloat(style['border' + side + 'Width']) >= 2 && style['border' + side + 'Style'] !== 'none') out.edges.push(name + ' ' + side + ' ' + style['border' + side + 'Color']);
          }
          if (/inset\s+-?[1-9]/.test(style.boxShadow) || /-?[1-9]\d*px 0px 0px 0px/.test(style.boxShadow)) out.edges.push(name + ' shadow ' + style.boxShadow);
          out.hues.push([name, style.color, style.backgroundColor, style.borderLeftColor]);
        }
        out.iconColors = new Set();
        for (const node of document.querySelectorAll('#timeline .event:not(.failed):not(.live):not(.selected):not(:hover)')) {
          out.rowColors.add(getComputedStyle(node.querySelector('.event-title')).color);
          out.rowBackgrounds.add(getComputedStyle(node).backgroundColor);
          out.iconColors.add(getComputedStyle(node.querySelector('.event-icon svg')).color);
        }
        out.shadows = [...document.querySelectorAll('.app-shell *')].filter(node => getComputedStyle(node).boxShadow !== 'none' && !node.matches('.segment, .jump-latest, .detail-column.drawer')).map(node => node.className && String(node.className.baseVal ?? node.className));
        return { ...out, rowColors: [...out.rowColors], rowBackgrounds: [...out.rowBackgrounds], iconColors: [...out.iconColors] };
      });
      assert.deepEqual(report.gradients, [], '不允许渐变');
      assert.deepEqual(report.animations, [], '除加载图标外不允许无限循环动画');
      assert.deepEqual(report.edges, [], '不允许 2px 以上的侧边线或侧边阴影条');
      assert.equal(report.rowColors.length, 1, '各类调用的文字同一种颜色，不再按类型着色：' + report.rowColors.join(' | '));
      assert.equal(report.rowBackgrounds.length, 1, '各类调用的行底色一致：' + report.rowBackgrounds.join(' | '));
      assert(report.iconColors.length >= 3, '读写、命令等操作用不同的语义色图标：' + report.iconColors.join(' | '));
      assert.deepEqual(report.shadows, [], '阴影只用于浮层（菜单、提示、对话框、窄窗口抽屉）');
      assert.equal(await page.locator('#timeline .event .event-icon svg').count(), rowCount, '每行都有动作图标（运行中为加载图标）');
      // 选中与当前对话都只用底色，不用侧边线。
      assert.equal(await page.locator('#threads .thread.active').evaluate(node => getComputedStyle(node).boxShadow), 'none');

      const lightSurface = await page.locator(".main-sheet").evaluate(node => getComputedStyle(node).backgroundColor);
      const luminance = color => {
        const { r, g, b } = parseColor(color);
        const channel = value => { value /= 255; return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4; };
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
      };
      for (const mode of ['light', 'dark']) {
        await page.emulateMedia({ colorScheme: mode });
        const colors = await page.evaluate(() => {
          const root = getComputedStyle(document.documentElement);
          const probe = document.createElement('span'); document.body.append(probe);
          const colors = Object.fromEntries(['--text', '--text-2', '--text-3', '--surface', '--frame', '--header'].map(key => {
            probe.style.color = root.getPropertyValue(key).trim();
            return [key, getComputedStyle(probe).color];
          }));
          probe.remove(); return colors;
        });
        for (const token of ['--text', '--text-2', '--text-3']) {
          const a = luminance(colors[token]), b = luminance(colors['--surface']);
          assert((Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05) >= 4.5, `${mode}: ${token} contrast must be at least 4.5:1`);
        }
        assert.notEqual(colors['--frame'], colors['--surface'], '导航与内容区需要不同底色');
        assert.notEqual(colors['--header'], colors['--surface'], '标题栏与正文需要不同底色');
      }
      // macOS follows the system appearance.
      await page.emulateMedia({ colorScheme: 'dark' });
      await delay(100);
      assert.notEqual(await page.locator('.main-sheet').evaluate(node => getComputedStyle(node).backgroundColor), lightSurface);
      await page.emulateMedia({ colorScheme: 'light' });
      await page.emulateMedia({ reducedMotion: 'reduce' });
      assert.equal(await page.locator('.event-wrap').first().evaluate(node => getComputedStyle(node).animationName), 'none');
      await page.emulateMedia({ reducedMotion: 'no-preference' });
    });

    await t.test('侧栏用底色标记当前对话，折叠后只留下图标', async () => {
      const active = page.locator('#threads .thread.active');
      assert.equal(await active.count(), 1);
      assert.match(await active.innerText(), /全部操作/);
      assert.deepEqual(await page.locator('#threads .thread b').allInnerTexts(), ['全部操作', '本地工作区面板改版'], '未归属与诊断放在底部');
      assert.match(await page.locator('#footer').innerText(), /^v2\.\d+\.\d+/);
      // 有调用在运行时，对应条目右侧显示加载图标而不是数字。
      assert.equal(await page.locator('#threads .thread').first().locator('.thread-meta svg.spin').count(), 1);
      assert.equal(await page.locator('.brand').isVisible(), true, '普通浏览器里显示品牌名');
      assert.deepEqual(await page.locator('.brand-mark').evaluate(img => [img.complete, img.naturalWidth, img.naturalHeight]), [true, 20, 20], '品牌标记是 20 px 手调图标');
      // 侧栏第一行与标题栏的标题行居中对齐；版本号和“诊断连接”在同一行。
      const centerY = selector => page.locator(selector).first().evaluate(node => { const r = node.getBoundingClientRect(); return r.top + r.height / 2; });
      const sidebarRows = () => page.evaluate(() => {
        // 把侧栏里可见的按钮和文字按所在行分组：每一行都必须有文字，不能只有一个图标按钮。
        const items = [...document.querySelectorAll('.sidebar button, .sidebar .brand, .sidebar .section-label > span, .sidebar .thread-empty')]
          .filter(node => { const r = node.getBoundingClientRect(); return r.width > 0 && r.height > 0 && getComputedStyle(node).visibility !== 'hidden'; });
        const rows = [];
        for (const node of items) {
          const r = node.getBoundingClientRect(), mid = r.top + r.height / 2;
          let row = rows.find(item => Math.abs(item.mid - mid) < 8);
          if (!row) rows.push(row = { mid, nodes: [] });
          row.nodes.push({ id: node.id, text: (node.innerText || '').trim() });
        }
        return rows.sort((a, b) => a.mid - b.mid);
      });
      assert.equal(await page.locator('.sidebar #collapse').count(), 0, '折叠按钮不占用侧栏的行');
      assert.equal(await page.locator('.workspace-head #collapse').isVisible(), true, '折叠按钮在标题栏标题左侧');
      assert(Math.abs(await centerY('.sidebar .brand') - await centerY('#title')) <= 2, '浏览器里品牌行与标题行对齐');
      assert(Math.abs(await centerY('#footer') - await centerY('#diagnostics')) <= 2, '版本号与“诊断连接”在同一行');
      await page.evaluate(() => document.documentElement.classList.add('embedded'));
      await delay(60);
      assert.equal(await page.locator('.brand').isVisible(), false, '内嵌在桌面程序里时隐藏品牌名');
      const embeddedRows = await sidebarRows();
      for (const row of embeddedRows) assert(row.nodes.some(node => node.text), '内嵌时侧栏没有只放图标按钮的行：' + JSON.stringify(row.nodes));
      assert.match(embeddedRows[0].nodes.map(node => node.text).join(' '), /全部操作/, '内嵌时侧栏第一行就是“全部操作”');
      assert(Math.abs(await centerY('#threads .thread') - await centerY('#title')) <= 2, '内嵌时“全部操作”与标题行对齐');
      await page.evaluate(() => document.documentElement.classList.remove('embedded'));

      await page.click('#collapse');
      await delay(200);
      assert.equal(await page.locator('#shell.collapsed').count(), 1);
      assert.equal(await page.locator('#threads .thread b').first().isVisible(), false, '折叠后不显示标题');
      assert.equal(await page.locator('#threads .thread-glyph').first().isVisible(), true, '折叠后仍要保留图标');
      assert.equal(await page.locator('.brand').isVisible(), false, '折叠后收起品牌名');
      await page.click('#collapse');
      await delay(200);
      assert.equal(await page.locator('#shell.collapsed').count(), 0);
    });

    await t.test('工作目录按完整路径归组，可搜索、折叠并打开各自的对话', async () => {
      const other = await browser.newPage({ viewport: { width: 1600, height: 900 } });
      const sample = require('../scripts/sample-snapshot.cjs')();
      sample.conversations = [
        { thread_id: 'thread-local-workspace', title: '工作台更新', path: '/Projects/one/workspace' },
        { thread_id: 'second', title: '同一目录的第二个对话', path: '/Projects/one/workspace/' },
        { thread_id: 'another', title: '另一个目录', path: '/Projects/two/workspace' },
        { thread_id: 'unlinked', title: '未关联的对话', path: null },
      ];
      await other.route('**/api/snapshot*', route => route.fulfill({ contentType: 'application/json', body: JSON.stringify(sample) }));
      try {
        await other.goto(preview.url);
        await other.waitForSelector('.directory-toggle');
        assert.equal(await other.locator('.directory-group').count(), 3);
        assert.equal(await other.locator('.directory-group').first().locator('.thread').count(), 2);
        assert.deepEqual(await other.locator('.directory-label b').allTextContents(), ['workspace', 'workspace', '未设置目录']);
        const search = other.getByRole('textbox', { name: '搜索目录或对话' });
        await search.fill('第二个');
        assert.deepEqual(await other.locator('.directory-group .thread b').allTextContents(), ['同一目录的第二个对话']);
        await search.fill('/Projects/two');
        assert.deepEqual(await other.locator('.directory-group .thread b').allTextContents(), ['另一个目录']);
        await search.fill('');
        const first = other.locator('.directory-group').first();
        await first.locator('.directory-toggle').click();
        assert.equal(await first.locator('.thread').count(), 0);
        await first.locator('.directory-toggle').click();
        await first.getByRole('button', { name: '同一目录的第二个对话', exact: true }).click();
        await other.waitForFunction(() => location.hash === '#thread=second' && document.querySelector('#title')?.textContent === '同一目录的第二个对话');
        assert.equal(await other.locator('#title').innerText(), '同一目录的第二个对话');
        assert.match(await other.locator('#context').innerText(), /工作目录.*\/Projects\/one\/workspace/s);
        if (process.env.WORKSPACE_UI_QA_DIR) {
          const fs = require('node:fs'); fs.mkdirSync(process.env.WORKSPACE_UI_QA_DIR, { recursive: true });
          await other.screenshot({ path: path.join(process.env.WORKSPACE_UI_QA_DIR, '03-workbench-directories.png'), fullPage: true });
        }
      } finally { await other.close(); }
    });

    await t.test('同名宿主会话显示日期和编号，默认收起较早记录且可搜索', async () => {
      const other = await browser.newPage({ viewport: { width: 1600, height: 900 } });
      const sample = require('../scripts/sample-snapshot.cjs')();
      sample.conversations = Array.from({ length: 7 }, (_, index) => ({ thread_id: 'thread-collision-' + index, title: 'workspace', path: '/Projects/workspace', source: 'chatgpt', created_at: `2026-10-${String(10 + index).padStart(2, '0')}T03:00:00Z` }));
      await other.route('**/api/snapshot*', route => route.fulfill({ contentType: 'application/json', body: JSON.stringify(sample) }));
      try {
        await other.goto(preview.url);
        await other.waitForSelector('.directory-group .thread');
        const items = other.locator('.directory-group .thread');
        assert.equal(await items.count(), 3);
        assert.equal(new Set(await items.locator('b').allTextContents()).size, 3);
        assert((await items.locator('.thread-sub').allTextContents()).every(text => text.startsWith('#') && text.includes('ChatGPT')));
        await other.getByRole('button', { name: '显示其余 4 个会话' }).click();
        assert.equal(await items.count(), 7);
        await other.getByRole('textbox', { name: '搜索目录或对话' }).fill('SION-1');
        assert.equal(await items.count(), 1);
        await items.first().click();
        await other.waitForFunction(() => location.hash === '#thread=thread-collision-1');
        await other.getByRole('textbox', { name: '搜索目录或对话' }).fill('');
        await other.getByRole('button', { name: '收起较早会话' }).click();
        assert.equal(await items.count(), 4, '保留当前选中的较早会话，避免选择消失');
        assert.equal(await other.locator('.directory-group .thread.active').count(), 1);
        if (process.env.WORKSPACE_UI_QA_DIR) {
          await other.emulateMedia({ colorScheme: 'dark' });
          await other.screenshot({ path: path.join(process.env.WORKSPACE_UI_QA_DIR, 'workbench-color-dark.png'), fullPage: true });
          await other.emulateMedia({ colorScheme: 'light' });
          await other.screenshot({ path: path.join(process.env.WORKSPACE_UI_QA_DIR, 'workbench-color-light.png'), fullPage: true });
        }
      } finally { await other.close(); }
    });

    await t.test('执行计划是时间线上方的独立一栏，不压住任何调用行', async () => {
      assert.equal(await page.locator('#plan-count').innerText(), '1/5');
      assert.match(await page.locator('#plan-current-text').innerText(), /类型化详情/);
      assert.equal(await page.locator('#plan-body').isVisible(), false, '默认折叠');
      assert(await page.evaluate(() => !!(document.querySelector('#plan-card').compareDocumentPosition(document.querySelector('#timeline')) & Node.DOCUMENT_POSITION_FOLLOWING)), '计划要位于时间线上方');
      // 计划不在滚动区里：任何滚动位置、折叠或展开，调用行都不会出现在计划后面。
      const noOverlap = async label => {
        const result = await page.evaluate(() => {
          const plan = document.querySelector('#plan-card').getBoundingClientRect();
          const stream = document.querySelector('#stream');
          const inside = stream.contains(document.querySelector('#plan-card'));
          const hidden = [];
          for (const top of [0, stream.scrollHeight]) {
            stream.scrollTop = top;
            for (const row of document.querySelectorAll('#timeline .event')) {
              // Only the part of a row inside the scroll viewport is painted.
              const box = row.getBoundingClientRect(), view = stream.getBoundingClientRect();
              const top = Math.max(box.top, view.top), bottom = Math.min(box.bottom, view.bottom);
              if (bottom > top && top < plan.bottom - 0.5 && bottom > plan.top + 0.5) hidden.push(row.getAttribute('aria-label'));
            }
          }
          return { inside, hidden, gap: stream.getBoundingClientRect().top - plan.bottom };
        });
        assert.equal(result.inside, false, '计划不放在滚动区内（' + label + '）');
        assert.deepEqual(result.hidden, [], '计划压住了调用行（' + label + '）');
        assert(result.gap >= -1, '时间线从计划下方开始（' + label + '）：' + result.gap);
      };
      await noOverlap('折叠');
      await page.click('#plan-toggle');
      assert.equal(await page.locator('#plan-body').isVisible(), true);
      await noOverlap('展开');
      assert.equal(await page.locator('#plan-steps .plan-step.completed svg').count() > 0, true, '已完成步骤带勾选图标');
      assert.equal(await page.locator('#plan-steps .plan-step').count(), 5);
      assert.equal(await page.locator('#plan-steps .plan-step.in_progress').count(), 1);
      assert.equal(await page.locator('#plan-bar').count(), 0, '不再画彩色进度条');
      await page.click('#plan-toggle');
    });

    await t.test('搜索与分段筛选只留下匹配的调用，弹层不透明', async () => {
      assert.equal(await page.locator('#search').count(), 0, '搜索默认收起');
      await page.click('#search-toggle');
      await page.fill('#search', 'missing-fixture');
      await delay(120);
      assert.equal(await rows.count(), 1);
      assert.match(await rows.first().locator('.event-title').innerText(), /未能读取/);
      // 补丁行要能按它改过的文件名搜到，而不是只能搜工作目录根。
      await page.fill('#search', 'sample-snapshot.cjs');
      await delay(120);
      assert.equal(await rows.count(), 1);
      assert.match(await rows.first().getAttribute('aria-label'), /^应用补丁/);
      await page.fill('#search', '');
      await delay(120);
      assert.equal(await rows.count(), rowCount);

      const track = await page.locator('#state').evaluate(node => getComputedStyle(node).backgroundColor);
      assert.notEqual(track, 'rgba(0, 0, 0, 0)', '分段筛选要有实底');
      await page.click('#state [aria-label="进行中"]');
      await delay(120);
      assert.equal(await rows.count(), 1, '进行中只保留仍在运行的调用');
      assert.match(await rows.first().getAttribute('aria-label'), /^执行命令 · 进行中/);
      await page.click('#state [aria-label="失败"]');
      await delay(120);
      assert.equal(await rows.count(), 1, '只留下退出码非 0 的命令');
      assert.match(await rows.first().locator('.event-fail').innerText(), /退出 1/);
      await page.click('#state [aria-label="全部"]');
      await delay(120);
      assert.equal(await rows.count(), rowCount);
      await page.click('#search-toggle');
      assert.equal(await page.locator('#search').count(), 0);

      await page.click('#more');
      const menu = page.locator('#more-menu');
      await menu.waitFor();
      assert.equal(await menu.evaluate(node => getComputedStyle(node).backgroundColor), 'rgb(255, 255, 255)', '菜单要有实底');
      await page.keyboard.press('Escape');
    });

    await t.test('清空日志在 ⋯ 菜单里，必须确认，并给出结果提示', async () => {
      let clears = 0, mode = 'ok';
      await page.route('**/api/local-actions', route => route.fulfill({ contentType: 'application/json', body: '{"token":"t"}' }));
      await page.route('**/api/clear-logs', route => {
        clears += 1;
        if (mode === 'ok') return route.fulfill({ contentType: 'application/json', body: '{"cleared_activity":18,"cleared_commands":2,"scope":"已完成调用与命令日志已清空；运行中命令、当前任务证据、计划和对话保留。","scope_code":"completed_logs"}' });
        return route.fulfill({ status: 500, contentType: 'text/html', body: '<h1>oops</h1>' });
      });
      assert.equal(await page.locator('#clear-logs').count(), 0, '清空不再放在顶栏');
      await page.click('#more');
      await page.click('#clear-logs');
      await page.locator('#clear-confirm').waitFor();
      assert.equal(clears, 0, '打开确认框时还没有清空');
      await page.click('#clear-cancel');
      await delay(100);
      assert.equal(clears, 0, '取消后不清空');
      assert.equal(await page.locator('#clear-confirm').count(), 0);

      await page.click('#more');
      await page.click('#clear-logs');
      await page.click('#clear-confirm-action');
      await page.locator('#notice').waitFor();
      assert.equal(clears, 1);
      assert.match(await page.locator('#notice').innerText(), /已清空；运行中命令[\s\S]*（共 20 条）/);

      // 非 JSON 的错误页也要给出可读原因，而不是解析异常。
      mode = 'error';
      await page.click('#more');
      await page.click('#clear-logs');
      await page.click('#clear-confirm-action');
      await page.waitForFunction(() => /日志未清空/.test((document.querySelector('#notice') || {}).textContent || ''));
      assert.match(await page.locator('#notice').innerText(), /日志未清空：服务返回 HTTP 500/);
      assert.match(await page.locator('#notice').getAttribute('class'), /error/);
      await page.unroute('**/api/clear-logs');
      await page.unroute('**/api/local-actions');
      await page.waitForSelector('#timeline .event');
    });

    await t.test('矮窗口里对话框整体可滚动到底部，版本以行列表展示', async () => {
      await page.setViewportSize({ width: 900, height: 420 });
      await delay(150);
      // 诊断入口常驻侧栏（菜单里也有一份）。
      await page.click('#diagnostics');
      await page.locator('.diagnostic-check').first().waitFor();
      const dialog = page.locator('.diagnostics-dialog');
      const box = await dialog.boundingBox();
      assert(box.y >= 0 && box.y + box.height <= 420 + 1, '对话框不超出窗口：' + JSON.stringify(box));
      assert.equal(await page.locator('.component-version').count(), 5);
      assert.match(await page.locator('.component-version').nth(2).innerText(), /正在运行[\s\S]*磁盘文件[\s\S]*重启后/);
      assert.equal(await page.locator('.diagnostic-status.pass').count() > 0, true);
      await dialog.evaluate(node => { node.scrollTop = node.scrollHeight; });
      await delay(100);
      const scope = await page.locator('#diagnostics-scope').boundingBox();
      assert(scope && scope.y + scope.height <= 420 + 1, '滚到底能看到最后一行说明');
      assert.equal(await page.locator('.dialog-close').getAttribute('aria-label'), '关闭');
      assert.match(await page.locator('.dialog-close .sr-only').innerText(), /^关闭$/);
      await page.keyboard.press('Escape');
      await delay(100);

      await page.click('#setup-toggle');
      const setup = page.locator('.setup-dialog');
      await setup.waitFor();
      await setup.evaluate(node => { node.scrollTop = node.scrollHeight; });
      await delay(100);
      const copy = await page.locator('#copy-prompt').boundingBox();
      assert(copy && copy.y + copy.height <= 420 + 1, '登记对话框滚到底能看到复制按钮');
      await page.keyboard.press('Escape');
      await page.setViewportSize({ width: 1600, height: 900 });
    });

    await t.test('640–1920 宽度（检查器开与关）都不横向溢出，页面没有脚本错误', async () => {
      const setInspector = async open => {
        if ((await page.locator('.detail-column').count() > 0) !== open) await page.click('#inspector-toggle');
        await delay(80);
        assert.equal(await page.locator('.detail-column').count() > 0, open);
      };
      for (const inspector of [false, true]) {
        for (const width of [640, 768, 900, 1024, 1100, 1280, 1440, 1600, 1920]) {
          await page.setViewportSize({ width, height: 900 });
          await delay(120);
          await setInspector(inspector);
          const overflow = await page.evaluate(() => {
            const doc = document.documentElement.scrollWidth - document.documentElement.clientWidth;
            const head = document.querySelector('.workspace-head');
            const stream = document.querySelector('#stream');
            const rows = [...document.querySelectorAll('#timeline .event')].filter(row => row.scrollWidth > row.clientWidth + 1).length;
            return { doc, head: head.scrollWidth - head.clientWidth, stream: stream.scrollWidth - stream.clientWidth, rows };
          });
          const tag = width + 'px' + (inspector ? '（检查器打开）' : '');
          assert(overflow.doc <= 0, tag + ' 出现横向滚动 ' + overflow.doc + 'px');
          assert(overflow.head <= 0, tag + ' 顶栏内容溢出 ' + overflow.head + 'px');
          assert(overflow.stream <= 0, tag + ' 时间线横向溢出 ' + overflow.stream + 'px');
          assert.equal(overflow.rows, 0, tag + ' 有调用行内容溢出');
          if (width >= 1100 && inspector) {
            const pane = await page.locator('.detail-column').boundingBox();
            assert(pane.width >= 320 - 1 && pane.width <= 640 + 1, tag + ' 检查器宽度 ' + pane.width);
          }
        }
      }
      // 上面故意让清空接口返回 500，浏览器会记一条资源错误；其余不允许任何脚本错误。
      assert.deepEqual(problems.filter(text => !/\/api\/clear-logs/.test(text)), []);
    });

    await t.test('检查器只在 ≥1280px 时默认打开；内容区用满窗口，只在超宽时限宽', async () => {
      await page.evaluate(() => localStorage.removeItem('workspace-inspector-open'));
      for (const [width, open] of [[1200, false], [1280, true], [1920, true]]) {
        await page.setViewportSize({ width, height: 900 });
        await page.reload({ waitUntil: 'load' });
        await page.waitForSelector('#timeline .event');
        assert.equal(await page.locator('.detail-column').count() > 0, open, width + 'px 默认' + (open ? '打开' : '关闭') + '检查器');
      }
      // 1440 无检查器：时间线两侧留白不超过 40px（不再是窄栏居中）。
      await page.setViewportSize({ width: 1440, height: 900 });
      await page.reload({ waitUntil: 'load' });
      await page.waitForSelector('#timeline .event');
      await page.click('#inspector-toggle');
      const gutter = await page.evaluate(() => {
        const column = document.querySelector('#stream').getBoundingClientRect();
        const content = document.querySelector('#timeline').getBoundingClientRect();
        return { left: content.left - column.left, right: column.right - content.right };
      });
      assert(gutter.left <= 40 && gutter.right <= 48, '两侧留白过大：' + JSON.stringify(gutter));
    });

    await t.test('暂停时切换对话只加载一次，旧内容与迟到响应不会串入新对话', async () => {
      const other = await browser.newPage({ viewport: { width: 1600, height: 900 } });
      const requests = [], held = new Map(), releases = [];
      const hold = thread => {
        let release;
        held.set(thread, new Promise(resolve => { release = resolve; }));
        const unblock = () => { held.delete(thread); release(); };
        releases.push(unblock);
        return unblock;
      };
      const snapshotFor = thread => {
        const checked = new Date().toISOString();
        const ids = thread ? [thread] : ['a', 'b'];
        return {
          instance_id: 'thread-switch', version: '2.4.1', checked_at: checked, thread_id: thread,
          conversations: ['a', 'b'].map(id => ({ thread_id: id, title: '对话 ' + id.toUpperCase(), path: '/workspace/' + id, created_at: checked })),
          activity: ids.map(id => ({
            id: 'call-' + id, thread_id: id, tool: 'read_file', target: '/workspace/' + id + '.txt', status: 'returned', started_at: checked, elapsed_ms: 1,
            detail: { kind: 'read', path: '/workspace/' + id + '.txt', name: id + '.txt', start_line: 1, end_line: 1, returned_count: 1, at_end: true, content: [{ n: 1, text: id + '-detail' }] },
          })),
          plans: ids.map(id => ({ thread_id: id, updated_at: checked, plan: [{ step: '计划 ' + id.toUpperCase(), status: 'in_progress' }] })),
          commands: [], queued_calls: 0,
        };
      };
      await other.addInitScript(() => localStorage.setItem('workspace-inspector-open', 'true'));
      await other.route('**/api/snapshot*', async route => {
        const thread = new URL(route.request().url()).searchParams.get('thread') || '';
        requests.push(thread);
        if (held.has(thread)) await held.get(thread);
        await route.fulfill({ contentType: 'application/json', body: JSON.stringify(snapshotFor(thread)) });
      });
      const pick = id => other.getByRole('button', { name: '对话 ' + id.toUpperCase(), exact: true }).click();
      const expectThread = async id => {
        await other.locator('#timeline .event[data-id="call-' + id + '"]').waitFor();
        assert.equal(await other.locator('#timeline .event').count(), 1);
        assert.equal(await other.locator('#title').innerText(), '对话 ' + id.toUpperCase());
        assert.equal(await other.locator('#plan-current-text').innerText(), '计划 ' + id.toUpperCase());
        assert.match(await other.locator('#detail-body').innerText(), new RegExp(id + '-detail'));
      };
      const expectLoading = async () => {
        await other.locator('.skeleton').waitFor();
        assert.equal(await other.locator('#timeline .event, #plan-card, .detail-column').count(), 0, '加载新对话时不展示旧时间线、计划或详情');
      };
      try {
        await other.goto(preview.url + '#thread=a');
        await expectThread('a');
        await other.click('#pause');
        const releaseB = hold('b');
        await pick('b');
        await expectLoading();
        assert.equal(await other.locator('#threads .thread.active b').innerText(), '对话 B', '切换后侧栏仍保留所有对话并选中 B');
        releaseB();
        await expectThread('b');
        assert.match(await other.locator('#connection').innerText(), /已暂停/);
        const afterSwitch = requests.length;
        await delay(1200);
        assert.equal(requests.length, afterSwitch, '切换只同步一次，保持暂停轮询');

        // Hold the already-read body: aborting fetch cannot prevent this late completion.
        await other.evaluate(() => {
          const fetch = window.fetch.bind(window);
          let holdNext = true;
          window.fetch = async (...args) => {
            const response = await fetch(...args);
            if (holdNext && new URL(args[0], location.href).pathname === '/api/snapshot') {
              holdNext = false;
              const read = response.text.bind(response);
              response.text = async () => {
                const body = await read();
                await new Promise(resolve => { window.releaseSnapshot = resolve; });
                return body;
              };
            }
            return response;
          };
        });
        await other.click('#more');
        await other.click('#refresh');
        await other.waitForFunction(() => typeof window.releaseSnapshot === 'function');
        const releaseA = hold('a');
        await Promise.all([other.waitForRequest('**/api/snapshot?thread=a'), pick('a')]);
        await expectLoading();
        await other.evaluate(async () => { window.releaseSnapshot(); await new Promise(resolve => setTimeout(resolve, 0)); });
        await expectLoading();
        assert.equal(await other.locator('#warning, #connect-error').count(), 0, '取消旧请求不显示连接错误');
        const beforeResume = requests.length;
        await other.click('#pause');
        await delay(150);
        assert.equal(requests.length, beforeResume, '旧请求结束不能释放新请求的占用并造成重复同步');
        await other.click('#pause');
        releaseA();
        await expectThread('a');
        assert.match(await other.locator('#connection').innerText(), /已暂停/);

        await Promise.all([other.waitForRequest('**/api/snapshot*'), other.click('#pause')]);
        await other.waitForRequest('**/api/snapshot*', { timeout: 3000 });
        await other.click('#pause');
        assert.match(await other.locator('#connection').innerText(), /已暂停/, '恢复后仍可再次暂停');
        await other.getByRole('button', { name: '全部操作', exact: true }).click();
        await other.waitForFunction(() => document.querySelectorAll('#timeline .event').length === 2);
        assert.equal(await other.locator('#title').innerText(), '全部操作', '暂停时也能切回全部操作');
      } finally {
        releases.forEach(release => release());
        await other.close();
      }
    });

    await t.test('原生导航唯一，登记入口可用，隐藏时停止网络轮询与计时', async () => {
      const nativePage = await context.newPage(); let requests = 0;
      nativePage.on('request', request => { if (request.url().includes('/api/snapshot')) requests++; });
      try {
        await nativePage.setViewportSize({ width: 1000, height: 740 });
        await nativePage.goto(preview.url + '?native=1');
        await nativePage.waitForSelector('#timeline .event');
        assert.equal(await nativePage.locator('.sidebar').count(), 0);
        assert(await nativePage.locator('.event-icon svg path').count() > 0, '真实矢量图标已渲染');
        const firstThread = await nativePage.evaluate(async () => (await (await fetch('/api/snapshot')).json()).conversations[0].thread_id);
        await nativePage.evaluate(id => { location.hash = 'thread=' + encodeURIComponent(id); }, firstThread);
        await nativePage.waitForFunction(() => document.querySelector('#title').textContent !== '全部操作');
        await nativePage.evaluate(() => window.dispatchEvent(new Event('workspace-setup')));
        await nativePage.getByRole('dialog').waitFor(); await nativePage.keyboard.press('Escape');
        await nativePage.evaluate(() => { location.hash = ''; });
        await nativePage.waitForFunction(count => document.querySelectorAll('#timeline .event').length === count, rowCount);
        await nativePage.evaluate(() => window.dispatchEvent(new CustomEvent('workspace-visibility', { detail: false })));
        await delay(300); const before = requests;
        const elapsed = await nativePage.locator('#timeline .event.live .event-elapsed').innerText();
        await delay(1800);
        assert.equal(requests, before, '隐藏后不再轮询');
        assert.equal(await nativePage.locator('#timeline .event.live .event-elapsed').innerText(), elapsed, '隐藏后不触发计时重绘');
        await nativePage.evaluate(() => window.dispatchEvent(new CustomEvent('workspace-visibility', { detail: true })));
        await delay(200); assert(requests > before, '恢复显示立即同步');
        assert.equal(await nativePage.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
      } finally { await nativePage.close(); }
    });

    await t.test('首屏加载是静态骨架，连接失败有设计过的错误页', async () => {
      const other = await context.newPage();
      let release;
      const hold = new Promise(resolve => { release = resolve; });
      await other.route('**/api/snapshot*', async route => { await hold; route.fulfill({ status: 503, contentType: 'application/json', body: '{"error":"本地服务未启动"}' }); });
      await other.goto(preview.url, { waitUntil: 'load' });
      await other.locator('.skeleton').waitFor();
      const animated = await other.evaluate(() => [...document.querySelectorAll('.skeleton *')].filter(node => getComputedStyle(node).animationName !== 'none').length);
      assert.equal(animated, 0, '骨架屏不闪烁');
      release();
      await other.locator('#connect-error').waitFor();
      assert.match(await other.locator('#connect-error').innerText(), /无法连接本地工作区[\s\S]*本地服务未启动[\s\S]*重试/);
      await other.close();
    });
  } finally {
    await browser.close();
    preview.stop();
  }
});
