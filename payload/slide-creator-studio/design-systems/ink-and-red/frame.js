'use strict';
// スライドの外側(.dc.html の決まった形、骨組み、資料の名前とタイトルの行、結論の一文、ページ番号)を作る関数。
// frame(data, deck, tokens, rendered) → .dc.html の全文。rendered は、テンプレートの render が返す { css, body }。
// 見出しの面を持たない。結論の一文の \n は、改行(<br>)にする。
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
  const deckTitle = data.deckTitle || deck.title;
  const conclusion = P.conclusionHtml(data.conclusion);
  const weights = (V('太さの段') || [400, 700]).join(';');
  const families = String(V('日本語のフォントの名前')).split(',').map((f) => f.replace(/'/g, '').trim()).filter((f) => f && f !== 'sans-serif')
    .map((f) => `family=${f.replace(/ /g, '+')}:wght@${weights}`).join('&');
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
<link href="https://fonts.googleapis.com/css2?${families}&display=swap" rel="stylesheet">
<style>
${css}
</style>
</helmet>
<div class="s">
<div class="hd" data-part="資料の名前とタイトル"><span ${T('資料の名前')}>${esc(deckTitle)}</span><i>${esc(V('区切りの記号'))}</i><span ${T('タイトル')}>${esc(data.section)}</span></div>
<p ${T('結論の一文', 'cc')} data-part="結論の一文">${conclusion}</p>
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
