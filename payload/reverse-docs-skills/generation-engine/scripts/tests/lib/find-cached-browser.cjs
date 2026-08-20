#!/usr/bin/env node
'use strict';

// DOM計測系テストのfindBrowser()が共有するPlaywrightキャッシュ探索ロジック。
// 改善課題1-181: この探索ロジックが一部のテストにしか実装されておらず、
// 環境変数未指定時にブラウザを検出できないテストが存在した。1箇所へ集約する。

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

module.exports = { findCachedBrowser };
