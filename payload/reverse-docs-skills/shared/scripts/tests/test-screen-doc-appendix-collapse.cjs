#!/usr/bin/env node
'use strict';

// 写真指摘 1-82: 画面詳細設計書で生コード全文ダンプと API 全量列挙テーブルが本文の 65.7% を占め、
// 主要読解パス（画面概要〜業務ルール〜領域別仕様〜要確認事項）を塞いでいた問題の回帰検証。
// 見出しテキストが「付録:」で始まる h3/h4 を <details><summary>（ネイティブHTML要素のみ・JSトグルなし）へ
// 変換し、初期表示（未展開）の本文高さが全展開時に比べて大幅に縮むことを実ブラウザのDOM計測で確認する。

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

// 指摘1-82の実測構図（イベント処理の生コード全文ダンプ・API通信仕様の機械列挙テーブル）を模した合成fixture。
const codeLines = Array.from({ length: 200 }, (_, i) => `  handleAction${i}();`).join('\n');
const tableRows = Array.from({ length: 100 }, (_, i) => (
  `| ${i} | api-${i} | GET | /api/resource/${i} | 初期表示時 |`
)).join('\n');

const fixtureMarkdown = [
  '# テスト設計書',
  '',
  '## §1 画面概要',
  '',
  '主要読解パスの本文。',
  '',
  '## §7 API 通信仕様',
  '',
  '### 付録: API 一覧',
  '',
  '| No | API 名 | メソッド | エンドポイント | 呼び出し契機 |',
  '|---|---|---|---|---|',
  tableRows,
  '',
  '## §8 イベント処理',
  '',
  '主要読解パスに残る要約説明。',
  '',
  '### 付録: イベントハンドラー原本コード',
  '',
  '```',
  codeLines,
  '```',
  '',
  '## §16 要確認事項一覧',
  '',
  '特になし',
].join('\n');

function buildDocumentHtml(templateSource) {
  let html = templateSource;
  html = replaceAll(html, '{{DOC_TITLE}}', '生コード全文・API全量列挙の折りたたみ検証');
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

const MEASURE_SCRIPT = `(async function () {
  var deadline = Date.now() + 15000;
  while (
    (document.readyState !== 'complete' || !document.getElementById('doc-content'))
    && Date.now() < deadline
  ) {
    await new Promise(function (resolve) { setTimeout(resolve, 20); });
  }
  var container = document.getElementById('doc-content');
  var detailsEls = Array.from(container.querySelectorAll('details.appendix-details'));
  var summaries = detailsEls.map(function (element) {
    return element.querySelector('summary') ? element.querySelector('summary').textContent : '';
  });
  var hasNativeToggleOnly = detailsEls.every(function (element) {
    return !element.hasAttribute('onclick') && !element.querySelector('[onclick]');
  });
  var tableInAppendix = detailsEls.some(function (element) { return !!element.querySelector('table'); });
  var codeInAppendix = detailsEls.some(function (element) { return !!element.querySelector('.code-block'); });
  var closedHeight = container.scrollHeight;
  detailsEls.forEach(function (element) { element.open = true; });
  await new Promise(function (resolve) {
    requestAnimationFrame(function () { requestAnimationFrame(resolve); });
  });
  var openHeight = container.scrollHeight;
  return JSON.stringify({
    detailsCount: detailsEls.length,
    summaries: summaries,
    hasNativeToggleOnly: hasNativeToggleOnly,
    tableInAppendix: tableInAppendix,
    codeInAppendix: codeInAppendix,
    closedHeight: closedHeight,
    openHeight: openHeight,
  });
})()`;

const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'screen-doc-appendix-'));
const cleanupFixture = () => fs.rmSync(fixtureRoot, {
  recursive: true,
  force: true,
  maxRetries: 10,
  retryDelay: 100,
});
process.on('exit', cleanupFixture);

const documentPath = path.join(fixtureRoot, 'appendix.html');
fs.writeFileSync(documentPath, buildDocumentHtml(fs.readFileSync(templatePath, 'utf8')));

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

    const target = await cdp.send('Target.createTarget', { url: `file://${documentPath}` });
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
    assert.equal(evaluated.exceptionDetails, undefined, 'DOM計測を実行できる');
    await cdp.send('Target.closeTarget', { targetId: target.targetId });
    const result = JSON.parse(evaluated.result.value);

    assert.equal(result.detailsCount, 2, '原本literal節（生コード全文）とAPI全量テーブルの両方が付録として検出される');
    assert.deepEqual(
      result.summaries,
      ['付録: API 一覧', '付録: イベントハンドラー原本コード'],
      '付録見出しのテキストが折りたたみのsummaryへ引き継がれる',
    );
    assert.ok(result.tableInAppendix, 'API全量列挙テーブルが付録内に格納される');
    assert.ok(result.codeInAppendix, '生コード全文（原本literal）が付録内に格納される');
    assert.ok(result.hasNativeToggleOnly, 'onclick等のJSトグルを使わずネイティブdetails/summaryのみで開閉する');

    const collapsedRatio = (result.closedHeight / result.openHeight) * 100;
    assert.ok(
      collapsedRatio <= 50,
      `初期表示（未展開）の本文高さが全展開時の半分以下: ${collapsedRatio.toFixed(1)}% `
        + `(closed=${result.closedHeight}px open=${result.openHeight}px)`,
    );

    console.log(
      `PASS: --self-test ケース22（画面詳細設計書テンプレートの参照用付録折りたたみ・`
      + `初期表示本文高さ ${result.closedHeight}px / 全展開 ${result.openHeight}px = ${collapsedRatio.toFixed(1)}%）`,
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
