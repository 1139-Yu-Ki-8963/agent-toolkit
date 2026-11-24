'use strict';
// 推移(縦棒の並び)。見本: examples/trend-bars.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'trend-bars',
  when: '1 つの量が、時点ごとに増えるか減る(2 時点より多い、6〜12 時点の推移)。時点の並びを、左から右への縦棒で見せ、各棒の上に値、下に時点の名前を置く。結論の一文が指す時点の棒 1 本を青にする。原則「図に本文領域の広さを使わせる」に合わせ、縦棒の最大の高さは、棒だけを図にする組み方の値とする。',
  parts: ['ラベル', '縦棒', '付録の番号'],
  schema: {
    label: { type: 'text', required: true },
    labelRef: { type: 'text' },
    items: {
      type: 'list', required: true, maxItems: '縦棒の数の上限',
      item: { type: 'object', fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true } } },
    },
    focus: { type: 'text', required: true },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, W, S, px, r2, span, label } = P;
    const c = data.content;
    const n = c.items.length;
    const gap = V('縦棒と縦棒の間の下限');
    const barW = V('縦棒の幅');
    const maxH = V('縦棒の最大の高さ');
    const valueH = V('文字の行の高さ.棒の値');
    const nameH = V('文字の行の高さ.項目の名前');
    const cellW = (W - gap * (n - 1)) / n;
    const maxN = Math.max(...c.items.map((i) => i.value.n));
    if (!c.items.some((i) => i.name === c.focus)) throw new Error(`focus が items の名前にない: ${c.focus}`);
    const cols = c.items.map((it) => {
      const f = it.name === c.focus;
      const bh = Math.round((it.value.n / maxN) * maxH);
      return `<div style="flex:0 0 ${px(cellW)};display:flex;flex-direction:column;align-items:flex-start">` +
        `<div style="height:${valueH}px;line-height:${valueH}px">${span('棒の値', h.quantity(it.value))}</div>` +
        `<div data-part="縦棒"${f ? ' data-emphasis' : ''} style="margin-top:${V('間隔.縦棒と値')}px;width:${barW}px;height:${bh}px;background:var(${f ? '--blue' : '--line'})"></div>` +
        `<div style="margin-top:${V('間隔.縦棒と時点の名前')}px;height:${nameH}px;line-height:${nameH}px">${span('項目の名前', it.name)}</div></div>`;
    });
    const body = label(c.label, c.labelRef) +
      `\n<div data-full-width style="display:flex;align-items:flex-end;column-gap:${gap}px;margin-top:${S}px">${cols.join('')}</div>`;
    return { css: '', body };
  },
};
