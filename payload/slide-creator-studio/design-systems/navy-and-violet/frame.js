'use strict';
// スライドの外側(.dc.html の決まった形、骨組み、資料の名前、結論の一文、ページ番号)を作る関数。
// frame(data, deck, tokens, rendered) → .dc.html の全文。rendered は、テンプレートの render が返す { css, body }。
// 結論の一文が 1 行か 2 行かは、parts.js の conclusionHtml が、字数(parts.js の countChars。半角の数字は、値「数字の半角の幅(字の大きさに対する比)」の字)から決める。
const fs = require('fs');
const path = require('path');
const makeParts = require('./parts');

const BASE_CSS = fs.readFileSync(path.join(__dirname, 'base.css'), 'utf8');

function frame(data, deck, tokens, rendered) {
  const value = (name) => {
    const hit = (tokens.values && tokens.values[name]) || (tokens.local && tokens.local[name]);
    return hit ? hit.value : undefined;
  };
  const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const P = makeParts(tokens, { value, esc, quantity: () => '' });
  const { V, T } = P;
  // 骨組みの位置は、結論の一文が 1 行でも 2 行でも同じにする(原則「全スライドを一つのグリッドに従わせる」)。
  const hdTop = V('資料の名前とタイトルの行の上端(結論の一文が 2 行)');
  const ccTop = V('結論の一文の上端(結論の一文が 2 行)');
  const deckTitle = data.deckTitle || deck.title;
  const conclusion = P.conclusionHtml(data.conclusion);
  const weights = (V('太さの段') || [400, 700]).join(';');
  const fontFamily = String(V('日本語のフォントの名前')).split(',')[0].replace(/'/g, '').trim().replace(/ /g, '+');
  const css = BASE_CSS + (rendered.css ? '\n' + rendered.css : '');
  // そのスライドの中身のデータ(.data.json の全文)。tools/extract.js が取り出す。`<` は `<` にして、`</script>` を中に出さない。
  const slideData = JSON.stringify(data, null, 2).replace(/</g, '\\u003c');
  return `<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<title>${esc(data.section)}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link href="https://fonts.googleapis.com/css2?family=${fontFamily}:wght@${weights}&display=swap" rel="stylesheet">
<style>
${css}
</style>
</helmet>
<div class="s">
<div class="hb" data-part="見出しの面"></div>
<div class="hd" data-part="資料の名前とタイトル" style="top:${hdTop}px"><span ${T('資料の名前')}>${esc(deckTitle)}</span><span ${T('タイトル')}>${esc(data.section)}</span></div>
<p ${T('結論の一文', 'cc')} data-part="結論の一文" style="top:${ccTop}px">${conclusion}</p>
<div class="bd" data-part="本文領域">
${rendered.body}
</div>
<div ${T('ページ番号', 'ft')} data-part="ページ番号">${esc(data.page)}</div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{"$preview":{"width":${V('スライドの幅')},"height":${V('スライドの高さ')}}}'>
class Component extends DCLogic {
renderVals() {
return {};
}
}
</script>
<script type="application/json" data-slide-data>${slideData}</script>
</body>
</html>
`;
}

module.exports = { frame, countChars: makeParts.countChars };
