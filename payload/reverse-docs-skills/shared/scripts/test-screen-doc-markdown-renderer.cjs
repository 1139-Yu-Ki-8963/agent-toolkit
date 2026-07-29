#!/usr/bin/env node
'use strict';

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

const repoRoot = path.resolve(__dirname, '..', '..');
const templatePath = path.join(repoRoot, 'shared', 'templates', 'screen-doc-template.html');

const fencedBlocks = [
  '# コメントとして表示する',
  '┌─ Component ─┐\n└───────────────┘',
  '~~取り消し線にしない~~',
  '---',
  '| テーブルに | しない |',
  '- リストにしない',
  '> 引用にしない',
  '<script>window.__fenceScriptExecuted=true</script>',
];

const markdown = [
  '# コードフェンス検証',
  '',
  ...fencedBlocks.flatMap((block, index) => [
    index === 0 ? '```text' : '```',
    block,
    '```',
    '',
  ]),
].join('\n');

function replaceAll(source, token, value) {
  return source.split(token).join(value);
}

const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'screen-doc-markdown-'));
const cleanupFixture = () => fs.rmSync(fixtureRoot, {
  recursive: true,
  force: true,
  maxRetries: 10,
  retryDelay: 100,
});
process.on('exit', cleanupFixture);

let documentHtml = fs.readFileSync(templatePath, 'utf8');
documentHtml = replaceAll(documentHtml, '{{DOC_TITLE}}', 'コードフェンス検証');
documentHtml = replaceAll(documentHtml, '{{PORTAL_INDEX_HREF}}', 'index.html');
documentHtml = replaceAll(documentHtml, '{{DOC_NAV}}', '');
documentHtml = replaceAll(
  documentHtml,
  '{{DOC_MARKDOWN_JSON}}',
  JSON.stringify(markdown).replaceAll('<', '\\u003c'),
);
documentHtml = replaceAll(
  documentHtml,
  '/* TOKENS_CSS */',
  ':root{--mono:monospace;--line:#ccc;--line2:#aaa;--panel:#fff;--panel3:#eee;--text:#111;--sub:#222;--muted:#555;--accent:#06c;--head:#eee;--headtext:#111;--code:#111;--codetext:#eee;--stamp:#06c;}',
);
documentHtml = replaceAll(documentHtml, '/* SHELL_CSS */', '');
documentHtml = replaceAll(documentHtml, '<!--SHELL_SIDEBAR-->', '');
documentHtml = replaceAll(documentHtml, '<!--SHELL_FOOTER-->', '');

const fixtureHtmlPath = path.join(fixtureRoot, 'code-fence-dom-test.html');
const browserProfilePath = path.join(fixtureRoot, 'browser-profile');
fs.writeFileSync(fixtureHtmlPath, documentHtml);

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
      `--user-data-dir=${browserProfilePath}`,
      '--remote-debugging-port=0',
      'about:blank',
    ]);
    browser = launched.browser;
    cdp = await connectCdp(launched.websocketUrl);
    const target = await cdp.send('Target.createTarget', {
      url: `file://${fixtureHtmlPath}`,
    });
    const attached = await cdp.send('Target.attachToTarget', {
      targetId: target.targetId,
      flatten: true,
    });
    await cdp.send('Runtime.enable', {}, attached.sessionId);
    const evaluated = await cdp.send('Runtime.evaluate', {
      expression: `(async function () {
        var deadline = Date.now() + 15000;
        while (
          (document.readyState !== 'complete' || !document.getElementById('doc-content'))
          && Date.now() < deadline
        ) {
          await new Promise(function (resolve) { setTimeout(resolve, 20); });
        }
        var container = document.getElementById('doc-content');
        if (!container) throw new Error('doc-contentが見つかりません');
        var code = container.querySelector('pre > code');
        return JSON.stringify({
          text: container.textContent,
          codeTexts: Array.from(container.querySelectorAll('pre > code'), function (element) {
            return element.textContent;
          }),
          preCount: container.querySelectorAll('pre').length,
          headingCount: container.querySelectorAll('h1,h2,h3,h4,h5,h6').length,
          strikeCount: container.querySelectorAll('del,s,strike').length,
          scriptCount: container.querySelectorAll('script').length,
          scriptExecuted: window.__fenceScriptExecuted === true,
          codeFont: code ? getComputedStyle(code).fontFamily : ''
        });
      })()`,
      awaitPromise: true,
      returnByValue: true,
    }, attached.sessionId);
    assert.equal(evaluated.exceptionDetails, undefined, '実行後DOMを評価できる');
    const actual = JSON.parse(evaluated.result.value);

    assert.equal(actual.text.includes('```'), false, 'フェンス記号を画面へ露出しない');
    assert.equal(actual.preCount, fencedBlocks.length, '全フェンスをpre要素へ格納する');
    assert.deepEqual(actual.codeTexts, fencedBlocks, 'フェンス内の文字列と改行を保持する');
    assert.equal(actual.headingCount, 0, 'フェンス内の#行を見出し化しない');
    assert.equal(actual.strikeCount, 0, 'フェンス内の~~を取り消し線化しない');
    assert.equal(actual.scriptCount, 0, 'フェンス内のHTMLを要素化しない');
    assert.equal(actual.scriptExecuted, false, 'フェンス内のスクリプトを実行しない');
    assert.match(actual.codeFont, /monospace/i, 'コードを等幅表示する');

    console.log('PASS: 画面設計書MarkdownコードフェンスDOM検収（8フェンス）');
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
