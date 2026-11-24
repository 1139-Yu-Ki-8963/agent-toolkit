'use strict';
// 2×2 の区画(縦の軸と横の軸の 2 つで、項目を 4 つの区画に置く)。見本: examples/quadrant.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'quadrant',
  when: '項目を、縦の軸と横の軸の 2 つの軸(それぞれ 2 つの値)で、2×2 の 4 つの区画に置く。結論の一文が、1 つの区画に入る項目を言う。結論の一文が指す項目の区画 1 つを赤の面にし、ほかの区画を枠線だけにする。原則「図に本文領域の広さを使わせる」に合わせ、区画の高さは、本文領域の高さから、軸の見出しの行と間隔を引いた値を 2 つに分けた値とする。',
  parts: ['軸の見出し', '2×2の区画'],
  schema: {
    xName: { type: 'text', required: true },
    xValues: { type: 'list', required: true, maxItems: '区画の軸の値の数', item: { type: 'text' } },
    yName: { type: 'text', required: true },
    yValues: { type: 'list', required: true, maxItems: '区画の軸の値の数', item: { type: 'text' } },
    items: {
      type: 'list', required: true, maxItems: '2×2の区画に置く項目の数の上限',
      item: {
        type: 'object',
        fields: {
          name: { type: 'text', required: true },
          横の値: { type: 'text', required: true },
          縦の値: { type: 'text', required: true },
          values: {
            type: 'list', required: true, maxItems: '区画の項目の値の数の上限',
            item: { type: 'object', fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true } } },
          },
        },
      },
    },
    focus: { type: 'text', required: true },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, W, px, span } = P;
    const cellGap = V('間隔.区画と区画'), itemGap = V('間隔.区画の項目と項目'), valueGap = V('間隔.区画の項目の名前と値の行');
    const c = data.content;
    const headH = V('文字の行の高さ.ラベル');
    const headW = V('2×2の区画の行の見出しの列の幅');
    const cellH = Math.floor((V('本文領域の高さ') - headH - cellGap * 2) / 2); // 値でない: 2 は、区画の行の数(区画の軸の値の数)で割る数
    const pad = V('カードの余白');
    const cells = [];
    for (const y of c.yValues) {
      cells.push(`<div data-part="軸の見出し" class="qh" style="height:${cellH}px">${span('ラベル', `${c.yName} ${y}`)}</div>`);
      for (const x of c.xValues) {
        const here = c.items.filter((i) => i.横の値 === x && i.縦の値 === y);
        const red = here.some((i) => i.name === c.focus);
        const inner = here.map((i, k) =>
          `<div class="qi" style="margin-top:${k ? itemGap : 0}px">${span('図の中のカードの名前', i.name)}<div class="qv" style="margin-top:${valueGap}px">` +
          i.values.map((v) => `${span('図の中の説明', v.name)}${span('図の中の説明', h.quantity(v.value))}`).join('') + '</div></div>').join('');
        cells.push(`<div data-part="2×2の区画"${red ? ' data-emphasis' : ''} class="qc${red ? ' mn' : ''}" style="height:${cellH}px;padding:0 ${pad - 1}px">${inner}</div>`);
      }
    }
    const heads = `<div></div>` + c.xValues.map((x) => `<div data-part="軸の見出し" class="qh" style="height:${headH}px">${span('ラベル', `${c.xName} ${x}`)}</div>`).join('');
    const css = `.qd{display:grid;grid-template-columns:${headW}px repeat(${c.xValues.length},1fr);gap:${cellGap}px;width:${W}px}` +
      `.qh{display:flex;align-items:center}.qh [data-role]{white-space:normal}.qc{box-sizing:border-box;border:${V('カードの枠線の太さ')}px solid var(--line);border-radius:${V('カードの角丸')}px;display:flex;flex-direction:column;justify-content:center;background:var(--bg)}` +
      `.qc.mn{background:var(--red);border-color:var(--red)}.qc.mn [data-role]{color:var(--bg)}.qv{display:flex;align-items:baseline;gap:${V('間隔.区画の値の名前と値')}px}.qv>span:nth-child(2n){margin-right:${V('間隔.区画の値の組と組') - V('間隔.区画の値の名前と値')}px}`;
    return { css, body: `<div class="qd" data-full-width>${heads}${cells.join('')}</div>` };
  },
};
