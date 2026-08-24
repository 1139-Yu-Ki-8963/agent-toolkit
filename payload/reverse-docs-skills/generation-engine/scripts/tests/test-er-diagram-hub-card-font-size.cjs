#!/usr/bin/env node
'use strict';

if (typeof WebSocket !== 'function' && !process.env.__WS_RETRY) {
  const { spawnSync } = require('node:child_process');
  const r = spawnSync(process.execPath,
    ['--experimental-websocket', __filename, ...process.argv.slice(2)],
    { stdio: 'inherit', env: { ...process.env, __WS_RETRY: '1' } });
  process.exit(r.status === null ? 1 : r.status);
}

// 写真指摘 1-104 検収方法2: 1ハブに200テーブルを持つ合成データでER図を生成し、
// 巨大ハブのクラスタ概観カード内の最小フォントサイズが10px以上であることを検証する。
//
// ER図はCanvas 2D(<canvas id="er-canvas-el">)へclient-sideで描画するため、実DOMの
// text要素は存在せずgetComputedStyleでは計測できない。そのため
// CanvasRenderingContext2D.prototype.fillText をページ読込前に計装(instrument)し、
// 実際に描画命令へ渡された ctx.font 文字列からpx値を抽出して計測する。
// これはDOM計測(getComputedStyle)と同じ検証意図(実際に描画されるフォントサイズの下限)を、
// Canvas描画という実装技術に合わせて代替した手法である。
//
// 調査済みの現状(detail-t6-er.html): クラスタ概観カード(drawClusterCard)のフォントは
// 15px/11px/11px(bold)/10pxの固定値で、メンバー数に応じて縮小するロジックは存在しない。
// 名称列挙は clusterMemberNamesTruncated が測定幅で打ち切り、全列挙はしない。
// 巨大クラスタへの「展開操作」は enterExpand (クリックでドリルダウン)として既存実装済み。
// 本テストはこれらの既存実装が200テーブル規模でも成立することの回帰保証を追加する。

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

const repoRoot = path.resolve(__dirname, '..', '..', '..');
const builderPath = path.join(repoRoot, 'generation-engine', 'scripts', 'detail-pages', 'build-detail-page.sh');

// --- 合成データ: 1ハブ(hub)にスポーク199件(=クラスタ計200件) + 孤立エンティティ150件 ---
// 孤立エンティティは、巨大成分がhub分割(出次数上位3ノードへの分解)されない比率(<=0.6)を
// 維持するための調整用(200/(200+150)=0.571)。分割されると単一ハブ200件の条件を満たさない。
const SPOKE_COUNT = 199;
const ISOLATED_COUNT = 150;
const entities = [{ key: 'hub', label: 'ハブテーブル' }];
const relations = [];
for (let i = 1; i <= SPOKE_COUNT; i += 1) {
  const key = `spoke${i}`;
  entities.push({ key, label: `スポークテーブル${i}` });
  relations.push({ from: 'hub', to: key, cardinality: '1:N', sourceRef: 'db/schema.sql:1' });
}
for (let i = 1; i <= ISOLATED_COUNT; i += 1) {
  entities.push({ key: `iso${i}`, label: `孤立テーブル${i}` });
}

const erData = {
  pageKind: 'er',
  generatedAt: '2026-07-30T00:00:00Z',
  title: 'ER図',
  description: 'self-test用フィクスチャ(1ハブ200テーブル)',
  legend: [{ symbol: '━', meaning: 'リレーション' }],
  entities,
  relations,
};

const INSTRUMENT_SCRIPT = `(function () {
  window.__fillTextLog = [];
  var proto = CanvasRenderingContext2D.prototype;
  var orig = proto.fillText;
  proto.fillText = function (text) {
    window.__fillTextLog.push({ text: String(text), font: this.font });
    return orig.apply(this, arguments);
  };
})();`;

const MEASURE_SCRIPT = `(async function () {
  var deadline = Date.now() + 15000;
  while (
    (document.readyState !== 'complete' || !document.getElementById('er-canvas-el'))
    && Date.now() < deadline
  ) {
    await new Promise(function (resolve) { setTimeout(resolve, 20); });
  }
  for (var i = 0; i < 6; i += 1) {
    await new Promise(function (resolve) { requestAnimationFrame(resolve); });
  }
  var log = window.__fillTextLog || [];
  var fontSizes = log.map(function (entry) {
    var m = entry.font.match(/(\\d+(?:\\.\\d+)?)px/);
    return m ? parseFloat(m[1]) : null;
  }).filter(function (v) { return v !== null; });
  var hubCountEntry = log.find(function (entry) { return /^テーブル\\d+件/.test(entry.text); });
  return JSON.stringify({
    logCount: log.length,
    minFontSize: fontSizes.length > 0 ? Math.min.apply(null, fontSizes) : null,
    hubCountText: hubCountEntry ? hubCountEntry.text : null,
  });
})()`;

const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'er-hub-card-font-size-'));
const cleanupFixture = () => fs.rmSync(fixtureRoot, {
  recursive: true,
  force: true,
  maxRetries: 10,
  retryDelay: 100,
});
process.on('exit', cleanupFixture);

function buildErPage(data) {
  const dataDir = path.join(fixtureRoot, 'fixture');
  fs.mkdirSync(dataDir, { recursive: true });
  const dataPath = path.join(dataDir, 'page-data.json');
  fs.writeFileSync(dataPath, JSON.stringify(data));
  const outputDir = path.join(dataDir, 'out');
  execFileSync('bash', [
    builderPath, dataPath, outputDir,
    '--page', 'er',
    '--generated-at', data.generatedAt,
  ], { stdio: 'pipe' });
  return path.join(outputDir, 'ER図.html');
}

(async () => {
  let browser;
  let cdp;
  try {
    const erPath = buildErPage(erData);

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
      '--window-size=1280,900',
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
    // fillTextの計装はアプリのスクリプトが走る前に仕込む必要があるため、
    // ナビゲーション前にaddScriptToEvaluateOnNewDocumentで登録する。
    await cdp.send('Page.addScriptToEvaluateOnNewDocument', { source: INSTRUMENT_SCRIPT }, sessionId);
    await cdp.send('Page.navigate', { url: `file://${erPath}` }, sessionId);

    const evaluated = await cdp.send('Runtime.evaluate', {
      expression: MEASURE_SCRIPT,
      awaitPromise: true,
      returnByValue: true,
    }, sessionId);
    assert.equal(evaluated.exceptionDetails, undefined, `DOM/Canvas計測を実行できる: ${erPath}`);
    const result = JSON.parse(evaluated.result.value);
    await cdp.send('Target.closeTarget', { targetId: target.targetId });

    assert.ok(result.logCount > 0, `fillTextの描画ログが記録される: ${result.logCount}件`);
    assert.notEqual(result.hubCountText, null, 'クラスタ概観カードに「テーブルN件」の表記が描画される');
    assert.ok(
      result.hubCountText && result.hubCountText.includes(`テーブル${SPOKE_COUNT + 1}件`),
      `巨大成分がhub分割(3分割)されず1クラスタ${SPOKE_COUNT + 1}件のままである: ${result.hubCountText}`,
    );
    assert.notEqual(result.minFontSize, null, 'カード内フォントサイズを計測できる');
    assert.ok(
      result.minFontSize >= 10,
      `巨大ハブのクラスタカード内、最小フォントサイズが10px以上: ${result.minFontSize}px`,
    );

    console.log(
      `PASS: --self-test ケース31（ER図の巨大ハブ(${SPOKE_COUNT + 1}テーブル)カード内、`
      + `最小フォントサイズ${result.minFontSize}px。既存のclusterMemberNamesTruncated打ち切りと`
      + `固定フォント指定により10px下限を維持）`,
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
  if (reportIfUnavailable(error)) {
    process.exitCode = 2;
    return;
  }
  console.error(error);
  process.exitCode = 1;
});
