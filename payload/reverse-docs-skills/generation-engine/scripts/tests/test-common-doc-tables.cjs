#!/usr/bin/env node
'use strict';

if (typeof WebSocket !== 'function' && !process.env.__WS_RETRY) {
  const { spawnSync } = require('node:child_process');
  const r = spawnSync(process.execPath,
    ['--experimental-websocket', __filename, ...process.argv.slice(2)],
    { stdio: 'inherit', env: { ...process.env, __WS_RETRY: '1' } });
  process.exit(r.status === null ? 1 : r.status);
}

// 改善課題1-273・1-295・1-300 検収: 共通の版面（common-doc-template.html）の表の扱いを
// 合成入力で実描画（CDP）して確かめる。
//   1-273: 閾値（20行）を超える表に列見出しクリックの並べ替えと行の絞り込みが付き、閾値以下の表は変わらない
//   1-295: テストケース一覧（1列目が「ケース名」または「対象（関数名）」）を、BOM 付き UTF-8・CRLF・
//          記入用6列を足した CSV として、埋め込みの原本から元の順序で全件書き出せる
//   1-300: 空行だけを挟んで続く2つの表が、別々の2つの表として描画される
//   1-304: 同一文書内アンカーへのリンクに target が付かず、別文書へのリンクに target="_blank" が付く
// ブラウザを起動できない場合は判定不能（終了コード2）とし、不合格と区別する。

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { withPage } = require('./lib/cdp-browser.cjs');
const { reportIfUnavailable } = require('./lib/browser-unavailable.cjs');

const repoRoot = path.resolve(__dirname, '..', '..', '..');
const templatePath = path.join(repoRoot, 'delivery-payload', 'templates', 'common-doc-template.html');
const BIG_ROWS = 30;
const SMALL_ROWS = 5;
const CASE_ROWS = 7;

function buildMarkdown() {
  const L = ['# 合成 テスト設計書', '', '## §1 大きな表', '', '| 名前 | 値 | 区分 |', '|---|---|---|'];
  for (let i = 1; i <= BIG_ROWS; i += 1) L.push(`| item_${String(i).padStart(2, '0')} | ${BIG_ROWS + 1 - i} | ${i % 2 ? '奇数' : '偶数'} |`);
  L.push('', '## §2 小さな表', '', '| 名前 | 値 |', '|---|---|');
  for (let i = 1; i <= SMALL_ROWS; i += 1) L.push(`| small_${i} | ${i} |`);
  L.push('', '## §3 テストケース一覧', '', '| ケース名 | 番号 | 対象 | 期待結果 |', '|---|---|---|---|');
  for (let i = 1; i <= CASE_ROWS; i += 1) L.push(`| ケース${i} | ${i} | fn_${i} | 値に「,」と"引用"を含む${i} |`);
  L.push('', '## §4 連続する表', '', '| 対応する節 | ファイル |', '|---|---|', '| §1 | a.md |', '', '| 資料 | パス |', '|---|---|', '| 設計書 | b.md |', '');
  L.push('', '## §5 リンク', '', '[節への移動](#sec-anchor) と [別文書](./基本設計書.html) を参照。', '');
  return L.join('\n');
}

function renderFixture() {
  const raw = fs.readFileSync(templatePath, 'utf8');
  const html = raw
    .replace('{{DOC_MARKDOWN_JSON}}', JSON.stringify(buildMarkdown()))
    .replace(/\{\{[A-Z_]+\}\}/g, 'x')
    .replace('<!--SHELL_SIDEBAR-->', '<aside class="pt-sidebar"><ul id="toc-list"></ul></aside>')
    .replace('<!--SHELL_FOOTER-->', '');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'common-doc-tables-'));
  const file = path.join(dir, 'fixture.html');
  fs.writeFileSync(file, html);
  return file;
}

function measureScript() {
  return `(async function () {
    var deadline = Date.now() + 15000;
    while ((document.readyState !== 'complete' || !document.querySelector('#doc-content table')) && Date.now() < deadline) {
      await new Promise(function (r) { setTimeout(r, 20); });
    }
    for (var i = 0; i < 3; i += 1) await new Promise(function (r) { requestAnimationFrame(r); });
    var out = {};
    var tables = Array.prototype.slice.call(document.querySelectorAll('#doc-content table'));
    out.tableCount = tables.length;
    out.rowCounts = tables.map(function (t) { return t.querySelectorAll('tbody tr').length; });
    var big = tables[0], small = tables[1], cases = tables[2];
    out.bigSortable = big.classList.contains('sortable-table');
    out.smallSortable = small.classList.contains('sortable-table');
    function toolsOf(t) { var host = t.parentNode.parentNode.classList.contains('table-scroll-shell') ? t.parentNode.parentNode : t.parentNode; var prev = host.previousElementSibling; return prev && prev.classList.contains('table-tools') ? prev : null; }
    out.bigHasTools = !!toolsOf(big); out.smallHasTools = !!toolsOf(small);
    function firstCell(t) { return t.querySelector('tbody tr:not(.is-filtered) td').textContent.trim(); }
    out.beforeSort = firstCell(big);
    var th = big.querySelectorAll('thead th')[1]; th.click(); out.afterAsc = firstCell(big); out.ariaAsc = th.getAttribute('aria-sort');
    th.click(); out.afterDesc = firstCell(big); out.ariaDesc = th.getAttribute('aria-sort');
    th.click(); out.afterReset = firstCell(big);
    var input = toolsOf(big).querySelector('input'); input.value = '奇数'; input.dispatchEvent(new Event('input', { bubbles: true }));
    await new Promise(function (r) { setTimeout(r, 30); });
    out.filteredVisible = big.querySelectorAll('tbody tr:not(.is-filtered)').length;
    out.filterCount = toolsOf(big).querySelector('.table-filter-count').textContent;
    input.value = ''; input.dispatchEvent(new Event('input', { bubbles: true }));
    await new Promise(function (r) { setTimeout(r, 30); });
    out.resetVisible = big.querySelectorAll('tbody tr:not(.is-filtered)').length;
    var caseTools = toolsOf(cases);
    out.csvButton = !!(caseTools && caseTools.querySelector('button.csv-export'));
    out.csv = window.__docBuildCaseCsv ? window.__docBuildCaseCsv(0) : null;
    out.csvOthers = window.__docBuildCaseCsv ? window.__docBuildCaseCsv(1) : 'x';
    out.links = Array.prototype.slice.call(document.querySelectorAll('#doc-content a[href]')).map(function (a) {
      return { href: a.getAttribute('href'), target: a.getAttribute('target'), rel: a.getAttribute('rel') };
    });
    return JSON.stringify(out);
  })()`;
}

(async () => {
  const failures = []; const reports = [];
  const fixture = renderFixture();
  const raw = await withPage('common-doc-tables', 1200, async (page) => { await page.goto('file://' + fixture); return page.evaluate(measureScript()); });
  const r = JSON.parse(raw);
  reports.push(`表 ${r.tableCount} 件（行数 ${r.rowCounts.join('/')}）／並べ替え: ${r.beforeSort}→${r.afterAsc}→${r.afterDesc}→${r.afterReset}／絞り込み: ${r.filteredVisible} 行（${r.filterCount}）`);
  // 1-300
  if (r.tableCount !== 5 || r.rowCounts[3] !== 1 || r.rowCounts[4] !== 1) failures.push(`1-300: 空行で続く2つの表が別々に描画されない（表 ${r.tableCount} 件、行数 ${r.rowCounts.join('/')}）`);
  // 1-273
  if (!r.bigSortable || !r.bigHasTools) failures.push('1-273 検収1: 閾値を超える表に並べ替え・絞り込みが付かない');
  if (r.smallSortable || r.smallHasTools) failures.push('1-273 検収3: 閾値以下の表が変わっている');
  if (r.afterAsc !== 'item_30' || r.ariaAsc !== 'ascending' || r.afterDesc !== 'item_01' || r.ariaDesc !== 'descending' || r.afterReset !== 'item_01') failures.push(`1-273 検収1: 列見出しクリックで並べ替えが働かない（${r.afterAsc}/${r.afterDesc}/${r.afterReset}）`);
  if (r.filteredVisible !== 15 || r.resetVisible !== BIG_ROWS) failures.push(`1-273 検収2: 絞り込みで一致する行だけが残らない（${r.filteredVisible}/${r.resetVisible}）`);
  // 1-295
  if (!r.csvButton) failures.push('1-295: テストケース一覧に書き出しのボタンが無い');
  if (!r.csv) failures.push('1-295: CSV が組み立てられない');
  else {
    const buf = Buffer.from(r.csv, 'utf8');
    const bom = buf.slice(0, 3).toString('hex') === 'efbbbf';
    const lines = r.csv.replace(/^﻿/, '').split('\r\n').filter(Boolean);
    const lf = (r.csv.match(/\n/g) || []).length, crlf = (r.csv.match(/\r\n/g) || []).length;
    const header = lines[0].split(',');
    reports.push(`CSV: BOM=${bom} CRLF=${crlf} LF=${lf} 行=${lines.length} 列=${header.length}`);
    if (!bom) failures.push('1-295 検収1: 出力の先頭3バイトが BOM ではない');
    if (lf !== crlf) failures.push('1-295 検収2: 改行が CRLF ではない');
    if (lines.length !== CASE_ROWS + 1) failures.push(`1-295 検収3: 表の行数と出力の行数が一致しない（${lines.length - 1}/${CASE_ROWS}）`);
    if (header.length !== 4 + 6 || header.slice(4).join(',') !== '実施日,実施者,結果,実際の結果,起票番号,実施時の備考') failures.push('1-295: 記入用の6列が付かない');
    if (!/"値に「,」と""引用""を含む1"/.test(lines[1])) failures.push('1-295: カンマ・引用符を含む値の二重化が正しくない');
    if (r.csvOthers !== null) failures.push('1-295: ケース表以外が書き出しの対象になっている');
  }
  // 1-304
  const anchorLink = (r.links || []).find((a) => a.href && a.href.charAt(0) === '#');
  const docLink = (r.links || []).find((a) => a.href && a.href.indexOf('基本設計書.html') !== -1);
  if (!anchorLink || !docLink) failures.push(`1-304: 検査対象のリンクが描画されない（${JSON.stringify(r.links || [])}）`);
  else {
    if (anchorLink.target) failures.push(`1-304 検収1: 同一文書内アンカーへのリンクに target が付いている（${anchorLink.target}）`);
    if (docLink.target !== '_blank') failures.push(`1-304 検収2: 別文書へのリンクに target="_blank" が付かない（${docLink.target}）`);
  }
  reports.push(`リンク: アンカー target=${anchorLink && anchorLink.target}／別文書 target=${docLink && docLink.target}`);
  reports.forEach((l) => console.log(`INFO: ${l}`));
  if (failures.length) { failures.forEach((l) => console.error(`FAIL: ${l}`)); process.exitCode = 1; return; }
  console.log('PASS: 共通の版面で、閾値を超える表の並べ替え・絞り込み（1-273）、テストケース一覧の CSV 書き出し（1-295）、空行で続く表の分離（1-300）が実描画で機能する');
})().catch((error) => { if (reportIfUnavailable(error)) { process.exitCode = 2; return; } console.error(error); process.exitCode = 1; });
