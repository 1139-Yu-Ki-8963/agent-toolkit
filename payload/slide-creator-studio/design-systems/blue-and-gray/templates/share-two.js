'use strict';
// 割合(2 つの項目を持つ帯。見せたい項目 1 つだけを強調の色にする)。見本: examples/share-two.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'share-two',
  when: '全体を、2 つの項目に分ける。結論の一文が、帯の 2 つの項目の両方の値を言う。データの focus が指す見せたい項目 1 つだけを強調の色にし、もう 1 つを見せたい項目以外の色にして、値を、図に添える値の字で同じ大きさに置く。',
  parts: ['ラベル', '名前と値の行', '図に添える値', '主役の帯グラフ', '付録の番号'],
  schema: {
    denominator: { type: 'text', required: true },
    denominatorRef: { type: 'text' },
    items: {
      type: 'list', required: true, maxItems: '割合の単独の帯の項目の数の上限',
      item: { type: 'object', fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true } } },
    },
    focus: { type: 'text', required: true },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, W, S, px, span, label } = P;
    const c = data.content;
    if (!c.items.some((i) => i.name === c.focus)) throw new Error(`focus が items の名前にない: ${c.focus}`);
    const colGap = V('横に並べる列の間隔の下限');
    const total = c.items.reduce((a, i) => a + i.value.n, 0);
    const widths = c.items.map((i) => Math.round((W * i.value.n) / total));
    widths[widths.length - 1] = W - widths.slice(0, -1).reduce((a, b) => a + b, 0);
    const rowH = V('文字の行の高さ.図に添える値');
    const bandH = V('主役の帯グラフの高さ(図に添える値の行を持つ帯)');
    // 名前と値の行の左端は、自分の帯の左端と、前の行の右端+列の間隔の下限の大きい方。右の項目が本文領域からはみ出すときは、本文領域の右端に右ぞろえにする。
    const rowW = c.items.map((it) => P.roleW('項目の名前', it.name) + V('間隔.項目の名前と値') + P.roleW('図に添える値', h.quantity(it.value)));
    const lefts = [], toEnd = c.items.map(() => false);
    let bandLeft = 0, prevRight = -Infinity;
    c.items.forEach((it, i) => {
      let left = Math.max(bandLeft, prevRight + colGap);
      if (i === c.items.length - 1 && left + rowW[i] > W) { toEnd[i] = true; left = W - rowW[i]; }
      lefts.push(left);
      prevRight = left + rowW[i];
      bandLeft += widths[i];
    });
    const cells = c.items.map((it, i) => {
      const w = i + 1 < c.items.length && !toEnd[i + 1] ? px(lefts[i + 1] - lefts[i]) : 'auto';
      return `<div class="k" style="flex:0 0 ${w};${toEnd[i] ? 'margin-left:auto;' : ''}">${span('項目の名前', it.name)}${span('図に添える値', h.quantity(it.value), 'data-part="図に添える値"')}</div>`;
    });
    const segs = c.items.map((it, i) => `<div style="flex:0 0 ${px(widths[i])};background:var(${it.name === c.focus ? '--blue' : '--line'})"${it.name === c.focus ? ' data-emphasis' : ''}></div>`);
    const body =
      label(c.denominator, c.denominatorRef) +
      `\n<div class="it" data-part="名前と値の行" style="height:${rowH}px;margin-top:${S}px;line-height:${rowH}px">${cells.join('')}</div>` +
      `\n<div class="br" data-part="主役の帯グラフ" data-full-width style="height:${bandH}px;margin-top:${V('間隔.名前と値の行と棒')}px">${segs.join('')}</div>`;
    return { css: '', body };
  },
};
