#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const {pathToFileURL} = require('node:url');
const {chromium} = require('playwright');

const htmlPaths = process.argv.slice(2);
assert.equal(htmlPaths.length, 3, 'usage: assert-generated-detail-pages-runtime.cjs <techstack.html> <env.html> <glossary.html>');
for (const htmlPath of htmlPaths) {
  assert.ok(fs.existsSync(htmlPath), `generated page must exist: ${htmlPath}`);
}

(async () => {
  const browser = await chromium.launch({headless: true});
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
  console.error(error.stack || error);
  process.exit(1);
});
