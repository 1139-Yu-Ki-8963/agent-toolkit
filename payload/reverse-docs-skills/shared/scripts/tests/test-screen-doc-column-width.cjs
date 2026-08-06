#!/usr/bin/env node
'use strict';

// 写真指摘 1-79: 画面詳細/基本設計書テンプレートのコンテンツカラムが 760px に固定され、
// 1920px ビューポートでテーブルの大半に不要な横スクロールが発生していた問題の回帰検証。
// 実ブラウザ（Chrome DevTools Protocol）でレイアウトを描画し、
// (a) コンテンツカラム幅がビューポートに応じて拡張されること、
// (b) 横スクロールを要するテーブルの割合が指摘値（76%）の半分以下へ減ることを、
// 修正前 CSS を再現した文書と現行テンプレートの文書を同一 fixture で比較して確認する。

const assert = require('node:assert/strict');
const { execFileSync, spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { findCachedBrowser } = require('./lib/find-cached-browser.cjs');

function isExecutable(filePath) {
  try {
    fs.accessSync(filePath, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function findOnPath(command) {
  try {
    const locator = process.platform === 'win32' ? 'where' : 'which';
    const resolved = execFileSync(locator, [command], { encoding: 'utf8' })
      .trim()
      .split(/\r?\n/)
      .find(isExecutable);
    return resolved || '';
  } catch {
    return '';
  }
}

function findMacBrowser() {
  if (process.platform !== 'darwin') return '';

  const bundleIds = [
    'com.google.Chrome',
    'com.google.Chrome.forTesting',
    'org.chromium.Chromium',
  ];
  for (const bundleId of bundleIds) {
    let appPaths = [];
    try {
      appPaths = execFileSync(
        'mdfind',
        [`kMDItemCFBundleIdentifier == '${bundleId}'`],
        { encoding: 'utf8' },
      ).trim().split('\n').filter(Boolean);
    } catch {
      continue;
    }
    for (const appPath of appPaths) {
      const macOsDir = path.join(appPath, 'Contents', 'MacOS');
      if (!fs.existsSync(macOsDir)) continue;
      const executable = fs.readdirSync(macOsDir)
        .map((name) => path.join(macOsDir, name))
        .find(isExecutable);
      if (executable) return executable;
    }
  }

  const applicationRoots = [
    '/Applications',
    path.join(os.homedir(), 'Applications'),
  ];
  const browserAppNames = [
    'Google Chrome.app',
    'Google Chrome for Testing.app',
    'Chromium.app',
  ];
  for (const applicationRoot of applicationRoots) {
    for (const appName of browserAppNames) {
      const macOsDir = path.join(applicationRoot, appName, 'Contents', 'MacOS');
      if (!fs.existsSync(macOsDir)) continue;
      const executable = fs.readdirSync(macOsDir)
        .map((name) => path.join(macOsDir, name))
        .find(isExecutable);
      if (executable) return executable;
    }
  }
  return '';
}

function findWindowsBrowser() {
  if (process.platform !== 'win32') return '';

  const installRoots = [
    process.env.PROGRAMFILES,
    process.env['PROGRAMFILES(X86)'],
    process.env.LOCALAPPDATA,
  ].filter(Boolean);
  const relativePaths = [
    path.join('Google', 'Chrome', 'Application', 'chrome.exe'),
    path.join('Chromium', 'Application', 'chrome.exe'),
  ];
  for (const installRoot of installRoots) {
    for (const relativePath of relativePaths) {
      const executable = path.join(installRoot, relativePath);
      if (isExecutable(executable)) return executable;
    }
  }
  return '';
}

function findBrowser() {
  if (process.env.CHROME_BIN && isExecutable(process.env.CHROME_BIN)) {
    return process.env.CHROME_BIN;
  }
  for (const command of [
    'google-chrome',
    'google-chrome-stable',
    'chromium',
    'chromium-browser',
  ]) {
    const browser = findOnPath(command);
    if (browser) return browser;
  }
  return findMacBrowser() || findWindowsBrowser() || findCachedBrowser();
}

function launchBrowser(browserPath, args) {
  return new Promise((resolve, reject) => {
    const browser = spawn(browserPath, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';
    let settled = false;
    const timeout = setTimeout(() => {
      if (settled) return;
      settled = true;
      browser.kill('SIGKILL');
      reject(new Error('Chrome/Chromiumのデバッグ接続先を15秒以内に取得できませんでした'));
    }, 15000);

    browser.stderr.setEncoding('utf8');
    browser.stderr.on('data', (chunk) => {
      stderr += chunk;
      const matched = stderr.match(/DevTools listening on (ws:\/\/\S+)/);
      if (!settled && matched) {
        settled = true;
        clearTimeout(timeout);
        resolve({ browser, websocketUrl: matched[1] });
      }
    });
    browser.on('error', (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    });
    browser.on('close', (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(new Error(`Chrome/Chromiumの起動に失敗しました（exit ${code}）\n${stderr}`));
    });
  });
}

function connectCdp(websocketUrl) {
  assert.equal(typeof WebSocket, 'function', 'Node.js組み込みWebSocketを利用できる');
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(websocketUrl);
    const pending = new Map();
    let nextId = 1;
    let connected = false;
    const rejectPending = (error) => {
      pending.forEach((command) => {
        clearTimeout(command.timeout);
        command.reject(error);
      });
      pending.clear();
    };
    const timeout = setTimeout(() => {
      socket.close();
      reject(new Error('Chrome DevTools Protocolへ15秒以内に接続できませんでした'));
    }, 15000);

    socket.addEventListener('open', () => {
      connected = true;
      clearTimeout(timeout);
      resolve({
        socket,
        send(method, params = {}, sessionId) {
          return new Promise((resolveCommand, rejectCommand) => {
            if (socket.readyState !== WebSocket.OPEN) {
              rejectCommand(new Error('Chrome DevTools Protocolが切断されています'));
              return;
            }
            const id = nextId++;
            const commandTimeout = setTimeout(() => {
              pending.delete(id);
              rejectCommand(new Error(`${method}が15秒以内に応答しませんでした`));
            }, 15000);
            pending.set(id, {
              resolve: resolveCommand,
              reject: rejectCommand,
              timeout: commandTimeout,
            });
            socket.send(JSON.stringify({
              id,
              method,
              params,
              ...(sessionId ? { sessionId } : {}),
            }));
          });
        },
      });
    });
    socket.addEventListener('message', (event) => {
      const message = JSON.parse(String(event.data));
      if (!message.id || !pending.has(message.id)) return;
      const command = pending.get(message.id);
      pending.delete(message.id);
      clearTimeout(command.timeout);
      if (message.error) {
        command.reject(new Error(`${message.error.message} (${message.error.code})`));
      } else {
        command.resolve(message.result);
      }
    });
    socket.addEventListener('error', () => {
      clearTimeout(timeout);
      const error = new Error('Chrome DevTools Protocolとの通信に失敗しました');
      rejectPending(error);
      if (!connected) reject(error);
    });
    socket.addEventListener('close', () => {
      clearTimeout(timeout);
      const error = new Error('Chrome DevTools Protocolとの接続が切断されました');
      rejectPending(error);
      if (!connected) reject(error);
    });
  });
}

async function stopBrowser(browser) {
  if (!browser || browser.exitCode !== null) return;
  browser.kill('SIGTERM');
  await Promise.race([
    new Promise((resolve) => browser.once('close', resolve)),
    new Promise((resolve) => setTimeout(resolve, 2000)),
  ]);
  if (browser.exitCode === null) {
    browser.kill('SIGKILL');
    await Promise.race([
      new Promise((resolve) => browser.once('close', resolve)),
      new Promise((resolve) => setTimeout(resolve, 2000)),
    ]);
  }
  browser.stdout.destroy();
  browser.stderr.destroy();
  browser.unref();
}

function replaceAll(source, token, value) {
  return source.split(token).join(value);
}

const repoRoot = path.resolve(__dirname, '..', '..', '..');
const templatePath = path.join(repoRoot, 'shared', 'templates', 'screen-doc-template.html');

// 列数だけを変化させた合成 fixture（20 テーブル）。指摘 1-79 の実測（55 テーブル中 42 個・76% が横スクロール要）を
// 同一手法で再現できるよう、列数分布を調整してある（後述の閾値は指摘値そのものに対して判定する）。
function tableMarkdown(cols, rows) {
  const header = Array.from({ length: cols }, (_, i) => `列${i + 1}見出し語`);
  const sep = header.map(() => '---');
  const lines = [`| ${header.join(' | ')} |`, `| ${sep.join(' | ')} |`];
  for (let r = 0; r < rows; r += 1) {
    const cells = Array.from({ length: cols }, (_, i) => `値${r}${i}相当`);
    lines.push(`| ${cells.join(' | ')} |`);
  }
  return lines.join('\n');
}
const columnCounts = [2, 3, 4, 4, 5, 5, 6, 6, 6, 7, 7, 7, 8, 8, 8, 5, 6, 7, 6, 5];
const tableSections = columnCounts.map((cols, i) => `## 節${i + 1}\n\n${tableMarkdown(cols, 2)}\n`);
const fixtureMarkdown = ['# テスト設計書', '', ...tableSections].join('\n');

function buildDocumentHtml(templateSource) {
  let html = templateSource;
  html = replaceAll(html, '{{DOC_TITLE}}', 'コンテンツカラム幅検証');
  html = replaceAll(html, '{{PORTAL_INDEX_HREF}}', 'index.html');
  html = replaceAll(html, '{{DOC_NAV}}', '');
  html = replaceAll(
    html,
    '{{DOC_MARKDOWN_JSON}}',
    JSON.stringify(fixtureMarkdown).replaceAll('<', '\\u003c'),
  );
  html = replaceAll(
    html,
    '/* TOKENS_CSS */',
    ':root{--mono:monospace;--line:#ccc;--line2:#aaa;--panel:#fff;--panel3:#eee;'
      + '--text:#111;--sub:#222;--muted:#555;--accent:#06c;--head:#eee;--headtext:#111;'
      + '--code:#111;--codetext:#eee;--stamp:#06c;--sidebar-w:248px;--page-gutter:40px;}',
  );
  html = replaceAll(
    html,
    '/* SHELL_CSS */',
    '.pt{height:100vh;overflow:hidden;display:flex;flex-direction:column;}'
      + '.pt-row{display:flex;flex:1;min-height:0;}'
      + '.pt-sidebar{width:var(--sidebar-w);flex:none;}'
      + '.pt-main{flex:1;min-width:0;overflow-y:auto;padding:0 var(--page-gutter) 72px;}',
  );
  html = replaceAll(
    html,
    '<!--SHELL_SIDEBAR-->',
    '<aside class="pt-sidebar">'
      + '<nav class="pt-doc-nav" aria-label="画面設計書"><div class="pt-doc-nav__group">画面 / 設計書</div>'
      + '<div class="pt-doc-nav__group">この設計書内</div><ul class="pt-doc-nav__toc" id="toc-list"></ul></nav>'
      + '</aside>',
  );
  html = replaceAll(html, '<!--SHELL_FOOTER-->', '');
  return html;
}

// 修正前 CSS（指摘 1-79 の再現）を、現行テンプレートの後ろへ上書き注入して構成する。
// テンプレート内部の文字列一致に依存させず、CSS カスケードの後勝ちだけで再現する。
const REGRESSION_OVERRIDE_CSS = '<style id="regression-override">'
  + '.dp-layout{grid-template-columns:200px 1fr!important;}'
  + '.dp-panel{max-width:760px!important;}'
  + '</style>';

const templateSource = fs.readFileSync(templatePath, 'utf8');
const afterHtml = buildDocumentHtml(templateSource);
const beforeHtml = buildDocumentHtml(templateSource).replace('</head>', `${REGRESSION_OVERRIDE_CSS}</head>`);

const MEASURE_SCRIPT = `(async function () {
  var deadline = Date.now() + 15000;
  while (
    (document.readyState !== 'complete' || !document.getElementById('doc-content'))
    && Date.now() < deadline
  ) {
    await new Promise(function (resolve) { setTimeout(resolve, 20); });
  }
  await new Promise(function (resolve) {
    requestAnimationFrame(function () { requestAnimationFrame(resolve); });
  });
  var panel = document.querySelector('.dp-panel');
  var wraps = Array.from(document.querySelectorAll('.table-wrap'));
  var overflowing = wraps.filter(function (wrap) {
    return wrap.scrollWidth > wrap.clientWidth + 1;
  });
  return JSON.stringify({
    panelWidth: panel ? panel.clientWidth : null,
    tableCount: wraps.length,
    overflowCount: overflowing.length,
  });
})()`;

const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'screen-doc-column-width-'));
const cleanupFixture = () => fs.rmSync(fixtureRoot, {
  recursive: true,
  force: true,
  maxRetries: 10,
  retryDelay: 100,
});
process.on('exit', cleanupFixture);

const beforePath = path.join(fixtureRoot, 'before.html');
const afterPath = path.join(fixtureRoot, 'after.html');
fs.writeFileSync(beforePath, beforeHtml);
fs.writeFileSync(afterPath, afterHtml);

(async () => {
  let browser;
  let cdp;
  try {
    const browserPath = findBrowser();
    assert.notEqual(browserPath, '', 'ChromeまたはChromiumの実行ファイルを検出できる');
    const launched = await launchBrowser(browserPath, [
      '--headless=new',
      '--no-sandbox',
      '--disable-gpu',
      '--disable-background-networking',
      '--no-first-run',
      '--no-default-browser-check',
      '--allow-file-access-from-files',
      '--window-size=1920,1200',
      `--user-data-dir=${path.join(fixtureRoot, 'browser-profile')}`,
      '--remote-debugging-port=0',
      'about:blank',
    ]);
    browser = launched.browser;
    cdp = await connectCdp(launched.websocketUrl);

    async function measure(filePath) {
      const target = await cdp.send('Target.createTarget', { url: `file://${filePath}` });
      const attached = await cdp.send('Target.attachToTarget', {
        targetId: target.targetId,
        flatten: true,
      });
      await cdp.send('Runtime.enable', {}, attached.sessionId);
      const evaluated = await cdp.send('Runtime.evaluate', {
        expression: MEASURE_SCRIPT,
        awaitPromise: true,
        returnByValue: true,
      }, attached.sessionId);
      assert.equal(evaluated.exceptionDetails, undefined, `DOM計測を実行できる: ${filePath}`);
      await cdp.send('Target.closeTarget', { targetId: target.targetId });
      return JSON.parse(evaluated.result.value);
    }

    const before = await measure(beforePath);
    const after = await measure(afterPath);

    assert.equal(before.tableCount, after.tableCount, '同一fixtureであり表の総数が一致する');
    assert.ok(before.tableCount > 0, 'fixtureに表が含まれる');

    const beforePercent = (before.overflowCount / before.tableCount) * 100;
    const afterPercent = (after.overflowCount / after.tableCount) * 100;
    const REPORTED_BEFORE_PERCENT = 76; // 指摘1-79の実測値（全55テーブル中42個）
    const HALF_OF_REPORTED = REPORTED_BEFORE_PERCENT / 2;

    assert.ok(
      before.panelWidth !== null && before.panelWidth <= 760,
      `修正前相当のコンテンツカラム幅は760px以下: ${before.panelWidth}`,
    );
    assert.ok(
      after.panelWidth !== null && after.panelWidth > before.panelWidth,
      `コンテンツカラム幅がビューポートに応じて拡張される: before=${before.panelWidth} after=${after.panelWidth}`,
    );
    assert.ok(
      beforePercent >= 60,
      `合成fixtureが指摘1-79の実測（76%）に近い横スクロール発生率を再現する: ${beforePercent.toFixed(1)}%`,
    );
    assert.ok(
      afterPercent <= HALF_OF_REPORTED,
      `横スクロールを要するテーブルの割合が指摘値76%の半分（${HALF_OF_REPORTED}%）以下: ${afterPercent.toFixed(1)}%`,
    );

    console.log(
      `PASS: --self-test ケース21（画面詳細/基本設計書テンプレートのコンテンツカラム幅拡張・横スクロール発生率 `
      + `${beforePercent.toFixed(1)}% → ${afterPercent.toFixed(1)}%、`
      + `カラム幅 ${before.panelWidth}px → ${after.panelWidth}px）`,
    );
  } finally {
    if (cdp) {
      try {
        await cdp.send('Browser.close');
      } catch {
        // 切断済みでもstopBrowserで終了させる
      }
      cdp.socket.close();
    }
    await stopBrowser(browser);
    cleanupFixture();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
