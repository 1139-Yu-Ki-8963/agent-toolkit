#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const { execFileSync, spawn, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { findCachedBrowser } = require('./lib/find-cached-browser.cjs');

const MAX_DUMP_BYTES = 20 * 1024 * 1024;
const DUMP_DOM_TIMEOUT_MS = 180000;

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

  const applicationRoots = [
    '/Applications',
    path.join(os.homedir(), 'Applications'),
  ];
  const browserAppNames = [
    'Google Chrome.app',
    'Google Chrome for Testing.app',
    'Chromium.app',
  ];
  const executablesForApp = (appPath) => {
    const macOsDir = path.join(appPath, 'Contents', 'MacOS');
    if (!fs.existsSync(macOsDir)) return [];
    return fs.readdirSync(macOsDir)
      .sort()
      .map((name) => path.join(macOsDir, name))
      .filter(isExecutable);
  };

  for (const applicationRoot of applicationRoots) {
    for (const appName of browserAppNames) {
      const executable = executablesForApp(path.join(applicationRoot, appName))[0];
      if (executable) return executable;
    }
  }

  const bundleIds = [
    'com.google.Chrome',
    'com.google.Chrome.forTesting',
    'org.chromium.Chromium',
  ];
  const candidates = [];
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
    for (const appPath of appPaths.sort()) {
      for (const executable of executablesForApp(appPath)) {
        candidates.push({ appPath, executable });
      }
    }
  }
  const nativeArchitecture = (executable) => {
    try {
      const description = execFileSync('file', ['-b', executable], { encoding: 'utf8' });
      if (process.arch === 'arm64') return /\barm64\b/.test(description);
      if (process.arch === 'x64') return /\b(?:x86_64|x86-64)\b/.test(description);
    } catch {
      // アーキテクチャを取得できない場合はパスの優先順で決める
    }
    return false;
  };
  return candidates.sort((left, right) => {
    const leftPriority = [
      left.appPath.startsWith('/Applications/') ? 0 : 1,
      nativeArchitecture(left.executable) ? 0 : 1,
      path.basename(left.appPath) === 'Google Chrome.app' ? 0 : 1,
      left.appPath,
      left.executable,
    ];
    const rightPriority = [
      right.appPath.startsWith('/Applications/') ? 0 : 1,
      nativeArchitecture(right.executable) ? 0 : 1,
      path.basename(right.appPath) === 'Google Chrome.app' ? 0 : 1,
      right.appPath,
      right.executable,
    ];
    for (let index = 0; index < leftPriority.length; index += 1) {
      if (leftPriority[index] < rightPriority[index]) return -1;
      if (leftPriority[index] > rightPriority[index]) return 1;
    }
    return 0;
  })[0]?.executable || '';
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

function hasCompleteDocument(html) {
  return /^\s*(?:<!doctype\s+html[^>]*>\s*)?<html(?:\s[^>]*)?>[\s\S]*<\/body\s*>\s*<\/html\s*>\s*$/i.test(html);
}

function signalBrowser(browser, signal) {
  if (!browser || !browser.pid) return;
  if (process.platform !== 'win32') {
    try {
      process.kill(-browser.pid, signal);
      return;
    } catch {
      // プロセスグループへ送れない環境では親プロセスへ送る
    }
  }
  try {
    browser.kill(signal);
  } catch {
    // 終了済みなら後続のcleanupへ進む
  }
}

async function stopBrowser(browser) {
  if (!browser) return;
  if (browser.exitCode === null) {
    signalBrowser(browser, 'SIGTERM');
    await Promise.race([
      new Promise((resolve) => browser.once('close', resolve)),
      new Promise((resolve) => setTimeout(resolve, 2000)),
    ]);
  }
  if (browser.exitCode === null) {
    signalBrowser(browser, 'SIGKILL');
    await Promise.race([
      new Promise((resolve) => browser.once('close', resolve)),
      new Promise((resolve) => setTimeout(resolve, 2000)),
    ]);
  }
  if (process.platform !== 'win32' && browser.pid) {
    try {
      process.kill(-browser.pid, 'SIGKILL');
    } catch {
      // グループが既に終了している
    }
  }
  browser.stdout.destroy();
  browser.stderr.destroy();
  browser.unref();
}

function launchDumpDom(browserPath, args) {
  return new Promise((resolve, reject) => {
    const browser = spawn(browserPath, args, {
      detached: process.platform !== 'win32',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stdoutBytes = 0;
    let stderr = '';
    let settled = false;
    let timeout;
    let graceTimer;
    const settle = (callback) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      clearTimeout(graceTimer);
      callback();
    };
    const fail = (error) => {
      settle(() => {
        signalBrowser(browser, 'SIGKILL');
        reject(error);
      });
    };
    const succeed = () => settle(() => resolve({ browser, html: stdout }));
    const startGraceTimer = () => {
      if (settled || graceTimer) return;
      graceTimer = setTimeout(succeed, 250);
    };
    timeout = setTimeout(() => {
      fail(new Error(`Chrome/Chromiumが180秒以内に完全な--dump-dom出力を返しませんでした\n${stderr}`));
    }, DUMP_DOM_TIMEOUT_MS);

    browser.stdout.setEncoding('utf8');
    browser.stderr.setEncoding('utf8');
    browser.stdout.on('data', (chunk) => {
      stdoutBytes += Buffer.byteLength(chunk);
      if (stdoutBytes > MAX_DUMP_BYTES) {
        fail(new Error(`Chrome/Chromiumの--dump-dom出力が${MAX_DUMP_BYTES}バイトを超えました`));
        return;
      }
      stdout += chunk;
      if (hasCompleteDocument(stdout)) startGraceTimer();
    });
    browser.stderr.on('data', (chunk) => {
      stderr += chunk;
    });
    browser.on('error', (error) => fail(error));
    browser.on('close', (code, signal) => {
      if (hasCompleteDocument(stdout)) {
        if (code === 0 && signal === null) {
          succeed();
        } else {
          fail(new Error(
            `Chrome/Chromiumが完全な--dump-dom出力後に異常終了しました（exit ${code}; signal ${signal ?? 'none'}）\n${stderr}`,
          ));
        }
        return;
      }
      fail(new Error(
        `Chrome/Chromiumが完全な--dump-dom出力前に終了しました（exit ${code}; signal ${signal ?? 'none'}）\n${stderr}`,
      ));
    });
  });
}

function decodeEntities(text) {
  return text
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&');
}

function extractSectionHeadings(html) {
  const headings = [];
  const labelPattern = /<div\b(?=[^>]*\bclass\s*=\s*(?:"[^"]*\bsec-label\b[^"]*"|'[^']*\bsec-label\b[^']*'))[^>]*>([\s\S]*?)<\/div\s*>/gi;
  for (const match of html.matchAll(labelPattern)) {
    headings.push(decodeEntities(match[1].replace(/<[^>]*>/g, '').trim()));
  }
  if (headings.length === 0) {
    throw new Error('生成HTMLのDOMに sec-label を含む div が見つかりません');
  }
  return headings;
}

const scriptDir = __dirname;
const repositoryRoot = path.resolve(scriptDir, '..', '..', '..');
const templatePath = path.join(
  repositoryRoot,
  'delivery-payload/templates/リバース検証/画面/詳細設計/画面詳細設計書.md',
);
const temporaryRoot = fs.realpathSync(
  fs.mkdtempSync(path.join(os.tmpdir(), 'screen-doc-order-')),
);
const docsRoot = path.join(temporaryRoot, 'docs');
const detailDir = path.join(docsRoot, '画面/screen-order-test/詳細設計');
const outputPath = path.join(detailDir, '画面詳細設計書.html');
const browserProfilePath = path.join(temporaryRoot, 'browser-profile');

function cleanupTemporaryRoot() {
  fs.rmSync(temporaryRoot, {
    recursive: true,
    force: true,
    maxRetries: 10,
    retryDelay: 100,
  });
}

process.on('exit', cleanupTemporaryRoot);

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: repositoryRoot,
    encoding: 'utf8',
    timeout: 300000,
    killSignal: 'SIGKILL',
    maxBuffer: MAX_DUMP_BYTES,
  });
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(' ')} failed with exit ${result.status}; error: ${result.error?.message ?? 'none'}; signal: ${result.signal ?? 'none'}\n${result.stdout}\n${result.stderr}`,
    );
  }
}

function generateScreenDetailDocument() {
  fs.mkdirSync(detailDir, { recursive: true });
  fs.writeFileSync(
    path.join(docsRoot, 'output-layout.json'),
    JSON.stringify({ specVersion: 1, layout: { screenUnitRoot: '画面', screenViewRoot: '画面' } }) + '\n',
  );
  fs.copyFileSync(templatePath, path.join(detailDir, '画面詳細設計書.md'));
  console.log('INFO: build-portalで画面詳細設計書HTMLを生成');
  run('bash', [
    path.join(scriptDir, '..', 'build-portal.sh'),
    temporaryRoot,
    docsRoot,
    docsRoot,
    '--generated-at',
    '2026-07-29T00:00:00Z',
  ]);
  assert.ok(fs.existsSync(outputPath), '画面詳細設計書.html が生成されていない');
}

(async () => {
  let browser;
  try {
    generateScreenDetailDocument();
    console.log('INFO: Chrome/Chromiumで生成後DOMを取得');
    const browserPath = findBrowser();
    assert.notEqual(browserPath, '', 'ChromeまたはChromiumの実行ファイルを検出できる');
    const launched = await launchDumpDom(browserPath, [
      '--headless=new',
      '--no-sandbox',
      '--disable-gpu',
      '--disable-dev-shm-usage',
      '--disable-background-networking',
      '--no-first-run',
      '--no-default-browser-check',
      '--allow-file-access-from-files',
      `--user-data-dir=${browserProfilePath}`,
      '--dump-dom',
      pathToFileURL(outputPath).href,
    ]);
    browser = launched.browser;
    const headings = extractSectionHeadings(launched.html);
    const relatedHeading = '§19 関連資料';
    const chapterMapHeading = '章マップ（付録B）';

    assert.equal(
      headings[0],
      '§1 画面概要',
      `最初の本文セクションが画面概要ではない: ${headings[0]}`,
    );
    assert.deepEqual(
      headings.slice(-2),
      [relatedHeading, chapterMapHeading],
      `管理・索引表が末尾付録ではない: ${headings.slice(-2).join(' / ')}`,
    );
    assert.equal(
      headings.filter((heading) => heading === relatedHeading).length,
      1,
      `${relatedHeading} が重複している`,
    );
    assert.equal(
      headings.filter((heading) => heading === chapterMapHeading).length,
      1,
      `${chapterMapHeading} が重複している`,
    );
    console.log(`PASS: DOM見出し順序 ${headings[0]} → … → ${headings.slice(-2).join(' → ')}`);
  } finally {
    await stopBrowser(browser);
    cleanupTemporaryRoot();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
