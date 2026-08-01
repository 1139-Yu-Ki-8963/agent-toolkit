#!/usr/bin/env node
'use strict';

// 写真指摘 1-84: 画面詳細設計書に重要度による視覚的強調が無く、§16 要確認事項一覧が
// 通常表として埋没していた問題の回帰検証。§16 の行数を自動判定し、1行以上なら
// pt-callout（重要度: 警告）を、0行なら通常表示のままにすることを実ブラウザのDOM計測で確認する。
// 判定は目視ではなく生成時のJS（screen-doc-template.htmlのenhance()）が機械的に行う。

const assert = require('node:assert/strict');
const { execFileSync, spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

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

function collectCachedBrowsers(directory, results) {
  if (!fs.existsSync(directory)) return;
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      collectCachedBrowsers(entryPath, results);
    } else if (
      [
        'chrome',
        'chromium',
        'chrome-headless-shell',
        'chrome.exe',
        'chromium.exe',
        'chrome-headless-shell.exe',
      ].includes(entry.name)
      && isExecutable(entryPath)
    ) {
      results.push(entryPath);
    }
  }
}

function findCachedBrowser() {
  const cacheRoots = [
    process.env.PLAYWRIGHT_BROWSERS_PATH,
    path.join(os.homedir(), 'Library', 'Caches', 'ms-playwright'),
    path.join(os.homedir(), '.cache', 'ms-playwright'),
    process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, 'ms-playwright'),
  ].filter(Boolean);
  const browsers = [];
  cacheRoots.forEach((cacheRoot) => collectCachedBrowsers(cacheRoot, browsers));
  return browsers.sort().at(-1) || '';
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

const markdownWithItems = [
  '# テスト設計書',
  '',
  '## §16 要確認事項一覧',
  '',
  '| キー | 起票日 | 内容 | 暫定扱いにしている § | 解消条件 | 状態 |',
  '|---|---|---|---|---|---|',
  '| キャンセル理由-必須化 | 2026-07-20 | 備考入力の要否を確認する | §9.2 | 業務部門からの回答 | 未解消 |',
].join('\n');

const markdownEmpty = [
  '# テスト設計書',
  '',
  '## §16 要確認事項一覧',
  '',
  '| キー | 起票日 | 内容 | 暫定扱いにしている § | 解消条件 | 状態 |',
  '|---|---|---|---|---|---|',
].join('\n');

function buildDocumentHtml(markdown) {
  let html = fs.readFileSync(templatePath, 'utf8');
  html = replaceAll(html, '{{DOC_TITLE}}', '要確認事項コールアウト検証');
  html = replaceAll(html, '{{PORTAL_INDEX_HREF}}', 'index.html');
  html = replaceAll(html, '{{DOC_NAV}}', '');
  html = replaceAll(html, '{{DOC_MARKDOWN_JSON}}', JSON.stringify(markdown).replaceAll('<', '\\u003c'));
  html = replaceAll(
    html,
    '/* TOKENS_CSS */',
    ':root{--mono:monospace;--line:#ccc;--line2:#aaa;--panel:#fff;--panel3:#eee;'
      + '--text:#111;--sub:#222;--muted:#555;--accent:#06c;--accent-soft:#def;'
      + '--head:#eee;--headtext:#111;--code:#111;--codetext:#eee;--stamp:#c60;--stamp-soft:#fed;'
      + '--green:#0a5;--green-soft:#dfd;--sidebar-w:248px;--page-gutter:40px;}',
  );
  html = replaceAll(
    html,
    '/* SHELL_CSS */',
    '.pt{height:100vh;overflow:hidden;display:flex;flex-direction:column;}'
      + '.pt-row{display:flex;flex:1;min-height:0;}'
      + '.pt-sidebar{width:var(--sidebar-w);flex:none;}'
      + '.pt-main{flex:1;min-width:0;overflow-y:auto;padding:0 var(--page-gutter) 72px;}'
      + '.pt-callout{box-shadow:inset 5px 0 0 var(--accent);}'
      + '.pt-callout--warning{box-shadow:inset 5px 0 0 var(--stamp);}'
      + '.pt-callout__icon{display:none;}'
      + '.pt-callout > :first-child > .pt-callout__icon{display:inline-block;}',
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
  var section = document.querySelector('.sec-block');
  var icon = section.querySelector('.pt-callout__icon');
  return JSON.stringify({
    className: section.className,
    hasWarningIcon: !!icon && icon.textContent === 'warning',
    iconIsFirstOfFirstChild: !!icon
      && section.firstElementChild
      && section.firstElementChild.firstElementChild === icon,
    rowCount: section.querySelectorAll('table.data-table tbody tr').length,
  });
})()`;

const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'screen-doc-unresolved-callout-'));
const cleanupFixture = () => fs.rmSync(fixtureRoot, {
  recursive: true,
  force: true,
  maxRetries: 10,
  retryDelay: 100,
});
process.on('exit', cleanupFixture);

const withItemsPath = path.join(fixtureRoot, 'with-items.html');
const emptyPath = path.join(fixtureRoot, 'empty.html');
fs.writeFileSync(withItemsPath, buildDocumentHtml(markdownWithItems));
fs.writeFileSync(emptyPath, buildDocumentHtml(markdownEmpty));

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

    const withItems = await measure(withItemsPath);
    const empty = await measure(emptyPath);

    assert.equal(withItems.rowCount, 1, '1行以上のfixtureで行数を正しく検出する');
    assert.ok(
      withItems.className.split(' ').includes('pt-callout')
        && withItems.className.split(' ').includes('pt-callout--warning'),
      `1行以上でpt-callout pt-callout--warningが付与される: ${withItems.className}`,
    );
    assert.ok(withItems.hasWarningIcon, '警告アイコン(material-symbols warning)が挿入される');
    assert.ok(withItems.iconIsFirstOfFirstChild, 'アイコンが見出し（先頭要素）の先頭に置かれる');

    assert.equal(empty.rowCount, 0, '0行のfixtureで行数を正しく検出する');
    assert.equal(
      empty.className,
      'sec-block',
      `0行ではpt-callout修飾が付かず通常表示のまま: ${empty.className}`,
    );
    assert.ok(!empty.hasWarningIcon, '0行では警告アイコンが挿入されない');

    console.log(
      'PASS: --self-test ケース23（§16要確認事項一覧の行数自動判定によるpt-calloutコールアウト付与・'
      + `1行以上=${withItems.className} / 0行=${empty.className}）`,
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
