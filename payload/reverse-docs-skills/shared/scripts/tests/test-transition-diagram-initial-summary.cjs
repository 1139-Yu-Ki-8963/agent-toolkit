#!/usr/bin/env node
'use strict';

// 写真指摘 1-104 検収方法1: 画面遷移図ページを開いた直後(未選択状態)のDOMに、
// 空でない描画内容(区分別の画面数・遷移数上位の画面のいずれかを含む規模サマリ)が
// 存在することを、実ブラウザ(Chrome DevTools Protocol)でレイアウトを描画して検証する。
// ドロップダウンと案内文だけの状態(修正前の挙動)はFAILとする。
//
// 実データの生成器(build-detail-pages-from-screen-manifest.sh)は edges を常に空配列で
// 出力する(遷移抽出は別工程)。この実態に合わせ、fixture1はedges:[]で規模サマリの
// 「区分別の画面数」のみを検証し、fixture2はedges付きで「遷移数上位の画面」の
// ランキング表示まで検証する。

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

const repoRoot = path.resolve(__dirname, '..', '..', '..');
const builderPath = path.join(repoRoot, 'shared', 'scripts', 'detail-pages', 'build-detail-page.sh');

function node(unitKey, label, category) {
  return { unitKey, label, category, categorySrc: 'url-segment' };
}

// --- fixture1: 実データと同じ形(edges:[])。「区分別の画面数」のみで空でない内容になること ---
const fixture1Nodes = [
  node('a1', '画面A1', '一般'), node('a2', '画面A2', '一般'), node('a3', '画面A3', '一般'),
  node('a4', '画面A4', '一般'), node('a5', '画面A5', '一般'), node('a6', '画面A6', '一般'),
  node('m1', '管理M1', '管理'), node('m2', '管理M2', '管理'),
];
const fixture1Data = {
  pageKind: 'transition',
  generatedAt: '2026-07-30T00:00:00Z',
  manifestContentHash: 'a'.repeat(64),
  manifestScreenCount: 8,
  title: '画面遷移図',
  description: 'self-test用フィクスチャ(edges:0件)',
  legend: [{ symbol: '□', meaning: '画面' }],
  nodes: fixture1Nodes,
  edges: [],
};

// --- fixture2: edges付き。「遷移数上位の画面」ランキングが表示され、
//     最多遷移(画面A1・出次数4)が1位に来ること ---
const fixture2Data = {
  pageKind: 'transition',
  generatedAt: '2026-07-30T00:00:00Z',
  manifestContentHash: 'a'.repeat(64),
  manifestScreenCount: 8,
  title: '画面遷移図',
  description: 'self-test用フィクスチャ(edgesあり)',
  legend: [{ symbol: '□', meaning: '画面' }],
  nodes: fixture1Nodes,
  edges: [
    { from: 'a1', to: 'a2', trigger: 'クリック', sourceRef: 'src/router.tsx:1', confidence: 'high' },
    { from: 'a1', to: 'a3', trigger: 'クリック', sourceRef: 'src/router.tsx:2', confidence: 'high' },
    { from: 'a1', to: 'a4', trigger: 'クリック', sourceRef: 'src/router.tsx:3', confidence: 'high' },
    { from: 'a1', to: 'a5', trigger: 'クリック', sourceRef: 'src/router.tsx:4', confidence: 'high' },
    { from: 'a2', to: 'a3', trigger: 'クリック', sourceRef: 'src/router.tsx:5', confidence: 'high' },
    { from: 'm1', to: 'a1', trigger: 'クリック', sourceRef: 'src/router.tsx:6', confidence: 'high' },
  ],
};

const MEASURE_SCRIPT = `(async function () {
  var deadline = Date.now() + 15000;
  while (
    (document.readyState !== 'complete' || !document.getElementById('view-content'))
    && Date.now() < deadline
  ) {
    await new Promise(function (resolve) { setTimeout(resolve, 20); });
  }
  await new Promise(function (resolve) {
    requestAnimationFrame(function () { requestAnimationFrame(resolve); });
  });
  var vc = document.getElementById('view-content');
  var statGrid = vc.querySelector('.summary-stat-grid');
  var statValues = statGrid
    ? Array.from(statGrid.querySelectorAll('.cov-stat-value')).map(function (e) { return parseInt(e.textContent, 10); })
    : [];
  var statTotal = statValues.reduce(function (a, b) { return a + b; }, 0);
  var rankRows = Array.from(vc.querySelectorAll('.summary-rank-row'));
  var onlyPlaceholder = vc.children.length === 1
    && vc.children[0].classList.contains('diagram-empty')
    && !statGrid
    && !vc.querySelector('.summary-rank-table');
  return JSON.stringify({
    childCount: vc.children.length,
    statTotal: statTotal,
    statCount: statValues.length,
    rankRowCount: rankRows.length,
    rankFirstText: rankRows.length > 0 ? rankRows[0].textContent.trim() : '',
    onlyPlaceholder: onlyPlaceholder,
    textLength: vc.textContent.trim().length,
  });
})()`;

const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'transition-initial-summary-'));
const cleanupFixture = () => fs.rmSync(fixtureRoot, {
  recursive: true,
  force: true,
  maxRetries: 10,
  retryDelay: 100,
});
process.on('exit', cleanupFixture);

function buildTransitionPage(data, dirName) {
  const dataDir = path.join(fixtureRoot, dirName);
  fs.mkdirSync(dataDir, { recursive: true });
  const dataPath = path.join(dataDir, 'page-data.json');
  fs.writeFileSync(dataPath, JSON.stringify(data));
  const outputDir = path.join(dataDir, 'out');
  execFileSync('bash', [
    builderPath, dataPath, outputDir,
    '--page', 'transition',
    '--generated-at', data.generatedAt,
  ], { stdio: 'pipe' });
  return path.join(outputDir, '画面遷移図.html');
}

(async () => {
  let browser;
  let cdp;
  try {
    const fixture1Path = buildTransitionPage(fixture1Data, 'fixture1');
    const fixture2Path = buildTransitionPage(fixture2Data, 'fixture2');

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
      '--window-size=1280,900',
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

    const result1 = await measure(fixture1Path);
    const result2 = await measure(fixture2Path);

    // fixture1(edges:0件): 区分別の画面数(8画面・一般6+管理2)が表示され、
    // プレースホルダ文のみの状態(修正前の挙動)ではないこと
    assert.equal(result1.onlyPlaceholder, false, 'fixture1: 案内文のみの空状態ではない');
    assert.equal(result1.statCount, 2, 'fixture1: 区分(一般・管理)が2件表示される');
    assert.equal(result1.statTotal, 8, 'fixture1: 区分別の画面数の合計がnodes総数(8)と一致する');
    assert.ok(result1.textLength > 30, `fixture1: 描画テキストが十分な分量を持つ: ${result1.textLength}文字`);

    // fixture2(edgesあり): 遷移数上位の画面ランキングが表示され、最多遷移(画面A1・4件)が1位
    assert.equal(result2.onlyPlaceholder, false, 'fixture2: 案内文のみの空状態ではない');
    assert.equal(result2.statTotal, 8, 'fixture2: 区分別の画面数の合計がnodes総数(8)と一致する');
    assert.ok(result2.rankRowCount > 0, 'fixture2: 遷移数上位の画面ランキングが表示される');
    assert.ok(
      result2.rankFirstText.includes('画面A1') && result2.rankFirstText.includes('4件'),
      `fixture2: ランキング1位が最多遷移(画面A1・4件)である: ${result2.rankFirstText}`,
    );

    console.log(
      'PASS: --self-test ケース30（画面遷移図の初期DOMに空でない規模サマリが存在する。'
      + `fixture1: 区分${result1.statCount}件・合計${result1.statTotal}画面 / `
      + `fixture2: ランキング${result2.rankRowCount}件・1位「${result2.rankFirstText}」）`,
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
