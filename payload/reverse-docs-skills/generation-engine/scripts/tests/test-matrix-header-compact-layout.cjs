#!/usr/bin/env node
'use strict';

if (typeof WebSocket !== 'function' && !process.env.__WS_RETRY) {
  const { spawnSync } = require('node:child_process');
  const r = spawnSync(process.execPath,
    ['--experimental-websocket', __filename, ...process.argv.slice(2)],
    { stdio: 'inherit', env: { ...process.env, __WS_RETRY: '1' } });
  process.exit(r.status === null ? 1 : r.status);
}

// 改善課題1-105 検収: 権限×機能マトリクス・権限×画面マトリクス・CRUD図(機能×テーブル)の
// 3種で、列数が閾値(8列)以下の合成データを与えたとき
//   (1) ヘッダ行の高さが通常データ行の高さの3.0倍以下であること
//   (2) 左上見出しセル(機能名/画面/機能＼テーブル)の文字色対背景色のコントラスト比が
//       4.5以上であること
//   (3) CRUD図の機能名列が220pxで固定され、長い機能名が複数行に折り返されること
// を実描画(CDP)で検証する。
//
// 実測済みの不具合(playwright/CDPで確認): 列数によらず常に縦書き回転
// (writing-mode: vertical-rl) + height固定(130px/150px)を適用していたため、
// 列が少ないデータでもヘッダ行が過大な高さになり、かつ左上見出しセルは
// background だけ var(--panel) で上書きし color を再指定していなかったため
// ヘッダ帯用の明るい文字色(var(--headtext))がそのまま乗ってコントラストが崩れていた。
// 本テストは、8列以下では水平見出し・自動高さへ切り替わり、左上見出しセルに
// color: var(--text) が効いていることの回帰保証を行う。
//
// test-er-diagram-hub-card-font-size.cjs と同じChromeバイナリ探索・CDP接続の
// 実装パターンをそのまま踏襲する。

const assert = require('node:assert/strict');
const { execFileSync, spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { findCachedBrowser } = require('./lib/find-cached-browser.cjs');
const { BrowserUnavailableError, markUnavailable, reportIfUnavailable } = require('./lib/browser-unavailable.cjs');

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
      reject(markUnavailable(new Error('Chrome/Chromiumのデバッグ接続先を15秒以内に取得できませんでした')));
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
      reject(markUnavailable(error));
    });
    browser.on('close', (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(markUnavailable(new Error(`Chrome/Chromiumの起動に失敗しました（exit ${code}）\n${stderr}`)));
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
      reject(markUnavailable(new Error('Chrome DevTools Protocolへ15秒以内に接続できませんでした')));
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
      if (!connected) reject(markUnavailable(error));
    });
    socket.addEventListener('close', () => {
      clearTimeout(timeout);
      const error = new Error('Chrome DevTools Protocolとの接続が切断されました');
      rejectPending(error);
      if (!connected) reject(markUnavailable(error));
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

// --- WCAG相対輝度・コントラスト比(Node側で最終判定に使う) ---
function relLum(r, g, b) {
  const chans = [r, g, b].map((c) => {
    c = c / 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * chans[0] + 0.7152 * chans[1] + 0.0722 * chans[2];
}
function contrastRatio(rgb1, rgb2) {
  const l1 = relLum(rgb1.r, rgb1.g, rgb1.b);
  const l2 = relLum(rgb2.r, rgb2.g, rgb2.b);
  const lighter = Math.max(l1, l2);
  const darker = Math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

const repoRoot = path.resolve(__dirname, '..', '..', '..');
const builderPath = path.join(repoRoot, 'generation-engine', 'scripts', 'matrix', 'build-matrix-pages.sh');

// --- 検証対象3種の合成フィクスチャ(列数は8以下=デフォルト水平見出しになる想定) ---
const CASES = [
  {
    pageType: 'permission-function',
    label: '権限×機能マトリクス',
    leftTopSelector: 'thead th.fn-col',
    data: {
      generatedAt: '2026-01-01T00:00:00Z',
      dataSource: 'self-test用フィクスチャ',
      roles: [
        { key: 'admin', name: '管理者' },
        { key: 'guest', name: 'ゲスト' },
      ],
      functions: [
        { functionKey: 'user-edit', functionName: 'ユーザー編集', category: 'ユーザー管理', permissions: { admin: 'CRUD', guest: '----' } },
        { functionKey: 'user-view', functionName: 'ユーザー閲覧', category: 'ユーザー管理', permissions: { admin: 'CRUD', guest: '-R--' } },
        { functionKey: 'order-edit', functionName: '注文編集', category: '注文管理', permissions: { admin: 'CRUD', guest: '----' } },
      ],
    },
  },
  {
    pageType: 'permission-screen',
    label: '権限×画面マトリクス',
    leftTopSelector: 'thead th.screen-col',
    data: {
      generatedAt: '2026-01-01T00:00:00Z',
      dataSource: 'self-test用フィクスチャ',
      roles: ['管理者', '一般'],
      screens: [
        { screenId: 'login', screenName: 'ログイン', route: '/login', permissions: { 管理者: true, 一般: true } },
        { screenId: 'admin-top', screenName: '管理トップ', route: '/admin', permissions: { 管理者: true, 一般: false } },
        { screenId: 'audit-log', screenName: '監査ログ', route: '/admin/audit', permissions: null },
      ],
    },
  },
  {
    pageType: 'crud',
    label: 'CRUD図(機能×テーブル)',
    leftTopSelector: 'thead th.feature-col',
    data: {
      generatedAt: '2026-01-01T00:00:00Z',
      dataSource: 'self-test用フィクスチャ',
      tables: [
        { physicalName: 'users', logicalName: 'ユーザー' },
        { physicalName: 'orders', logicalName: '注文' },
      ],
      features: [
        { featureId: 'user-manage', featureName: 'ユーザー情報を検索して確認し権限に応じて更新する管理機能', cells: { users: 'CRUD', orders: '' } },
        { featureId: 'order-manage', featureName: '注文管理', cells: { users: 'R---', orders: 'CRUD' } },
        { featureId: 'report', featureName: '帳票出力', cells: { users: 'R---', orders: 'R---' } },
      ],
    },
  },
];

const RATIO_MAX = 3.0;
const CONTRAST_MIN = 4.5;

function measureScript(leftTopSelector) {
  return `(async function () {
    var deadline = Date.now() + 15000;
    while (
      (document.readyState !== 'complete' || !document.querySelector('thead tr') || !document.querySelector('tbody tr'))
      && Date.now() < deadline
    ) {
      await new Promise(function (resolve) { setTimeout(resolve, 20); });
    }
    /* 左上見出しセルのコントラスト崩れ(改善課題1-105)はライトテーマの --headtext(#F1F4F8)が
       --panel(#FFFFFF)に乗る組合せで顕在化する。ダークテーマの既定値では --headtext と --text が
       近似しコントラスト崩れを再現できないため、計測前に明示的にライトテーマへ切り替える。 */
    document.documentElement.setAttribute('data-theme', 'light');
    for (var i = 0; i < 4; i += 1) {
      await new Promise(function (resolve) { requestAnimationFrame(resolve); });
    }
    function parseColor(str) {
      var m = str && str.match(/rgba?\\(([^)]+)\\)/);
      if (!m) return null;
      var parts = m[1].split(',').map(function (s) { return parseFloat(s.trim()); });
      return { r: parts[0], g: parts[1], b: parts[2], a: parts.length > 3 ? parts[3] : 1 };
    }
    function findBg(el) {
      var node = el;
      while (node) {
        var cs = getComputedStyle(node);
        var c = parseColor(cs.backgroundColor);
        if (c && c.a > 0) return c;
        node = node.parentElement;
      }
      return { r: 255, g: 255, b: 255, a: 1 };
    }
    var theadTr = document.querySelector('thead tr');
    var bodyRows = Array.prototype.slice.call(document.querySelectorAll('tbody tr')).slice(0, 3);
    var theadHeight = theadTr ? theadTr.getBoundingClientRect().height : null;
    var bodyHeights = bodyRows.map(function (tr) { return tr.getBoundingClientRect().height; });
    var avgBodyHeight = bodyHeights.length > 0
      ? (bodyHeights.reduce(function (a, b) { return a + b; }, 0) / bodyHeights.length)
      : null;
    var leftTop = document.querySelector(${JSON.stringify(leftTopSelector)});
    var leftTopColor = leftTop ? parseColor(getComputedStyle(leftTop).color) : null;
    var leftTopBg = leftTop ? findBg(leftTop) : null;
    var featureName = document.querySelector('td.feature-name');
    var featureNameStyle = featureName ? getComputedStyle(featureName) : null;
    var featureNameRect = featureName ? featureName.getBoundingClientRect() : null;
    var featureNameLineHeight = featureNameStyle
      ? (parseFloat(featureNameStyle.lineHeight) || parseFloat(featureNameStyle.fontSize) * 1.2)
      : null;
    return JSON.stringify({
      theadHeight: theadHeight,
      avgBodyHeight: avgBodyHeight,
      bodyRowCount: bodyRows.length,
      leftTopColor: leftTopColor,
      leftTopBg: leftTopBg,
      featureNameWidth: featureNameRect ? featureNameRect.width : null,
      featureNameHeight: featureNameRect ? featureNameRect.height : null,
      featureNameLineHeight: featureNameLineHeight,
      featureNameWhiteSpace: featureNameStyle ? featureNameStyle.whiteSpace : null,
    });
  })()`;
}

const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'matrix-header-compact-layout-'));
const cleanupFixture = () => fs.rmSync(fixtureRoot, {
  recursive: true,
  force: true,
  maxRetries: 10,
  retryDelay: 100,
});
process.on('exit', cleanupFixture);

function buildMatrixPage(caseDef) {
  const dataPath = path.join(fixtureRoot, `${caseDef.pageType}-data.json`);
  const outPath = path.join(fixtureRoot, `${caseDef.pageType}-out.html`);
  fs.writeFileSync(dataPath, JSON.stringify(caseDef.data));
  execFileSync('bash', [builderPath, caseDef.pageType, dataPath, outPath], { stdio: 'pipe' });
  return outPath;
}

(async () => {
  let browser;
  let cdp;
  const failures = [];
  const reports = [];
  try {
    const browserPath = findBrowser();
    if (browserPath === '') {
      throw markUnavailable(new Error('ChromeまたはChromiumの実行ファイルを検出できない'));
    }
    const launched = await launchBrowser(browserPath, [
      '--headless=new',
      '--no-sandbox',
      '--disable-gpu',
      '--disable-background-networking',
      '--no-first-run',
      '--no-default-browser-check',
      '--allow-file-access-from-files',
      '--window-size=1440,900',
      `--user-data-dir=${path.join(fixtureRoot, 'browser-profile')}`,
      '--remote-debugging-port=0',
      'about:blank',
    ]);
    browser = launched.browser;
    cdp = await connectCdp(launched.websocketUrl);

    const target = await cdp.send('Target.createTarget', { url: 'about:blank' });
    const attached = await cdp.send('Target.attachToTarget', {
      targetId: target.targetId,
      flatten: true,
    });
    const sessionId = attached.sessionId;
    await cdp.send('Runtime.enable', {}, sessionId);
    await cdp.send('Page.enable', {}, sessionId);
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: 1440,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false,
    }, sessionId);

    for (const caseDef of CASES) {
      const outPath = buildMatrixPage(caseDef);
      await cdp.send('Page.navigate', { url: `file://${outPath}` }, sessionId);
      const evaluated = await cdp.send('Runtime.evaluate', {
        expression: measureScript(caseDef.leftTopSelector),
        awaitPromise: true,
        returnByValue: true,
      }, sessionId);
      assert.equal(evaluated.exceptionDetails, undefined, `DOM計測を実行できる: ${outPath}`);
      const result = JSON.parse(evaluated.result.value);

      if (result.theadHeight == null || result.avgBodyHeight == null || !(result.avgBodyHeight > 0)) {
        failures.push(`${caseDef.label}: ヘッダ行またはデータ行の高さを計測できなかった(thead=${result.theadHeight}, avgBody=${result.avgBodyHeight})`);
        continue;
      }
      if (!result.leftTopColor || !result.leftTopBg) {
        failures.push(`${caseDef.label}: 左上見出しセル(${caseDef.leftTopSelector})の色を計測できなかった`);
        continue;
      }

      const ratio = result.theadHeight / result.avgBodyHeight;
      const contrast = contrastRatio(result.leftTopColor, result.leftTopBg);
      reports.push(
        `${caseDef.label}: ヘッダ高さ${result.theadHeight.toFixed(1)}px / データ行平均高さ${result.avgBodyHeight.toFixed(1)}px `
        + `(比率${ratio.toFixed(2)}倍) / 左上見出しコントラスト比${contrast.toFixed(2)}`,
      );

      if (!(ratio <= RATIO_MAX)) {
        failures.push(`${caseDef.label}: ヘッダ行/データ行の高さ比率が基準(${RATIO_MAX}倍以下)を超過: ${ratio.toFixed(2)}倍`);
      }
      if (!(contrast >= CONTRAST_MIN)) {
        failures.push(`${caseDef.label}: 左上見出しセルのコントラスト比が基準(${CONTRAST_MIN}以上)を下回る: ${contrast.toFixed(2)}`);
      }
      if (caseDef.pageType === 'crud') {
        reports.push(
          `${caseDef.label}: 機能名列幅${result.featureNameWidth?.toFixed(1)}px / `
          + `セル高さ${result.featureNameHeight?.toFixed(1)}px / white-space=${result.featureNameWhiteSpace}`,
        );
        if (Math.abs(result.featureNameWidth - 220) > 1) {
          failures.push(`${caseDef.label}: 機能名列幅が220pxでない: ${result.featureNameWidth}px`);
        }
        if (result.featureNameWhiteSpace !== 'normal') {
          failures.push(`${caseDef.label}: 機能名列のwhite-spaceがnormalでない: ${result.featureNameWhiteSpace}`);
        }
        if (!(result.featureNameHeight > result.featureNameLineHeight * 1.5)) {
          failures.push(
            `${caseDef.label}: 長い機能名が複数行に折り返されない: `
            + `高さ${result.featureNameHeight}px / 行高${result.featureNameLineHeight}px`,
          );
        }
      }
    }

    await cdp.send('Target.closeTarget', { targetId: target.targetId });

    reports.forEach((line) => console.log(`INFO: ${line}`));

    if (failures.length > 0) {
      failures.forEach((line) => console.error(`FAIL: ${line}`));
      process.exitCode = 1;
    } else {
      console.log(
        'PASS: 権限×機能マトリクス・権限×画面マトリクス・CRUD図の3種すべてで、'
        + `列数8以下ではヘッダ行/データ行の高さ比率が${RATIO_MAX}倍以下、`
        + `左上見出しセルのコントラスト比が${CONTRAST_MIN}以上を満たし、`
        + 'CRUD図の機能名列が220pxで長い機能名を折り返す',
      );
    }
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
  if (reportIfUnavailable(error)) {
    process.exitCode = 2;
    return;
  }
  console.error(error);
  process.exitCode = 1;
});
