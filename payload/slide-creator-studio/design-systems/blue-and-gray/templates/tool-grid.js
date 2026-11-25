'use strict';
// 項目(行)と道具の一式(列)の格子。マスに、その一式の、その項目を受け持つ道具の名前を置き、道具の欠ける項目には空の枠を置く。見本: examples/tool-grid.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'tool-grid',
  when: '項目ごとに、どの道具(道具の一式)が受け持つかと、道具の欠ける項目を見せる。項目は 1 枚に 5 つまで。左の列に項目の名前を本文の字で置き、右に、道具の一式ごとの列を置いて、マスに、その一式の、その項目を受け持つ道具の名前を、本文の字で 1 つずつ縦に積む。元の資料が道具の欠けることを言う項目は、いちばん右の列に、空の枠(部品「値のないもの」)と、元の資料の言葉を置く。列には、その 1 枚の項目を受け持つ一式だけを置き、列の順は、資料の全部の格子で同じにする。受け持つ道具のない一式の列を置かないのは、空の列が幅を取り、道具の名前が細い列で何行にも折れて、本文領域に入らないからである。名前を言い換えずに道具の名前を見せる中身で、記号だけの格子にすると、元の資料の道具の名前が消える。',
  parts: ['表', '値のないもの'],
  schema: {
    label: { type: 'text' },
    sets: { type: 'list', required: true, maxItems: '道具の格子の一式の列の数の上限', item: { type: 'text' } },
    noneHeader: { type: 'text' },
    rows: {
      type: 'list', required: true, maxItems: '道具の格子の項目の数の上限',
      item: {
        type: 'object',
        fields: {
          name: { type: 'text', required: true },
          tools: { type: 'list', required: true, item: { type: 'list', item: { type: 'text' } } },
          none: { type: 'text' },
        },
      },
    },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, e } = P;
    const c = data.content;
    const hasNone = c.rows.some((r) => r.none);
    const nCol = 1 + c.sets.length + (hasNone ? 1 : 0);   // 値でない: 項目の列と、一式の列と、欠ける道具の列
    // 値のないものの枠の上下の内側の余白。字の大きさの 0.5 倍(カードの中の文字のまわりの余白の下限)から、行の高さの中の字の上下の空きを引いた値。
    const fs = P.roleSize('本文'), padY = fs * V('カードの中の文字のまわりの余白の下限') - (V('文字の行の高さ.本文') - fs) / 2;   // 値でない: 下限から行の中の空きを引く
    const cells = [];
    cells.push(`<div ${T('表の見出し')}></div>`);
    for (const s of c.sets) cells.push(`<div ${T('表の見出し')}>${e(s)}</div>`);
    if (hasNone) cells.push(`<div ${T('表の見出し')}>${e(c.noneHeader || '')}</div>`);
    c.rows.forEach((r) => {
      if (r.tools.length !== c.sets.length) throw new Error(`tools の数が sets の数と違う: ${r.name}`);
      cells.push('<div class="ru"></div>');
      cells.push(`<div ${T('本文', 'rn')}>${e(r.name)}</div>`);
      // 道具の名前の欧文(識別子)は、途中で折らない。折り返しは、空白の位置だけで行う(原則「ファイル名、URL、識別子を同じ行に置く」)。
      const keep = (t) => t.split(' ').map((w) => (/[\x21-\x7e]/.test(w) ? `<span class="nw">${e(w)}</span>` : e(w))).join(' ');
      r.tools.forEach((list) => cells.push(`<div class="tc">${list.map((t) => `<div ${T('本文')}>${keep(t)}</div>`).join('')}</div>`));
      if (hasNone) cells.push(r.none ? `<div class="nf" data-part="値のないもの"><div ${T('本文')}>${e(r.none)}</div></div>` : '<div></div>');
    });
    const css = `.tg{display:grid;grid-template-columns:max-content repeat(${nCol - 1}, auto);column-gap:${V('表の列と列の間')}px;row-gap:${V('表の行と行の間')}px;align-items:start;align-content:center}
.tg .ru{grid-column:1/-1;height:0;border-top:${V('表の罫線の太さ')}px solid var(--line)}
.tg [data-role]{white-space:normal}
.tg .nw{white-space:nowrap}
.tg .tc{display:flex;flex-direction:column;row-gap:${V('間隔.名前と、その中身')}px}
.tg .nf{box-sizing:border-box;border:${V('値のないものの枠の線の太さ')}px solid var(--sub);padding:${padY}px ${V('カードの余白')}px;margin-top:${-(padY + V('値のないものの枠の線の太さ'))}px}
.tg .nf [data-role]{white-space:normal}`;
    const label = c.label ? P.label(c.label) : '';
    return { css, body: `${label}<div class="tg" data-part="表" data-full-width style="width:${W}px">\n${cells.join('\n')}\n</div>` };
  },
};
