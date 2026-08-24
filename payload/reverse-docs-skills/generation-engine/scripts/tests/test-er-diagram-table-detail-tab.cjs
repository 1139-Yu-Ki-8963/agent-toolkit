#!/usr/bin/env node
'use strict';

if (typeof WebSocket !== 'function' && !process.env.__WS_RETRY) {
  const { spawnSync } = require('node:child_process');
  const r = spawnSync(process.execPath,
    ['--experimental-websocket', __filename, ...process.argv.slice(2)],
    { stdio: 'inherit', env: { ...process.env, __WS_RETRY: '1' } });
  process.exit(r.status === null ? 1 : r.status);
}

// ER図へ新設した「テーブル詳細」タブの検収。
//
// 判定2: 関連数が最も多いテーブル(本テストの合成データでは"hub")を選んだとき、
// 描画されたカード(.er-tc-card)の矩形が互いに重ならないこと。
// 判定3: タブを切り替えて戻したとき、選択されたテーブルと検索語が保たれること。
//
// 「テーブル詳細」タブはCanvasではなく実DOM(position:absoluteのカード+SVG接続線)で
// 描画するため、getBoundingClientRect()による実測で判定できる(判定2は目分量ではなく
// 実際に描画された矩形同士の交差を計算して判定する)。

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

// --- 合成データ: hub(スポーク12件と接続。関連数=12で最多) + spoke12件(各関連数=1)。
// スポークのカラム数を意図的にばらつかせ(3〜9件)、カード高さが不揃いでも
// 円状配置の半径計算(実測した対角線サイズの最大値に基づく)が重なりを防ぐことを検証する。
const SPOKE_COUNT = 12;
function makeColumns(n) {
  const cols = [{ name: 'id', type: 'BIGINT', pk: true }];
  for (let i = 1; i < n; i += 1) {
    cols.push({ name: `col_${i}`, type: 'VARCHAR(100)', nullable: i % 2 === 0 });
  }
  return cols;
}
const entities = [{ key: 'hub', label: 'ハブテーブル', columns: makeColumns(8) }];
const relations = [];
for (let i = 1; i <= SPOKE_COUNT; i += 1) {
  const key = `spoke${i}`;
  const colCount = 3 + (i % 7); // 3〜9件でばらつかせる
  entities.push({ key, label: `スポークテーブル${i}`, columns: makeColumns(colCount) });
  relations.push({ from: 'hub', to: key, cardinality: '1:N', sourceRef: 'db/schema.sql:1' });
}
// hub以外に関連数の少ないテーブル対を1組追加し、「関連数が最も多いテーブル」が
// hubであることが一意に定まるようにする(誤って別テーブルを検査対象にしない保証)。
entities.push({ key: 'aux_a', label: '補助テーブルA', columns: makeColumns(2) });
entities.push({ key: 'aux_b', label: '補助テーブルB', columns: makeColumns(2) });
relations.push({ from: 'aux_a', to: 'aux_b', cardinality: '1:1', sourceRef: 'db/schema.sql:2' });

const erData = {
  pageKind: 'er',
  generatedAt: '2026-08-01T00:00:00Z',
  title: 'ER図',
  description: 'self-test用フィクスチャ(テーブル詳細タブ検証: hub+スポーク12件+補助2件)',
  legend: [{ symbol: '━', meaning: 'リレーション' }],
  entities,
  relations,
};

const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'er-table-detail-tab-'));
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

// ブラウザ内で実行する測定スクリプト。
// 手順:
//   1. 「テーブル詳細」タブへ切り替える
//   2. 検索欄に「ハブ」と入力し、候補から hub を選ぶ
//   3. 描画された .er-tc-card 全件の矩形を実測する(判定2用)
//   4. 検索語・選択中カードの値を控えたうえで「関連図」タブへ戻り、再度
//      「テーブル詳細」タブへ戻して、検索欄の値と中心カードのdata-keyが
//      保たれているかを確認する(判定3用)
const MEASURE_SCRIPT = `(async function () {
  function wait(ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); }
  function fireInput(elm, value) {
    elm.value = value;
    elm.dispatchEvent(new Event('input', { bubbles: true }));
  }
  var deadline = Date.now() + 15000;
  while (
    (document.readyState !== 'complete' || !document.getElementById('er-tab-btn-detail'))
    && Date.now() < deadline
  ) {
    await wait(20);
  }

  var tabBtnDetail = document.getElementById('er-tab-btn-detail');
  var tabBtnDiagram = document.getElementById('er-tab-btn-diagram');
  if (!tabBtnDetail || !tabBtnDiagram) {
    return JSON.stringify({ error: 'tab-buttons-not-found' });
  }

  tabBtnDetail.click();
  await wait(60);

  var searchInput = document.getElementById('er-detail-search-input');
  var searchTerm = 'ハブ';
  fireInput(searchInput, searchTerm);
  await wait(60);

  var results = document.querySelectorAll('#er-detail-search-results .er-search-item');
  var target = null;
  for (var i = 0; i < results.length; i += 1) {
    if (results[i].textContent.indexOf('hub') !== -1) { target = results[i]; break; }
  }
  if (!target) {
    return JSON.stringify({ error: 'hub-not-found-in-search-results', resultCount: results.length });
  }
  target.click();
  await wait(60);

  var cards = document.querySelectorAll('#er-detail-canvas .er-tc-card');
  var rects = Array.prototype.map.call(cards, function (c) {
    var r = c.getBoundingClientRect();
    return { key: c.getAttribute('data-key'), isCenter: c.classList.contains('er-tc-card--center'), x: r.left, y: r.top, w: r.width, h: r.height };
  });
  var centerCardEl = document.querySelector('#er-detail-canvas .er-tc-card--center');
  var centerKeyBefore = centerCardEl ? centerCardEl.getAttribute('data-key') : null;
  var searchValueBefore = searchInput.value;

  // 判定3: タブを切り替えて戻す
  tabBtnDiagram.click();
  await wait(60);
  tabBtnDetail.click();
  await wait(60);

  var searchValueAfter = document.getElementById('er-detail-search-input').value;
  var centerAfterEl = document.querySelector('#er-detail-canvas .er-tc-card--center');
  var centerKeyAfter = centerAfterEl ? centerAfterEl.getAttribute('data-key') : null;
  var cardCountAfter = document.querySelectorAll('#er-detail-canvas .er-tc-card').length;

  return JSON.stringify({
    rects: rects,
    cardCount: cards.length,
    centerKeyBefore: centerKeyBefore,
    searchValueBefore: searchValueBefore,
    searchValueAfter: searchValueAfter,
    centerKeyAfter: centerKeyAfter,
    cardCountAfter: cardCountAfter
  });
})()`;

function rectsOverlap(a, b) {
  const overlapX = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
  const overlapY = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
  return overlapX > 0.5 && overlapY > 0.5;
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
    await cdp.send('Page.navigate', { url: `file://${erPath}` }, sessionId);

    const evaluated = await cdp.send('Runtime.evaluate', {
      expression: MEASURE_SCRIPT,
      awaitPromise: true,
      returnByValue: true,
    }, sessionId);
    assert.equal(evaluated.exceptionDetails, undefined, `DOM計測を実行できる: ${erPath}`);
    const result = JSON.parse(evaluated.result.value);
    await cdp.send('Target.closeTarget', { targetId: target.targetId });

    assert.equal(result.error, undefined, `検索・選択の手順が正常に進行する: ${JSON.stringify(result)}`);
    assert.equal(
      result.centerKeyBefore, 'hub',
      `関連数が最も多いテーブル(hub、関連${SPOKE_COUNT}件)が中心カードとして選択される: ${result.centerKeyBefore}`,
    );
    assert.equal(
      result.cardCount, SPOKE_COUNT + 1,
      `中心カード1件+関連カード${SPOKE_COUNT}件が描画される: ${result.cardCount}件`,
    );

    // --- 判定2: カードの矩形が互いに重ならない ---
    const rects = result.rects;
    assert.ok(Array.isArray(rects) && rects.length === SPOKE_COUNT + 1, 'カード矩形を実測できる');
    let overlapPairs = [];
    for (let i = 0; i < rects.length; i += 1) {
      for (let j = i + 1; j < rects.length; j += 1) {
        if (rectsOverlap(rects[i], rects[j])) {
          overlapPairs.push(`${rects[i].key}×${rects[j].key}`);
        }
      }
    }
    assert.equal(
      overlapPairs.length, 0,
      `関連数最多テーブル(hub)選択時、カード矩形の重なりが0件: ${overlapPairs.join(', ')}`,
    );

    // --- 判定3: タブ切り替え後も選択状態・検索語が保たれる ---
    // 検索結果クリック時、入力欄の表示値は選択したテーブルのラベルへ更新される仕様のため、
    // タブ切り替え前の時点の値(ラベル)を基準にして、切り替え後も同じ値のままであることを見る。
    assert.equal(result.searchValueBefore, 'ハブテーブル', '検索結果クリックで入力欄がラベル表示へ更新される');
    assert.equal(
      result.searchValueAfter, result.searchValueBefore,
      `タブ切り替え後も検索語が保たれる: before=${result.searchValueBefore} after=${result.searchValueAfter}`,
    );
    assert.equal(
      result.centerKeyAfter, result.centerKeyBefore,
      `タブ切り替え後も選択中テーブルが保たれる: before=${result.centerKeyBefore} after=${result.centerKeyAfter}`,
    );
    assert.equal(
      result.cardCountAfter, SPOKE_COUNT + 1,
      `タブ切り替え後もカード描画件数が保たれる: ${result.cardCountAfter}件`,
    );

    console.log(
      `PASS: テーブル詳細タブ — 関連数最多テーブル(hub、関連${SPOKE_COUNT}件)選択時にカード重なり0件、`
      + `タブ切替後も選択(${result.centerKeyAfter})と検索語(${result.searchValueAfter})が保たれる`,
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
