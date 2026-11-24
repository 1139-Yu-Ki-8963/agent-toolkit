'use strict';
// イラストの枠と、その中のイラストの HTML を作る。イラストを持つテンプレート(voices、steps-illustrated、system-context-illustrated、one-sentence)が使う。
// 絵の種類(人物、場面、手、物)は、illustration/illustrations.json から読む。一覧にない画像は、場面として置く。
// 絵は、縦横の比を保って、枠に収まる大きさに縮める。元の大きさより大きくしない(原則「画像を実寸以下で置く」)。
const path = require('path');
const LIST = require('./illustration/illustrations.json');

// opts.align: 人物の絵の左右の位置。'left' は枠の左端、省くと中央。
module.exports = function illustration(P, h, img, boxW, boxH, opts = {}) {
  const { V, px, r2 } = P;
  const size = h.imageSize(img);
  if (!size) throw new Error(`画像の大きさを読めない: ${img && img.src}`);
  const row = LIST.find((x) => x.file === path.basename(String(img.src)));
  const kind = row ? row.kind : '場面';
  const person = kind.startsWith('人物');
  const ratio = person ? V('人物の絵の高さの割合') : (kind === '手' || kind === '物') ? V('手と物の絵の高さの割合') : 1;
  const scale = Math.min(boxW / size.w, (boxH * ratio) / size.h, V('画像の拡大率の上限'));
  const w = size.w * scale, hh = size.h * scale;
  const left = person && opts.align === 'left' ? 0 : (boxW - w) / 2;
  const top = person ? boxH - hh : (boxH - hh) / 2;
  const image = h.image(img, `data-part="イラスト" style="position:absolute;left:${r2(left)}px;top:${r2(top)}px;width:${px(w)};height:${px(hh)}"`);
  return `<div data-part="イラストの枠" style="position:relative;flex:none;width:${px(boxW)};height:${px(boxH)};background:var(--bg)${opts.style ? ';' + opts.style : ''}">${image}</div>`;
};
