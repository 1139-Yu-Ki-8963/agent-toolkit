#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const {pathToFileURL} = require('node:url');
const { BrowserUnavailableError, markUnavailable, reportIfUnavailable } = require('./lib/browser-unavailable.cjs');
let chromium;
try {
  ({chromium} = require('playwright'));
} catch (error) {
  if (error && error.code === 'MODULE_NOT_FOUND') {
    console.error('[UNKNOWN] playwrightパッケージが見つからないため判定できません（実行環境にnode_modulesが用意されていない可能性があります）');
    process.exit(2);
  }
  throw error;
}

const htmlPaths = process.argv.slice(2);
assert.equal(htmlPaths.length, 3, 'usage: assert-generated-detail-pages-runtime.cjs <techstack.html> <env.html> <glossary.html>');
for (const htmlPath of htmlPaths) {
  assert.ok(fs.existsSync(htmlPath), `generated page must exist: ${htmlPath}`);
}

(async () => {
  let browser;
  try {
    browser = await chromium.launch({headless: true});
  } catch (launchError) {
    throw markUnavailable(launchError);
  }
  try {
    for (const htmlPath of htmlPaths) {
      const page = await browser.newPage({viewport: {width: 1280, height: 720}});
      const pageErrors = [];
      page.on('pageerror', error => pageErrors.push(error.message));
      await page.goto(pathToFileURL(htmlPath).href, {waitUntil: 'load'});
      await page.waitForTimeout(100);
      assert.deepEqual(pageErrors, [], `${htmlPath} emitted runtime exceptions`);
      await page.close();
    }
  } finally {
    await browser.close();
  }
  console.log('generated detail pages runtime: PASS (3 pages, pageerror=0)');
})().catch(error => {
  if (reportIfUnavailable(error)) {
    process.exit(2);
    return;
  }
  console.error(error.stack || error);
  process.exit(1);
});
