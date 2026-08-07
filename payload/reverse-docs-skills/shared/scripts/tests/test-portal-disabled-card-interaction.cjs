#!/usr/bin/env node
'use strict';

// 改善課題1-7 検収: disabledWhenEmpty:true の種別が0件の合成カタログからポータルTOPを生成し、
// 実描画(CDP)で次の2点を検証する。
//   (1) 作成不可(is-disabled)カードをクリックしても遷移が発生しないこと
//   (2) 作成不可カードと活性カードとの間に、計算後のスタイル(color/cursor/opacity)で
//       視覚差があること
// 比較対象として、glob一致する実ファイルを1件だけ用意した活性カードも同一カテゴリへ追加し、
// そちらは実際にクリックで遷移することも合わせて確認する(遷移しないことだけを見ると
// href不在のdiv要素である時点で自明になってしまうため、対比を設けて検収を意味あるものにする)。
//
// test-matrix-header-compact-layout.cjsと同じChromeバイナリ探索・CDP接続の実装パターンを
// 踏襲する。ChromeまたはChromiumが見つからない環境では、既存8本と同じく失敗として扱う。
// 素通りさせると、ブラウザの無い環境で本テストだけが無検証のまま緑になるため。

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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function evalJs(cdp, sessionId, expression) {
  const evaluated = await cdp.send('Runtime.evaluate', {
    expression,
    awaitPromise: true,
    returnByValue: true,
  }, sessionId);
  assert.equal(evaluated.exceptionDetails, undefined, `DOM評価を実行できる: ${expression.slice(0, 80)}`);
  return evaluated.result.value;
}

async function clickAt(cdp, sessionId, x, y) {
  await cdp.send('Input.dispatchMouseEvent', {
    type: 'mousePressed', x, y, button: 'left', clickCount: 1,
  }, sessionId);
  await cdp.send('Input.dispatchMouseEvent', {
    type: 'mouseReleased', x, y, button: 'left', clickCount: 1,
  }, sessionId);
}

const repoRoot = path.resolve(__dirname, '..', '..', '..');
const buildPortalPath = path.join(repoRoot, 'shared', 'scripts', 'build-portal.sh');

// build-portal.sh は書込先経路にシンボリックリンクを含む場合に拒否する(assertNoLexicalSymlink)。
// macOSでは/varが/private/varへのシンボリックリンクのため、実体パスへ解決してから使う
// (shared/scripts/build-portal.shのcreate_physical_tmpdirと同じ対処)。
const fixtureRoot = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'portal-disabled-card-')));
const cleanupFixture = () => fs.rmSync(fixtureRoot, {
  recursive: true,
  force: true,
  maxRetries: 10,
  retryDelay: 100,
});
process.on('exit', cleanupFixture);

function buildPortal() {
  const repoDir = path.join(fixtureRoot, 'repo');
  // discovery(glob探索)はbuild-portal.shの--output-root(=output_dir引数)を起点に行われる。
  // portal_output_dirとは別の値を渡すとカードが検出されない事故になるため、
  // 他のセルフテスト(build-portal.sh --self-testのケース13等)と同じく両者を同一にする。
  const portalDir = path.join(fixtureRoot, 'portal');
  fs.mkdirSync(repoDir, { recursive: true });
  fs.mkdirSync(portalDir, { recursive: true });

  // disabledWhenEmpty:true の種別を0件、通常種別を1件(実ファイルあり)で持つ合成カタログ。
  const catalog = {
    schemaVersion: 1,
    categories: [
      {
        key: 'degrade-test',
        label: '縮退検査',
        group: 'Test',
        icon: 'folder',
        sub: 'test',
        blueprints: [
          {
            kind: 'keep-visible',
            label: '作成不可カード',
            icon: 'description',
            desc: '0件でも無効カードとして残る種別。',
            dir: '',
            generator: 'test-generator',
            unit: '件',
            countFormat: 'detail',
            disabledWhenEmpty: true,
            discovery: {
              artifactType: 'keep-visible-page',
              root: 'output-dir',
              glob: 'keep-visible.html',
              matchKind: 'file',
              titleSource: 'blueprint-label',
              dirSource: 'blueprint',
              instanceKeySource: 'relative-path',
              sort: 'relative-path-bytewise',
            },
          },
          {
            kind: 'enabled-card',
            label: '活性カード',
            icon: 'description',
            desc: '1件存在し活性表示される種別。',
            dir: '',
            generator: 'test-generator',
            unit: '件',
            countFormat: 'detail',
            discovery: {
              artifactType: 'enabled-card-page',
              root: 'output-dir',
              glob: 'enabled-card.html',
              matchKind: 'file',
              titleSource: 'blueprint-label',
              dirSource: 'blueprint',
              instanceKeySource: 'relative-path',
              sort: 'relative-path-bytewise',
            },
          },
        ],
      },
    ],
  };
  const catalogPath = path.join(fixtureRoot, 'catalog.json');
  fs.writeFileSync(catalogPath, JSON.stringify(catalog));
  fs.writeFileSync(
    path.join(portalDir, 'code-metrics.json'),
    JSON.stringify({ total: 100, fe: 50, be: 50, file_count: 10 }),
  );
  fs.writeFileSync(
    path.join(portalDir, 'enabled-card.html'),
    '<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><title>活性カード遷移先</title></head>'
    + '<body><p data-marker="ENABLED_CARD_TARGET">活性カードの遷移先ページ</p></body></html>',
  );

  execFileSync('bash', [buildPortalPath, repoDir, portalDir, portalDir, '--catalog', catalogPath], { stdio: 'pipe' });
  return path.join(portalDir, 'index.html');
}

(async () => {
  const browserPath = findBrowser();
  assert.ok(browserPath, 'ChromeまたはChromiumの実行ファイルを検出できる');

  let browser;
  let cdp;
  const failures = [];
  const reports = [];
  try {
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

    const indexPath = buildPortal();
    await cdp.send('Page.navigate', { url: `file://${indexPath}` }, sessionId);

    await evalJs(cdp, sessionId, `(async function () {
      var deadline = Date.now() + 15000;
      while (
        (document.readyState !== 'complete' || !document.querySelector('.card.is-tool'))
        && Date.now() < deadline
      ) {
        await new Promise(function (resolve) { setTimeout(resolve, 20); });
      }
      /* ライトテーマへ固定する(--faint/--textの差分を決定的に計測するため) */
      document.documentElement.setAttribute('data-theme', 'light');
      return true;
    })()`);

    const initialHref = await evalJs(cdp, sessionId, 'location.href');
    assert(initialHref.endsWith('index.html'), '初期URLがポータルTOPを指す');

    // --- (2) 計算後スタイルの視覚差(color/cursor/opacity) ---
    const styleInfo = await evalJs(cdp, sessionId, `(function () {
      var disabled = document.querySelector('.card.is-tool.is-disabled');
      var enabled = document.querySelector('.card.is-tool:not(.is-disabled)');
      if (!disabled || !enabled) return null;
      var dc = getComputedStyle(disabled);
      var ec = getComputedStyle(enabled);
      return JSON.stringify({
        disabledColor: dc.color, enabledColor: ec.color,
        disabledCursor: dc.cursor, enabledCursor: ec.cursor,
        disabledOpacity: dc.opacity, enabledOpacity: ec.opacity,
      });
    })()`);
    assert(styleInfo, '作成不可カードと活性カードの両方がDOM上に存在する');
    const style = JSON.parse(styleInfo);
    reports.push(
      `スタイル計測: 作成不可カード color=${style.disabledColor} cursor=${style.disabledCursor} opacity=${style.disabledOpacity} / `
      + `活性カード color=${style.enabledColor} cursor=${style.enabledCursor} opacity=${style.enabledOpacity}`,
    );
    const styleDiffers = style.disabledColor !== style.enabledColor
      || style.disabledCursor !== style.enabledCursor
      || style.disabledOpacity !== style.enabledOpacity;
    if (!styleDiffers) {
      failures.push('作成不可カードと活性カードの計算後スタイル(color/cursor/opacity)がすべて同一で視覚差が無い');
    }

    // --- (1a) 作成不可カードをクリックしても遷移しないこと ---
    const disabledRect = await evalJs(cdp, sessionId, `(function () {
      var el = document.querySelector('.card.is-tool.is-disabled');
      el.scrollIntoView({ block: 'center' });
      var r = el.getBoundingClientRect();
      return JSON.stringify({ x: r.x + r.width / 2, y: r.y + r.height / 2, hasHref: el.hasAttribute('href') });
    })()`);
    const disabled = JSON.parse(disabledRect);
    assert.equal(disabled.hasHref, false, '作成不可カードはhref属性を持たない');
    await clickAt(cdp, sessionId, disabled.x, disabled.y);
    await sleep(300);
    const hrefAfterDisabledClick = await evalJs(cdp, sessionId, 'location.href');
    if (hrefAfterDisabledClick !== initialHref) {
      failures.push(`作成不可カードのクリックで遷移が発生した: ${initialHref} -> ${hrefAfterDisabledClick}`);
    } else {
      reports.push('作成不可カードのクリックでは遷移が発生しない');
    }

    // --- (1b) 対比: 活性カードをクリックすると遷移すること ---
    const enabledRect = await evalJs(cdp, sessionId, `(function () {
      var el = document.querySelector('.card.is-tool:not(.is-disabled)');
      el.scrollIntoView({ block: 'center' });
      var r = el.getBoundingClientRect();
      return JSON.stringify({ x: r.x + r.width / 2, y: r.y + r.height / 2, href: el.getAttribute('href') });
    })()`);
    const enabled = JSON.parse(enabledRect);
    await clickAt(cdp, sessionId, enabled.x, enabled.y);

    let hrefAfterEnabledClick = initialHref;
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      await sleep(100);
      try {
        // eslint-disable-next-line no-await-in-loop
        hrefAfterEnabledClick = await evalJs(cdp, sessionId, 'location.href');
      } catch {
        // ナビゲーション中はコンテキスト破棄で例外になりうるため無視して再試行する
        continue;
      }
      if (hrefAfterEnabledClick !== initialHref) break;
    }
    if (hrefAfterEnabledClick === initialHref || !hrefAfterEnabledClick.endsWith('enabled-card.html')) {
      failures.push(`活性カードのクリックで期待した遷移が発生しなかった: ${initialHref} -> ${hrefAfterEnabledClick}`);
    } else {
      reports.push(`活性カードのクリックで enabled-card.html へ遷移した(href=${enabled.href})`);
    }

    await cdp.send('Target.closeTarget', { targetId: target.targetId });

    reports.forEach((line) => console.log(`INFO: ${line}`));

    if (failures.length > 0) {
      failures.forEach((line) => console.error(`FAIL: ${line}`));
      process.exitCode = 1;
    } else {
      console.log(
        'PASS: disabledWhenEmpty:trueの作成不可カードはクリックしても遷移せず、'
        + '活性カードとは計算後スタイル(color/cursor/opacity)で視覚差があり、活性カードは実際に遷移する',
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
  console.error(error);
  process.exitCode = 1;
});
