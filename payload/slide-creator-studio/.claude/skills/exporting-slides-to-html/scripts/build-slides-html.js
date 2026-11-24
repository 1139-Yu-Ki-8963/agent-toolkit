#!/usr/bin/env node
// ページのスライドのファイル(.dc.html)を、全ページを 1 つにまとめた HTML にするスクリプト。
//
// 使い方:
//   node build-slides-html.js <元のファイルを置くフォルダ> [--name <資料の名前>] [--out <まとめた HTML を書くフォルダ>] [まとめるスライドのファイルの名前 ...]
//
// - スクリプトは、フォルダの canvas.json を読み、order の順に、ページのスライドを 1 ページずつ入れる。
//   案のスライドと、使わなかったスライドは、入れずに、結果の excluded に名前を出す
//   (案のスライド: ファイルの名前が「-alt<数字>.dc.html」で終わるもの。使わなかったスライド: canvas.json の題が「使わなかったスライド 」で始まるもの)。
//   スライドのファイルの名前を渡したときは、ページのスライドのうち、そのスライドだけを、order の順に入れる。
// - スクリプトは、まとめた HTML を、同じフォルダに、「<資料の名前>スライド.html」の名前で書く。
//   --out を渡したときは、そのフォルダに書く(スクリプトを試すときに使う)。
//   資料の名前は、--name の値とする。--name がないときは、canvas.json の title とする。
// - まとめた HTML は、1 ページを 1 つの iframe(srcdoc)に入れ、表示しているページだけを見せる。
//   ページは、下のボタンと、キー(→、←、PageDown、PageUp、空白、Home、End)で切り替わる。
//   ページの大きさは、canvas.json のスライドの幅と高さ(w と h)とし、ウィンドウに合わせて縮める。
// - スクリプトは、結果を JSON で標準出力に出す。

const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
let docName = '';
const nameAt = args.indexOf('--name');
if (nameAt !== -1) {
  docName = args[nameAt + 1] ?? '';
  if (!docName) throw new Error('--name の後ろに、資料の名前がない');
  args.splice(nameAt, 2);
}
let outDir = '';
const outAt = args.indexOf('--out');
if (outAt !== -1) {
  outDir = args[outAt + 1] ?? '';
  if (!outDir) throw new Error('--out の後ろに、まとめた HTML を書くフォルダがない');
  args.splice(outAt, 2);
}
const [dirArg, ...only] = args;
if (!dirArg) {
  console.error('使い方: node build-slides-html.js <元のファイルを置くフォルダ> [--name <資料の名前>] [--out <まとめた HTML を書くフォルダ>] [まとめるスライドのファイルの名前 ...]');
  process.exit(1);
}
const dir = path.resolve(dirArg);
const canvas = JSON.parse(fs.readFileSync(path.join(dir, 'canvas.json'), 'utf8'));
// まとめた HTML のファイルの名前の末尾。
const SUFFIX = 'スライド';
// 案のスライドのファイルの名前は、「-alt<案の番号>.dc.html」で終わる。
const ALT_SLIDE = /-alt\d+\.dc\.html$/;
// 使わなかったスライドの題は、「使わなかったスライド 」で始まる。
const UNUSED_TITLE = '使わなかったスライド ';
if (!docName) {
  if (!canvas.title) throw new Error('canvas.json に title がない。--name で資料の名前を渡す');
  docName = canvas.title;
}
const htmlName = `${docName}${SUFFIX}`;
for (const name of canvas.order) {
  if (!canvas.boards[name]) throw new Error(`canvas.json の boards にないスライド: ${name}`);
}
// まとめた HTML は、ページのスライドだけを持つ。
const isPage = (name) => !ALT_SLIDE.test(name) && !(canvas.boards[name].title ?? '').startsWith(UNUSED_TITLE);
const pageNames = canvas.order.filter(isPage);
const excluded = canvas.order.filter((name) => !isPage(name));
for (const name of only) {
  if (!canvas.order.includes(name)) throw new Error(`canvas.json の order にないスライド: ${name}`);
  if (!pageNames.includes(name)) throw new Error(`ページのスライドでないスライド(案のスライドか、使わなかったスライド)は、まとめた HTML に入れない: ${name}`);
}
const names = pageNames.filter((name) => only.length === 0 || only.includes(name));
if (names.length === 0) throw new Error('まとめるスライドが 1 つもない');

const sizes = new Set(names.map((name) => `${canvas.boards[name].w}x${canvas.boards[name].h}`));
if (sizes.size !== 1) throw new Error(`スライドの大きさが 1 つにそろっていない: ${[...sizes].join(', ')}`);
const W = canvas.boards[names[0]].w;
const H = canvas.boards[names[0]].h;

const KEY_SCRIPT = '<script>document.addEventListener("keydown",function(e){parent.postMessage({slideKey:e.key},"*")});</script>';
const escapeHtml = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

let docLang = '';
const slides = names.map((name) => {
  const text = fs.readFileSync(path.join(dir, name), 'utf8');
  const lang = text.match(/<html[^>]*\slang="([^"]+)"/i)?.[1] ?? 'ja';
  const head = text.match(/<helmet>([\s\S]*?)<\/helmet>/i)?.[1];
  const body = text.match(/<x-dc[^>]*>([\s\S]*)<\/x-dc>/i)?.[1].replace(/<helmet>[\s\S]*?<\/helmet>/i, '');
  if (head === undefined || body === undefined) throw new Error(`helmet か x-dc がない: ${name}`);
  docLang = docLang || lang;
  return {
    title: canvas.boards[name].title,
    html: `<!doctype html><html lang="${lang}"><head><meta charset="utf-8">${head}</head><body>${body}${KEY_SCRIPT}</body></html>`,
  };
});

// script の要素の中に置くので、「</」と「<!--」を、HTML として読まれない形にする。
const slidesJson = JSON.stringify(slides).replace(/<\//g, '<\\/').replace(/<!--/g, '\\u003c!--');

const BAR = 56; // ページを切り替えるボタンの行の高さ(px)
const html = `<!doctype html>
<html lang="${docLang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(htmlName)}</title>
<style>
html,body{margin:0;height:100%;background:ButtonFace;font-family:sans-serif;color:CanvasText;overflow:hidden}
#wrap{position:absolute;left:0;top:0;right:0;bottom:${BAR}px;display:flex;align-items:center;justify-content:center}
#stage{position:relative;width:${W}px;height:${H}px;flex:none;transform-origin:center center;box-shadow:0 0 0 1px GrayText}
#stage iframe{position:absolute;left:0;top:0;width:${W}px;height:${H}px;border:0;background:Canvas}
#stage iframe[hidden]{display:none}
#bar{position:absolute;left:0;right:0;bottom:0;height:${BAR}px;display:flex;align-items:center;justify-content:center;gap:16px;font-size:16px}
#bar button{font:inherit;font-weight:700;width:44px;height:36px;border:2px solid CanvasText;border-radius:8px;background:Canvas;color:CanvasText;cursor:pointer}
#bar button:active{transform:scale(.97)}
#no{min-width:80px;text-align:center;font-weight:700}
</style>
</head>
<body>
<div id="wrap"><div id="stage"></div></div>
<div id="bar"><button id="prev" type="button" aria-label="前のスライド">←</button><span id="no"></span><button id="next" type="button" aria-label="次のスライド">→</button></div>
<script>
var slides = ${slidesJson};
var stage = document.getElementById('stage');
var frames = slides.map(function (s) {
  var f = document.createElement('iframe');
  f.title = s.title;
  f.hidden = true;
  f.srcdoc = s.html;
  stage.appendChild(f);
  return f;
});
var cur = 0;
function show(i) {
  cur = Math.max(0, Math.min(frames.length - 1, i));
  frames.forEach(function (f, k) { f.hidden = k !== cur; });
  document.getElementById('no').textContent = (cur + 1) + ' / ' + frames.length;
  if (location.hash !== '#' + (cur + 1)) { history.replaceState(null, '', '#' + (cur + 1)); }
}
function fit() {
  var w = window.innerWidth, h = window.innerHeight - ${BAR};
  stage.style.transform = 'scale(' + Math.min(w / ${W}, h / ${H}) + ')';
}
function key(k) {
  if (k === 'ArrowRight' || k === 'PageDown' || k === ' ') { show(cur + 1); }
  if (k === 'ArrowLeft' || k === 'PageUp') { show(cur - 1); }
  if (k === 'Home') { show(0); }
  if (k === 'End') { show(frames.length - 1); }
}
document.addEventListener('keydown', function (e) { key(e.key); });
window.addEventListener('message', function (e) { if (e.data && e.data.slideKey) { key(e.data.slideKey); } });
document.getElementById('prev').addEventListener('click', function () { show(cur - 1); });
document.getElementById('next').addEventListener('click', function () { show(cur + 1); });
window.addEventListener('resize', fit);
fit();
show((parseInt(location.hash.slice(1), 10) || 1) - 1);
</script>
</body>
</html>
`;

const out = path.join(outDir ? path.resolve(outDir) : dir, `${htmlName}.html`);
fs.writeFileSync(out, html);
console.log(JSON.stringify({ out, pages: slides.length, width: W, height: H, titles: slides.map((s) => s.title), excluded }, null, 2));
