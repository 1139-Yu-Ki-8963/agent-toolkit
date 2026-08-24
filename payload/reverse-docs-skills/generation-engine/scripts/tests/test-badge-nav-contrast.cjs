#!/usr/bin/env node
'use strict';

if (typeof WebSocket !== 'function' && !process.env.__WS_RETRY) {
  const { spawnSync } = require('node:child_process');
  const r = spawnSync(process.execPath,
    ['--experimental-websocket', __filename, ...process.argv.slice(2)],
    { stdio: 'inherit', env: { ...process.env, __WS_RETRY: '1' } });
  process.exit(r.status === null ? 1 : r.status);
}

// 改善課題1-49 検収: 一覧のバッジ3種（badge.high/medium/low）と共通サイドバーの
// ナビ項目文字・番号・件数（通常項目・現在地項目の両方）について、実描画(CDP)で
// 透過色を実際の背景と合成したうえでコントラスト比を算出し、明るい配色・暗い配色の
// 両方で基準（4.5:1）を満たすことを検証する。
//
// 基準値4.5の採用根拠: WCAG 2.1 レベルAAの通常文字に対する最小コントラスト比
// （SC 1.4.3）。このリポジトリでは test-matrix-header-compact-layout.cjs の
// CONTRAST_MIN が既にこの値を採用しており、本テストも同じ基準に揃える。
// 1-49の一覧（docs/tasks/指摘改善一覧.md）にも反映先の done 指示書にも、
// なぜ4.5を採ったかの根拠説明は明記されていなかった（2026-08-18 実測）。
//
// 対象ページは合成フィクスチャではなく、既存の実サンプル
// generation-engine/samples/project-portal/lists/apis/API一覧.html を使う。
// このページは埋め込みJSONに confidence: HIGH/MEDIUM/LOW を3種とも持ち
// （バッジ3種の描画を保証）、data-active-category="list" を持つため
// サイドバーの現在地ナビ項目（is-active）も再現できる。
//
// test-matrix-header-compact-layout.cjs と同じChromeバイナリ探索・CDP接続の
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
const targetPage = path.join(
  repoRoot, 'generation-engine', 'samples', 'project-portal', 'lists', 'apis', 'API一覧.html',
);

// --- 検証対象要素(セレクタ)。バッジ3種＋サイドバーのナビ項目の文字・番号・件数
//     （通常項目・現在地(is-active)項目の両方） ---
const ELEMENTS = [
  { key: 'badge-high', label: 'バッジ(high)', selector: '.badge.high' },
  { key: 'badge-medium', label: 'バッジ(medium)', selector: '.badge.medium' },
  { key: 'badge-low', label: 'バッジ(low)', selector: '.badge.low' },
  { key: 'nav-item-text', label: 'サイドバー通常項目の文字', selector: '.pt-nav-item:not(.is-active)' },
  { key: 'nav-num', label: 'サイドバー通常項目の番号', selector: '.pt-nav-item:not(.is-active) .pt-nav-num' },
  { key: 'nav-count', label: 'サイドバー通常項目の件数', selector: '.pt-nav-item:not(.is-active) .pt-nav-count' },
  { key: 'nav-active-text', label: 'サイドバー現在地項目の文字', selector: '.pt-nav-item.is-active' },
  { key: 'nav-active-num', label: 'サイドバー現在地項目の番号', selector: '.pt-nav-item.is-active .pt-nav-num' },
  { key: 'nav-active-count', label: 'サイドバー現在地項目の件数', selector: '.pt-nav-item.is-active .pt-nav-count' },
];

const THEMES = ['light', 'dark'];
const CONTRAST_MIN = 4.5;

function measureScript(theme) {
  return `(async function () {
    var deadline = Date.now() + 15000;
    while (
      (document.readyState !== 'complete' || !document.querySelector('.pt-nav-item'))
      && Date.now() < deadline
    ) {
      await new Promise(function (resolve) { setTimeout(resolve, 20); });
    }
    /* バッジ(confidence)は行クリックで展開する詳細パネル内にのみ動的生成される
       （unit-list-template.html の行クリックイベント）。ページ読み込み直後の
       DOMには存在しないため、high/medium/lowそれぞれ1行ずつ選び出しクリックして
       展開してから計測する必要がある(2026-08-18 実測で判明)。 */
    (function expandOneRowPerConfidence() {
      var manifestEl = document.getElementById('unit-manifest');
      if (!manifestEl) return;
      var manifest;
      try { manifest = JSON.parse(manifestEl.textContent); } catch (e) { return; }
      var units = manifest && manifest.units ? manifest.units : [];
      var seen = {};
      units.forEach(function (u) {
        var conf = String(u.confidence || '').toLowerCase();
        if ((conf === 'high' || conf === 'medium' || conf === 'low') && !seen[conf]) {
          var tr = document.querySelector('tr[data-unit-id="' + u.unitId + '"]')
            || document.querySelector('tr[data-unit-key="' + u.unitKey + '"]');
          /* テーマ切替のたびに本関数が再実行されるため、既に展開済み(トグルで
             閉じてしまう)行は再クリックしない。 */
          var already = tr && tr.nextElementSibling && tr.nextElementSibling.classList.contains('row-detail');
          if (tr && !already) { tr.click(); }
          if (tr) { seen[conf] = true; }
        }
      });
    })();
    /* .badge.low は実データ上、confidence=LOW のユニットが全件 kind=unresolved で
       別セクション（クリック展開対象外）へ回るため、通常の行展開では出現しない
       （2026-08-18 実測で判明。全サンプルマニフェストを走査し確認済み）。
       検証したいのはCSS定義（.badge.lowの配色）であって実データの出現頻度ではないため、
       .badge.high と同じ親要素の下へ合成の.badge.low要素を挿し込み、背景の継承を
       同条件にしたうえで計測後に取り除く。 */
    var syntheticLowBadge = null;
    (function insertSyntheticLowBadge() {
      var highBadge = document.querySelector('.badge.high');
      if (!highBadge || !highBadge.parentElement) return;
      var low = document.createElement('span');
      low.className = 'badge low';
      low.textContent = 'LOW';
      highBadge.parentElement.appendChild(low);
      syntheticLowBadge = low;
    })();
    /* テーマ切替直後、data-themeを変えた瞬間はtransition(shell.cssの
       .pt-nav-item { transition: all 0.12s } 等)による遷移の中間値を
       computedStyleが返すため、固定フレーム数(旧: 4rAF)の待機では遷移完了前の
       値を拾ってしまう(2026-08-18 実測で確定。現在地ナビ項目文字で2.48〜5.01の
       ばらつきを観測)。要素ごとにtransition-durationが異なりうるため、
       固定フレーム数ではなく計測対象要素ごとの transitionend 購読 +
       duration実測値+マージンのタイムアウトによるフォールバックへ変更する。
       transitionを持たない要素(直接colorが宣言され継承もされないバッジ・
       ナビ番号/件数)はdurationが0のため2rAF待機のみで即時解決する(2026-08-19)。 */
    var selectors = ${JSON.stringify(ELEMENTS.map((e) => [e.key, e.selector]))};
    function transitionDurationMs(el) {
      var cs = getComputedStyle(el);
      var raw = String(cs.transitionDuration || '0s').split(',');
      var max = 0;
      raw.forEach(function (part) {
        var s = part.trim();
        var v = parseFloat(s);
        if (isNaN(v)) return;
        var ms = /ms$/.test(s) ? v : v * 1000;
        if (ms > max) max = ms;
      });
      return max;
    }
    /* 計測対象の要素自身がtransitionを持たない場合でも、colorが明示宣言されず
       祖先から継承する、または祖先自身のbackground-colorがeffectiveBg()で
       合成対象になる場合(.pt-nav-num/.pt-nav-countの親.pt-nav-item等)があるため、
       対象要素だけでなく祖先チェーン全体のtransition-durationを走査し、
       最大値に基づいて待機する。transitionendは既定でバブリングするため、
       document側で捕捉してチェーン中のどの要素で発生したかを照合する。 */
    function collectTransitioningAncestors(el) {
      var found = [];
      var node = el;
      while (node) {
        var d = transitionDurationMs(node);
        if (d > 0) found.push({ node: node, duration: d });
        node = node.parentElement;
      }
      return found;
    }
    function waitForElementSettle(el, marginMs) {
      return new Promise(function (resolve) {
        var chain = collectTransitioningAncestors(el);
        if (chain.length === 0) {
          requestAnimationFrame(function () { requestAnimationFrame(resolve); });
          return;
        }
        var pending = new Set(chain.map(function (c) { return c.node; }));
        var maxDuration = chain.reduce(function (m, c) { return Math.max(m, c.duration); }, 0);
        var done = false;
        function finish() {
          if (done) return;
          done = true;
          document.removeEventListener('transitionend', onEnd, true);
          clearTimeout(timer);
          resolve();
        }
        function onEnd(ev) {
          if (pending.has(ev.target)) {
            pending.delete(ev.target);
            if (pending.size === 0) finish();
          }
        }
        document.addEventListener('transitionend', onEnd, true);
        var timer = setTimeout(finish, maxDuration + marginMs);
      });
    }
    document.documentElement.setAttribute('data-theme', ${JSON.stringify(theme)});
    await Promise.all(selectors.map(function (pair) {
      var el = document.querySelector(pair[1]);
      return el ? waitForElementSettle(el, 200) : Promise.resolve();
    }));
    function parseColor(str) {
      var m = str && str.match(/rgba?\\(([^)]+)\\)/);
      if (!m) return null;
      var parts = m[1].split(',').map(function (s) { return parseFloat(s.trim()); });
      return { r: parts[0], g: parts[1], b: parts[2], a: parts.length > 3 ? parts[3] : 1 };
    }
    /* 背景合成: 対象要素自身の背景が半透明(rgba)の場合、その半透明色を
       祖先の不透明背景の上に実際に合成してから返す。tokens.css・shell.css の
       --accent-soft 等はrgba半透明であるため、値の数式計算ではなく
       実描画のcomputedStyleを祖先方向へ辿って合成する必要がある(2026-08-18)。 */
    function compositeOver(fg, bg) {
      var a = fg.a;
      return {
        r: fg.r * a + bg.r * (1 - a),
        g: fg.g * a + bg.g * (1 - a),
        b: fg.b * a + bg.b * (1 - a),
      };
    }
    function effectiveBg(el) {
      var node = el;
      var composed = { r: 255, g: 255, b: 255 };
      var chain = [];
      while (node) {
        var cs = getComputedStyle(node);
        var c = parseColor(cs.backgroundColor);
        if (c && c.a > 0) chain.push(c);
        node = node.parentElement;
      }
      for (var i = chain.length - 1; i >= 0; i -= 1) {
        composed = compositeOver(chain[i], composed);
      }
      return composed;
    }
    var results = {};
    selectors.forEach(function (pair) {
      var key = pair[0];
      var selector = pair[1];
      var el = document.querySelector(selector);
      if (!el) { results[key] = null; return; }
      var color = parseColor(getComputedStyle(el).color);
      if (!color) { results[key] = null; return; }
      var bg = effectiveBg(el);
      results[key] = { color: color, bg: bg };
    });
    if (syntheticLowBadge && syntheticLowBadge.parentElement) {
      syntheticLowBadge.parentElement.removeChild(syntheticLowBadge);
    }
    return JSON.stringify(results);
  })()`;
}

(async () => {
  let browser;
  let cdp;
  const failures = [];
  const reports = [];
  try {
    assert.ok(fs.existsSync(targetPage), `対象ページが実在する: ${targetPage}`);

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
      `--user-data-dir=${fs.mkdtempSync(path.join(os.tmpdir(), 'badge-nav-contrast-'))}`,
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

    await cdp.send('Page.navigate', { url: `file://${targetPage}` }, sessionId);

    /* 捨て測り: 初期状態はdata-themeを持たずシステムの設定に従うため、最初の
       測定だけが「初期状態からの切替」になり、遷移の途中の値を拾う(2026-08-19
       実測。light配色の通常項目1.90・現在地項目1.07。色の値から計算した理論値は
       6.65と12.27であり、本来は基準4.5を上回る)。測定に入る前に1回だけ切り替えて
       結果を捨て、以後はどの配色も「確定した状態からの切替」にそろえる。
       THEMESの順序の入れ替えでは直らない。最初になった配色へ問題が移るだけで、
       実測で順序を入れ替えたとき暗い配色が通ったのは、元の比が8.70・11.34と高く
       途中の値でも基準を超えたからである。 */
    await cdp.send('Runtime.evaluate', {
      expression: measureScript(THEMES[0]),
      awaitPromise: true,
      returnByValue: true,
    }, sessionId);

    for (const theme of THEMES) {
      const evaluated = await cdp.send('Runtime.evaluate', {
        expression: measureScript(theme),
        awaitPromise: true,
        returnByValue: true,
      }, sessionId);
      assert.equal(evaluated.exceptionDetails, undefined, `DOM計測を実行できる(${theme})`);
      const results = JSON.parse(evaluated.result.value);

      for (const elementDef of ELEMENTS) {
        const measured = results[elementDef.key];
        if (!measured) {
          failures.push(`${theme}配色 / ${elementDef.label}: 要素(${elementDef.selector})を計測できなかった`);
          continue;
        }
        const contrast = contrastRatio(measured.color, measured.bg);
        reports.push(`${theme}配色 / ${elementDef.label}: コントラスト比${contrast.toFixed(2)}`);
        if (!(contrast >= CONTRAST_MIN)) {
          failures.push(`${theme}配色 / ${elementDef.label}: コントラスト比が基準(${CONTRAST_MIN}以上)を下回る: ${contrast.toFixed(2)}`);
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
        `PASS: バッジ3種(high/medium/low)とサイドバーのナビ項目(通常・現在地)の文字・番号・件数が、`
        + `明るい配色・暗い配色の両方でコントラスト比${CONTRAST_MIN}以上を満たす`,
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
  }
})().catch((error) => {
  if (reportIfUnavailable(error)) {
    process.exitCode = 2;
    return;
  }
  console.error(error);
  process.exitCode = 1;
});
