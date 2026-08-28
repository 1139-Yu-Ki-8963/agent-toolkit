#!/usr/bin/env node
'use strict';

if (typeof WebSocket !== 'function' && !process.env.__WS_RETRY) {
  const { spawnSync } = require('node:child_process');
  const r = spawnSync(process.execPath,
    ['--experimental-websocket', __filename, ...process.argv.slice(2)],
    { stdio: 'inherit', env: { ...process.env, __WS_RETRY: '1' } });
  process.exit(r.status === null ? 1 : r.status);
}

// 改善課題1-244 検収: 共通の版面（delivery-payload/templates/common-doc-template.html）が、
// 長い節の中を辿る手段を持つことを実描画（CDP）で確かめる。
// 章13件・関数ごとの表41件を持つ合成入力を版面へ流し込み、次の6点を測る。
//   1. 目次の項目数が章の数ではなく章と関数の合計になる
//   2. 生成物の <a href="#…"> が1件以上あり、クリックで対応する見出しへ移動する
//   3. 関数ごとの表が既定で閉じており、見出しをクリックして開ける
//   4. 絞り込みの入力欄に関数名の一部を打つと、該当する見出しだけが残る
//   5. 一覧表の「参照先」の値がリンクになり、対応する関数ごとの表へ移動する
//   6. JavaScript を無効にした状態での可読性（版面は本文を JavaScript で組み立てるため、
//      この版面では成立しない。既存の性質であり本項目の対象外。INFO として報告する）
// ブラウザを起動できない場合は判定不能（終了コード2）とし、不合格と区別する。

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { withPage } = require('./lib/cdp-browser.cjs');
const { reportIfUnavailable } = require('./lib/browser-unavailable.cjs');

const repoRoot = path.resolve(__dirname, '..', '..', '..');
const templatePath = path.join(repoRoot, 'delivery-payload', 'templates', 'common-doc-template.html');

const CHAPTERS = 13;
const FUNCTIONS = 41;

function buildMarkdown() {
  const lines = ['# 合成 API 詳細設計書', ''];
  for (let c = 1; c <= CHAPTERS; c += 1) {
    lines.push(`## §${c} 章${c}`, '', `章${c}の本文です。`, '');
    if (c === 12) {
      lines.push('### 12.1 関数と役割', '', '| 関数 | 役割 | 参照先 |', '|---|---|---|');
      for (let f = 1; f <= FUNCTIONS; f += 1) lines.push(`| fn_${f} | 役割${f} | fn_${f} |`);
      lines.push('', '### 12.2 関数単位の契約', '');
      for (let f = 1; f <= FUNCTIONS; f += 1) {
        lines.push(`#### fn_${f}`, '', '| 項目 | 値 |', '|---|---|', `| 引数 | a${f} |`, `| 戻り値 | r${f} |`, '');
      }
    }
  }
  return lines.join('\n');
}

function renderFixture() {
  const raw = fs.readFileSync(templatePath, 'utf8');
  // 版面の共通シェル用マーカーは、目次の置き場（#toc-list）だけを最小の形で補う
  let html = raw
    .replace('{{DOC_MARKDOWN_JSON}}', JSON.stringify(buildMarkdown()))
    .replace(/\{\{[A-Z_]+\}\}/g, 'x')
    .replace('<!--SHELL_SIDEBAR-->', '<aside class="pt-sidebar"><ul id="toc-list"></ul></aside>')
    .replace('<!--SHELL_FOOTER-->', '');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'common-doc-navigation-'));
  const file = path.join(dir, 'fixture.html');
  fs.writeFileSync(file, html);
  return file;
}

function measureScript() {
  return `(async function () {
    var deadline = Date.now() + 15000;
    while ((document.readyState !== 'complete' || !document.querySelector('#toc-list .toc-link')) && Date.now() < deadline) {
      await new Promise(function (r) { setTimeout(r, 20); });
    }
    for (var i = 0; i < 3; i += 1) await new Promise(function (r) { requestAnimationFrame(r); });
        function topOf(el) { return Math.round(el.getBoundingClientRect().top); }
    var out = {};
    out.tocTotal = document.querySelectorAll('#toc-list .toc-link').length;
    out.tocL2 = document.querySelectorAll('#toc-list .toc-li-l2').length;
    out.tocL4 = document.querySelectorAll('#toc-list .toc-l4').length;
    var anchors = Array.prototype.slice.call(document.querySelectorAll('#doc-content a[href^="#"], #toc-list a[href^="#"]'));
    out.anchors = anchors.length;
    out.anchorsResolved = anchors.filter(function (a) { return !!document.getElementById(a.getAttribute('href').substring(1)); }).length;
    var folds = Array.prototype.slice.call(document.querySelectorAll('details.fold-details'));
    out.folds = folds.length;
    out.foldsClosed = folds.filter(function (d) { return !d.open; }).length;
    var fnFolds = folds.filter(function (d) { var h = d.querySelector('summary h4'); return h && /^fn_/.test(h.textContent); });
    out.functionFolds = fnFolds.length;
    // 2. 目次のリンクをクリックして見出しへ移動する
    var link = document.querySelector('#toc-list a[href="#' + fnFolds[20].querySelector('h4').id + '"]');
    out.tocLinkFound = !!link;
    if (link) { link.click(); await new Promise(function (r) { setTimeout(r, 1500); }); }
    var target = fnFolds[20].querySelector('h4');
    out.movedTop = topOf(target);
    out.movedOpened = fnFolds[20].open;
    // 3. 見出し（summary）をクリックして開く
    var d3 = fnFolds[5];
    out.beforeClickOpen = d3.open;
    d3.querySelector('summary').click();
    await new Promise(function (r) { setTimeout(r, 50); });
    out.afterClickOpen = d3.open;
    // 4. 絞り込み
    var input = document.getElementById('doc-filter');
    out.filterInput = !!input;
    input.value = 'fn_3';
    input.dispatchEvent(new Event('input', { bubbles: true }));
    await new Promise(function (r) { setTimeout(r, 50); });
    out.filterCount = document.querySelector('.doc-filter-count').textContent;
    out.filterVisibleFolds = folds.filter(function (d) { return !d.classList.contains('is-filtered'); }).length;
    out.filterVisibleHeads = folds.filter(function (d) { return !d.classList.contains('is-filtered'); }).map(function (d) { return d.querySelector('h4').textContent; });
    out.filterVisibleToc = Array.prototype.filter.call(document.querySelectorAll('#toc-list .toc-li-l4'), function (li) { return !li.classList.contains('is-filtered'); }).length;
    input.value = '';
    input.dispatchEvent(new Event('input', { bubbles: true }));
    await new Promise(function (r) { setTimeout(r, 50); });
    out.filterResetFolds = folds.filter(function (d) { return !d.classList.contains('is-filtered'); }).length;
    // 5. 参照先のリンク
    var refs = Array.prototype.slice.call(document.querySelectorAll('#doc-content a.ref-link'));
    out.refLinks = refs.length;
    var ref = refs[30];
    out.refHref = ref ? ref.getAttribute('href') : null;
    if (ref) { ref.click(); await new Promise(function (r) { setTimeout(r, 1500); }); }
    var refTarget = ref ? document.getElementById(ref.getAttribute('href').substring(1)) : null;
    out.refTop = refTarget ? topOf(refTarget) : null;
    out.refText = refTarget ? refTarget.textContent : null;
    out.refOpened = refTarget ? refTarget.closest('details').open : null;
    // 6. JavaScript 無しの可読性（版面の性質）
    out.docMdIsJson = !!document.querySelector('script#doc-md[type="application/json"]');
    return JSON.stringify(out);
  })()`;
}

(async () => {
  const failures = [];
  const reports = [];
  const fixture = renderFixture();
  const raw = await withPage('common-doc-navigation', 1200, async (page) => {
    await page.goto('file://' + fixture);
    return page.evaluate(measureScript());
  });
  const r = JSON.parse(raw);
  const expectedToc = CHAPTERS + FUNCTIONS + 2; // 章13 + 12.1/12.2 + 関数41
  reports.push(`目次: 全${r.tocTotal}件（章${r.tocL2}・関数${r.tocL4}）／ページ内リンク ${r.anchors}件（解決 ${r.anchorsResolved}件）／折りたたみ ${r.folds}件（閉 ${r.foldsClosed}・関数 ${r.functionFolds}）`);
  if (r.tocL2 !== CHAPTERS || r.tocL4 !== FUNCTIONS || r.tocTotal !== expectedToc) failures.push(`検収1: 目次が章${CHAPTERS}+節2+関数${FUNCTIONS}=${expectedToc}件になっていない（実際 ${r.tocTotal}）`);
  if (!(r.anchors > 0) || r.anchorsResolved !== r.anchors) failures.push(`検収2: ページ内リンクが無いか解決しない（${r.anchorsResolved}/${r.anchors}）`);
  if (!r.tocLinkFound || r.movedTop < 0 || r.movedTop > 200 || r.movedOpened !== true) failures.push(`検収2: 目次のクリックで見出しへ移動しない（top=${r.movedTop} opened=${r.movedOpened}）`);
  if (r.functionFolds !== FUNCTIONS || r.foldsClosed !== r.folds) failures.push(`検収3: 関数ごとの表が既定で閉じていない（folds=${r.folds} closed=${r.foldsClosed} fn=${r.functionFolds}）`);
  if (r.beforeClickOpen !== false || r.afterClickOpen !== true) failures.push(`検収3: 見出しのクリックで開かない（${r.beforeClickOpen}→${r.afterClickOpen}）`);
  // fn_3, fn_30..fn_39 の 11 件が一致するのが正しい
  if (!r.filterInput || r.filterVisibleFolds !== 11 || r.filterVisibleToc !== 11 || !/^11件/.test(r.filterCount) || r.filterResetFolds !== r.folds) failures.push(`検収4: 絞り込みが見出しを残さない（folds=${r.filterVisibleFolds} toc=${r.filterVisibleToc} count=${r.filterCount} reset=${r.filterResetFolds}）`);
  if (r.refLinks !== FUNCTIONS) failures.push(`検収5: 参照先の値がリンクになっていない（${r.refLinks}/${FUNCTIONS}）`);
  if (r.refText !== 'fn_31' || r.refTop < 0 || r.refTop > 200 || r.refOpened !== true) failures.push(`検収5: 参照先のクリックで関数ごとの表へ移動しない（text=${r.refText} top=${r.refTop} opened=${r.refOpened}）`);
  reports.push('検収6: この版面は本文を <script type="application/json" id="doc-md"> から JavaScript で組み立てる' + (r.docMdIsJson ? '（確認）' : '（未確認）') + '。JavaScript を無効にすると本項目の変更に関わらず白紙になる。既存の性質であり本項目の対象外');
  reports.forEach((line) => console.log(`INFO: ${line}`));
  if (failures.length) { failures.forEach((line) => console.error(`FAIL: ${line}`)); process.exitCode = 1; return; }
  console.log(`PASS: 共通の版面で、章${CHAPTERS}・関数${FUNCTIONS}の合成入力に対し、階層目次・ページ内リンク・閉じた折りたたみ・絞り込み・参照先のリンク化の5点が実描画で機能する`);
})().catch((error) => {
  if (reportIfUnavailable(error)) { process.exitCode = 2; return; }
  console.error(error);
  process.exitCode = 1;
});
