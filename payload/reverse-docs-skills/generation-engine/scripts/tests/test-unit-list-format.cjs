#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const {execFileSync} = require('node:child_process');
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

const repoRoot = path.resolve(__dirname, '..', '..', '..');
const builder = path.join(repoRoot, 'generation-engine', 'scripts', 'unit-list', 'build-unit-list.sh');
const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'unit-list-format-'));

function makeUnit(index, overrides = {}) {
  const number = String(index).padStart(3, '0');
  return {
    unitKey: `unit-${number}`,
    kind: 'endpoint',
    identifier: `GET /api/unit-${number}`,
    unitNameGuess: `単位 ${number}`,
    sourceFile: path.join(fixtureRoot, 'src', 'units.ts'),
    confidence: 'high',
    fileCount: 1,
    detectionMethod: 'manual',
    ...overrides,
  };
}

const completePaths = {
  designDocPath: '../docs/basic.html',
  detailDocPath: '../docs/detail.html',
  sequencePath: '../docs/sequence.html',
  integrationTestCasePath: '../docs/integration.html',
  integrationTestViewpointPath: '../docs/integration-viewpoint.html',
  testCasePath: '../docs/unit.html',
  unitTestViewpointPath: '../docs/unit-viewpoint.html',
  scenarioPath: '../docs/confirmation.html',
};

function buildPage(name, units) {
  const manifestPath = path.join(fixtureRoot, `${name}.json`);
  const outputPath = path.join(fixtureRoot, `${name}.html`);
  const manifest = {
    generatedAt: '2026-08-23T00:00:00Z',
    sourceDir: path.join(fixtureRoot, 'src'),
    unitKind: 'api',
    strategy: {extractionMethod: 'custom', approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: units.length, unresolvedCount: 0},
    units,
  };
  fs.writeFileSync(manifestPath, JSON.stringify(manifest));
  execFileSync('bash', [builder, manifestPath, outputPath, '--unit-kind', 'api'], {stdio: 'pipe'});
  return outputPath;
}

function buildDerivedPage(name, unitKind, units) {
  const manifestPath = path.join(fixtureRoot, `${name}.json`);
  const outputPath = path.join(fixtureRoot, `${name}.html`);
  const manifest = {
    generatedAt: '2026-08-23T00:00:00Z',
    unitKind,
    units,
    summary: {totalCount: units.length, byTestType: {unit: units.length}, byScreen: {'api-login': units.length}},
  };
  fs.writeFileSync(manifestPath, JSON.stringify(manifest));
  execFileSync('bash', [builder, manifestPath, outputPath, '--unit-kind', unitKind], {stdio: 'pipe'});
  return outputPath;
}

async function visibleKeys(page) {
  return page.locator('#unit-table tbody > tr:not(.row-detail)').evaluateAll(rows => rows
    .filter(row => getComputedStyle(row).display !== 'none')
    .map(row => row.getAttribute('data-unit-key')));
}

(async () => {
  fs.mkdirSync(path.join(fixtureRoot, 'src'), {recursive: true});
  fs.writeFileSync(path.join(fixtureRoot, 'src', 'units.ts'), 'export const units = [];\n');

  const mixedPage = buildPage('mixed', [
    makeUnit(2, {unitKey: 'zulu', unitNameGuess: 'ズールー', designDocPath: '../docs/basic-only.html'}),
    makeUnit(1, {unitKey: 'alpha', unitNameGuess: 'アルファ', ...completePaths}),
  ]);
  const zeroCompletePage = buildPage('zero-complete', [
    makeUnit(1, {unitKey: 'partial', unitNameGuess: '部分', designDocPath: '../docs/basic-only.html'}),
  ]);
  const boundaryPage = buildPage('boundary', Array.from({length: 50}, (_, index) => {
    const wordKey = String.fromCharCode(97 + Math.floor(index / 26)) + String.fromCharCode(97 + (index % 26));
    return makeUnit(index + 1, {unitKey: `boundary-entry-${wordKey}`});
  }));
  const largePage = buildPage('large', Array.from({length: 51}, (_, index) => {
    const wordKey = String.fromCharCode(97 + Math.floor(index / 26)) + String.fromCharCode(97 + (index % 26));
    return makeUnit(index + 1, {unitKey: `item-entry-${wordKey}`});
  }));
  const apiViewpointPage = buildDerivedPage('api-viewpoint', 'test_viewpoint', [{
    unitKey: 'api-login-viewpoint-1', screenKey: 'api-login', sourceKind: 'api', testType: 'unit', category: '外部仕様', viewpoint: '期限切れトークンを拒否する',
  }]);
  const apiCasePage = buildDerivedPage('api-case', 'test_case', [{
    unitKey: 'api-login-case-1', screenKey: 'api-login', sourceKind: 'api', testType: 'unit', unitNameGuess: '期限切れ拒否', kind: 'unit', caseKey: '期限切れ拒否', viewpointKey: 'トークン期限切れ', input: '', steps: '', expected: '401を返す',
  }]);

  let browser;
  try {
    try {
      browser = await chromium.launch({headless: true});
    } catch (launchError) {
      throw markUnavailable(launchError);
    }
    const page = await browser.newPage({viewport: {width: 1440, height: 900}});
    await page.goto(pathToFileURL(mixedPage).href, {waitUntil: 'load'});

    const rows = page.locator('#unit-table tbody > tr:not(.row-detail)');
    assert.equal(await rows.count(), 2, '混在入力の2単位を描画する');
    assert.equal(await rows.nth(0).locator('.unit-doc-slot').count(), 5, '資料枠を5枠で固定する');
    assert.equal(await rows.nth(0).locator('.unit-doc-missing').count(), 4, '一部だけの単位は未作成4枠を—で描画する');
    assert.deepEqual(await rows.nth(0).locator('.unit-doc-slot').allTextContents(), ['基本', '—', '—', '—', '—']);
    assert.equal(await rows.nth(1).locator('.unit-doc-missing').count(), 0, '全部揃った単位には欠落枠がない');
    assert.equal(await rows.nth(1).locator('.unit-doc-link').count(), 8, '5枠から既存8資料すべてへリンクできる');
    assert.deepEqual(await rows.nth(1).locator('.unit-doc-link').evaluateAll(links => links.map(link => link.getAttribute('data-kind'))), [
      'basic', 'detail', 'sequence', 'integration-case', 'integration-viewpoint', 'test', 'unit-viewpoint', 'scenario',
    ]);

    const completeTile = page.locator('.tile[data-summary="complete-docs"]');
    assert.equal(await completeTile.count(), 1, '完全単位があるときだけ資料完備タイルを表示する');
    assert.equal((await completeTile.locator('strong').textContent()).trim(), '1', '全5枠が揃った単位数を表示する');
    assert.equal(await page.locator('.summary-tiles > .tile').first().getAttribute('data-summary'), 'complete-docs', '資料完備タイルを一覧先頭へ置く');

    const nameHeader = page.locator('th[data-key="unitNameGuess"]');
    await nameHeader.click();
    assert.deepEqual(await visibleKeys(page), ['alpha', 'zulu'], '1回目のクリックで名称を昇順に並べる');
    await nameHeader.click();
    assert.deepEqual(await visibleKeys(page), ['zulu', 'alpha'], '2回目のクリックで名称を降順に並べる');
    assert.equal(await page.locator('#pagination').evaluate(node => getComputedStyle(node).display), 'none', '1ページ以内ならページ送りを隠す');

    await page.goto(pathToFileURL(zeroCompletePage).href, {waitUntil: 'load'});
    assert.equal(await page.locator('.tile[data-summary="complete-docs"]').count(), 0, '完全単位が0件なら資料完備タイルを出さない');

    await page.goto(pathToFileURL(boundaryPage).href, {waitUntil: 'load'});
    assert.equal(await page.locator('#pagination').evaluate(node => getComputedStyle(node).display), 'none', 'ちょうど50件ならページ送りを隠す');
    assert.equal((await visibleKeys(page)).length, 50, 'ちょうど50件なら全行を1ページに表示する');

    await page.goto(pathToFileURL(largePage).href, {waitUntil: 'load'});
    assert.notEqual(await page.locator('#pagination').evaluate(node => getComputedStyle(node).display), 'none', '51件ならページ送りを表示する');
    assert.equal((await visibleKeys(page)).length, 50, '1ページ目には50件を表示する');
    await page.locator('#page-next').click();
    assert.deepEqual(await visibleKeys(page), ['item-entry-by'], '次ボタンで2ページ目の1件へ移動する');
    assert.match(await page.locator('#page-info').textContent(), /^2 \/ 2（51件）$/, 'ページ番号を2 / 2へ更新する');

    for (const derivedPage of [apiViewpointPage, apiCasePage]) {
      await page.goto(pathToFileURL(derivedPage).href, {waitUntil: 'load'});
      assert.equal((await page.locator('th[data-key="sourceKind"]').textContent()).trim(), '種別', 'APIのみの派生一覧に種別列を描画する');
      assert.equal((await page.locator('#unit-table tbody > tr:not(.row-detail) td').filter({hasText: /^API$/}).count()), 1, '集約元のAPI種別を表示する');
    }

    console.log('self-test: 7 PASS, 0 FAIL');
  } finally {
    if (browser) await browser.close();
    fs.rmSync(fixtureRoot, {recursive: true, force: true});
  }
})().catch(error => {
  if (reportIfUnavailable(error)) {
    process.exit(2);
    return;
  }
  console.error(error.stack || error);
  process.exit(1);
});
