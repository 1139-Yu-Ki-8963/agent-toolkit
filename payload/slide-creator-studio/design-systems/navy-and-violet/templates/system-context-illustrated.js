'use strict';
// つながり(システムの範囲・イラスト)(作るシステムを中央に、左右に相手を 1 つずつ置き、渡すものを矢印で示す)。見本: examples/system-context-illustrated.data.json
const makeParts = require('../parts');
const illustration = require('../illustration');

module.exports = {
  name: 'system-context-illustrated',
  when: '作るシステムの相手が左右に 1 つずつで、両方の相手を表すイラスト(人物、場面、物)がある。左から、相手、作るシステム、相手のカードを並べ、相手とシステムの間に、渡すものの名前を添えた矢印を、行きと帰りで 1 本ずつ置く。作るシステムのカードを紫にして、作る範囲を示す。右の相手は、横顔の絵があれば、システムのほうを向く横顔を使う。相手が 3 つ以上のときは、この型を使わない。原則「矢印を、順番かつながりの意味がある所だけに置く」に合わせ、矢印は、渡すものの名前を持つ。',
  parts: ['列の上のラベル', '相手のカード', '主役のカード', 'イラストの枠', 'イラスト', '矢印', '矢印に添える名前'],
  schema: {
    partnerLabel: { type: 'text', required: true },
    systemLabel: { type: 'text', required: true },
    system: { type: 'object', required: true, fields: { name: { type: 'text', required: true, maxChars: 'つながりの名前の字数の上限' } } },
    leftPartner: { type: 'object', required: true, fields: partner() },
    rightPartner: { type: 'object', required: true, fields: partner() },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, S, e, px, r2 } = P;
    const B = V('間隔.まとまりとまとまり'); // まとまりとまとまりの間
    const c = data.content;
    const cardW = V('つながりの相手のカードの幅'), arrW = (W - cardW * 3) / 2;
    if (arrW < V('つながりの矢印の列の幅') - 0.5) throw new Error('矢印の列の幅が、値「つながりの矢印の列の幅」より狭い');
    const labH = V('文字の行の高さ.列の上のラベル');
    const cardH = V('本文領域の高さ') - labH - S;
    const pad = V('カードの余白'), inner = cardW - pad * 2, boxH = V('イラストの枠の高さ'), nameGap = V('絵と、絵が表す名前の間');
    const lab = (text) => `<div ${T('列の上のラベル')} data-part="列の上のラベル">${e(text)}</div>`;
    const partnerCard = (p) => `<div data-part="相手のカード" class="xc" style="height:${cardH}px;padding:0 ${pad}px">` +
      illustration(P, h, p.image, inner, boxH) +
      `<div ${T('図の中のカードの名前')} style="margin-top:${nameGap}px">${e(p.name)}</div>` +
      `<div ${T('図の中の説明')} style="margin-top:${S}px">${e(p.note)}</div></div>`;
    const systemCard = `<div data-part="主役のカード" data-emphasis class="xc mn" style="height:${cardH}px;padding:0 ${pad}px"><div ${T('図の中のカードの名前')}>${e(c.system.name)}</div></div>`;
    // 矢印。dir: 'r' は右向き、'l' は左向き。両端を、値「つながりの矢印の両端の余り」だけあける。
    const aW = arrW - V('つながりの矢印の両端の余り') * 2, aH = V('矢じりの底辺') + V('矢印の図の上下の余り'), depth = V('矢じりの奥行き'), half = V('矢じりの底辺') / 2, lw = V('矢印の線の太さ'), cy = aH / 2;
    const arrow = (dir) => `<svg data-part="矢印" width="${r2(aW)}" height="${aH}" viewBox="0 0 ${r2(aW)} ${aH}" aria-hidden="true">` +
      (dir === 'r' ? P.rightArrowShapes(0, aW, cy, 'var(--ink)') :
        `<path d="M${r2(aW)} ${cy}H${depth}" fill="none" style="stroke:var(--ink)" stroke-width="${lw}"/><path d="M${depth} ${cy - half}L0 ${cy}L${depth} ${cy + half}Z" style="fill:var(--ink)"/>`) + '</svg>';
    const flow = (text, dir, top) => `<div class="xf" style="margin-top:${top}px"><div ${T('矢印に添える名前')} data-part="矢印に添える名前">${e(text)}</div><div style="margin-top:${S}px">${arrow(dir)}</div></div>`;
    const arrows = (first, second) => `<div class="xa" style="height:${cardH}px">${flow(first[0], first[1], 0)}${flow(second[0], second[1], B)}</div>`;
    const css = `.xg{display:grid;grid-template-columns:${px(cardW)} ${px(arrW)} ${px(cardW)} ${px(arrW)} ${px(cardW)};row-gap:${S}px;width:${W}px}` +
      `.xc{box-sizing:border-box;background:var(--tint);border-radius:${V('カードの角丸')}px;display:flex;flex-direction:column;justify-content:center}` +
      `.xc.mn{background:var(--accent)}.xc.mn [data-role]{color:var(--bg)}` +
      `.xa{display:flex;flex-direction:column;justify-content:center;align-items:center}.xf{display:flex;flex-direction:column;align-items:center}`;
    const body = `<div class="xg" data-full-width>` +
      lab(c.partnerLabel) + '<div></div>' + lab(c.systemLabel) + '<div></div>' + lab(c.partnerLabel) +
      partnerCard(c.leftPartner) + arrows([c.leftPartner.gives, 'r'], [c.leftPartner.gets, 'l']) + systemCard + arrows([c.rightPartner.gets, 'r'], [c.rightPartner.gives, 'l']) + partnerCard(c.rightPartner) +
      '</div>';
    return { css, body };
  },
};

// 相手の欄。gives は、相手がシステムに渡すもの。gets は、システムが相手に渡すもの。
function partner() {
  return {
    image: { type: 'image', required: true },
    name: { type: 'text', required: true, maxChars: 'つながりの名前の字数の上限' },
    note: { type: 'text', required: true, maxChars: 'つながりの説明の字数の上限' },
    gives: { type: 'text', required: true, maxChars: 'つながりの矢印に添える名前の字数の上限' },
    gets: { type: 'text', required: true, maxChars: 'つながりの矢印に添える名前の字数の上限' },
  };
}
