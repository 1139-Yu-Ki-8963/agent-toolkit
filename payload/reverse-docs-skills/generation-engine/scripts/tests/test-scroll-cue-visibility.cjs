#!/usr/bin/env node
'use strict';

if (typeof WebSocket !== 'function' && !process.env.__WS_RETRY) {
  const { spawnSync } = require('node:child_process');
  const r = spawnSync(process.execPath,
    ['--experimental-websocket', __filename, ...process.argv.slice(2)],
    { stdio: 'inherit', env: { ...process.env, __WS_RETRY: '1' } });
  process.exit(r.status === null ? 1 : r.status);
}

// 改善課題1-50 検収: 横スクロールする表の視覚的な手がかり(.pt-scroll-shell要素への
// can-scroll-left/can-scroll-rightクラス付与)が、幅866pxでは現れ、幅3000pxでは
// 現れないことを実描画(CDP)で検証する。
//
// 対象は data-scroll-cues="auto" を持つホスト配下の table.screens
// (delivery-payload/templates/unit-list/screen-list-template.htmlが
// min-width: 1100pxを明示指定)。866px幅ではラップ後の.pt-scroll-shellが
// wrap.scrollWidth > wrap.clientWidthを検出しcan-scroll-*クラスを付与し、
// 3000px幅では付与されないことを検証する。
//
// test-matrix-header-compact-layout.cjsと同じChromeバイナリ探索・CDP接続の
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

const repoRoot = path.resolve(__dirname, '..', '..', '..');
const samplePath = path.join(
  repoRoot, 'generation-engine', 'samples', 'project-portal', 'lists', 'screens', '画面一覧.html',
);

function measureScript() {
  return `(async function () {
    var deadline = Date.now() + 15000;
    while (
      (document.readyState !== 'complete' || !document.querySelector('.pt-scroll-shell'))
      && Date.now() < deadline
    ) {
      await new Promise(function (resolve) { setTimeout(resolve, 20); });
    }
    for (var i = 0; i < 4; i += 1) {
      await new Promise(function (resolve) { requestAnimationFrame(resolve); });
    }
    var shell = document.querySelector('.pt-scroll-shell');
    var wrap = shell ? shell.querySelector(':scope > .table-wrap, :scope > .pt-tablewrap') : null;
    return JSON.stringify({
      found: !!shell,
      canScrollLeft: shell ? shell.classList.contains('can-scroll-left') : null,
      canScrollRight: shell ? shell.classList.contains('can-scroll-right') : null,
      scrollWidth: wrap ? wrap.scrollWidth : null,
      clientWidth: wrap ? wrap.clientWidth : null,
    });
  })()`;
}

function resizeMeasureScript() {
  return `(async function () {
    window.dispatchEvent(new Event('resize'));
    for (var i = 0; i < 6; i += 1) {
      await new Promise(function (resolve) { requestAnimationFrame(resolve); });
    }
    await new Promise(function (resolve) { setTimeout(resolve, 50); });
    var shell = document.querySelector('.pt-scroll-shell');
    var wrap = shell ? shell.querySelector(':scope > .table-wrap, :scope > .pt-tablewrap') : null;
    return JSON.stringify({
      found: !!shell,
      canScrollLeft: shell ? shell.classList.contains('can-scroll-left') : null,
      canScrollRight: shell ? shell.classList.contains('can-scroll-right') : null,
      scrollWidth: wrap ? wrap.scrollWidth : null,
      clientWidth: wrap ? wrap.clientWidth : null,
    });
  })()`;
}

(async () => {
  let browser;
  let cdp;
  const failures = [];
  const reports = [];
  try {
    assert.ok(fs.existsSync(samplePath), `検証対象サンプルが存在する: ${samplePath}`);

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
      '--window-size=866,900',
      `--user-data-dir=${fs.mkdtempSync(path.join(os.tmpdir(), 'scroll-cue-visibility-'))}`,
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
      width: 866,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false,
    }, sessionId);

    await cdp.send('Page.navigate', { url: `file://${samplePath}` }, sessionId);
    const narrowEvaluated = await cdp.send('Runtime.evaluate', {
      expression: measureScript(),
      awaitPromise: true,
      returnByValue: true,
    }, sessionId);
    assert.equal(narrowEvaluated.exceptionDetails, undefined, '幅866pxでのDOM計測を実行できる');
    const narrow = JSON.parse(narrowEvaluated.result.value);

    if (!narrow.found) {
      failures.push('幅866px: .pt-scroll-shell要素が見つからなかった（wrapAutoHostsによる動的ラップが機能していない可能性）');
    } else {
      reports.push(
        `幅866px: canScrollLeft=${narrow.canScrollLeft} canScrollRight=${narrow.canScrollRight} `
        + `scrollWidth=${narrow.scrollWidth} clientWidth=${narrow.clientWidth}`,
      );
      if (!(narrow.scrollWidth > narrow.clientWidth)) {
        failures.push(`幅866px: scrollWidth(${narrow.scrollWidth})がclientWidth(${narrow.clientWidth})を超えず、そもそも横スクロールが発生していない`);
      }
      if (narrow.canScrollRight !== true) {
        failures.push(`幅866px: can-scroll-rightクラスが付与されていない（手がかりが現れていない）: canScrollRight=${narrow.canScrollRight}`);
      }
    }

    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: 3000,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false,
    }, sessionId);
    const wideEvaluated = await cdp.send('Runtime.evaluate', {
      expression: resizeMeasureScript(),
      awaitPromise: true,
      returnByValue: true,
    }, sessionId);
    assert.equal(wideEvaluated.exceptionDetails, undefined, '幅3000pxでのDOM計測を実行できる');
    const wide = JSON.parse(wideEvaluated.result.value);

    if (!wide.found) {
      failures.push('幅3000px: .pt-scroll-shell要素が見つからなかった');
    } else {
      reports.push(
        `幅3000px: canScrollLeft=${wide.canScrollLeft} canScrollRight=${wide.canScrollRight} `
        + `scrollWidth=${wide.scrollWidth} clientWidth=${wide.clientWidth}`,
      );
      if (wide.canScrollLeft !== false || wide.canScrollRight !== false) {
        failures.push(`幅3000px: can-scroll-left/can-scroll-rightのいずれかが付与されたままで、手がかりが消えていない: canScrollLeft=${wide.canScrollLeft} canScrollRight=${wide.canScrollRight}`);
      }
    }

    await cdp.send('Target.closeTarget', { targetId: target.targetId });

    reports.forEach((line) => console.log(`INFO: ${line}`));

    if (failures.length > 0) {
      failures.forEach((line) => console.error(`FAIL: ${line}`));
      process.exitCode = 1;
    } else {
      console.log(
        'PASS: 横スクロールする表(画面一覧)で、幅866pxでは.pt-scroll-shellにcan-scroll-rightが付与され手がかりが現れ、'
        + '幅3000pxではcan-scroll-left/can-scroll-rightがいずれも外れ手がかりが消えることを確認した',
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
