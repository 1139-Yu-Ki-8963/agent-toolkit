'use strict';
// 利用者の声や課題(話し手ごとに、絵、立場の名前、声の引用を縦に並べた列)。見本: examples/voices.data.json
const makeParts = require('../parts');
const illustration = require('../illustration');

module.exports = {
  name: 'voices',
  when: '利用者や関係者の声を、話し手ごとに並べる(1〜3 人)。話し手ごとに、人物(正面)のイラスト、立場の名前、声の引用(2 行まで)の列を置く。元の資料が 1 つの声を最も重いとしているときは、その声を focus にして左端に置き、立場の名前を紫にする。話し手を持たない項目は、この型を使わない。原則「見せ方の型を、見せたい関係で選ぶ」の関係「声」。4 人以上の声は、3 人までずつ、2 枚以上に分ける。',
  parts: ['声の列', 'イラストの枠', 'イラスト'],
  schema: {
    voices: {
      type: 'list', required: true, maxItems: '声の数の上限',
      item: {
        type: 'object',
        fields: {
          image: { type: 'image', required: true },
          role: { type: 'text', required: true, maxChars: '声の立場の名前の字数の上限' },
          quote: { type: 'text', required: true, maxChars: '声の引用の字数の上限' },
        },
      },
    },
    focus: { type: 'text' },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, S, e, px } = P;
    const B = V('間隔.まとまりとまとまり'); // まとまりとまとまりの間
    const c = data.content;
    if (c.focus && !c.voices.some((v) => v.role === c.focus)) throw new Error(`focus が voices の role にない: ${c.focus}`);
    // 最も重い声(focus)を、左端に置く。ほかの声は、データの順のまま。
    const voices = c.focus ? [...c.voices.filter((v) => v.role === c.focus), ...c.voices.filter((v) => v.role !== c.focus)] : c.voices;
    const n = voices.length;
    const colW = (W - (n - 1) * B) / n;
    const boxH = V('イラストの枠の高さ'), gap = V('絵と、絵が表す名前の間');
    const cols = voices.map((v) => {
      const f = v.role === c.focus;
      return `<div data-part="声の列" style="width:${px(colW)}">` + illustration(P, h, v.image, colW, boxH, { align: 'left' }) +
        `<div ${T('図の中のカードの名前')}${f ? ' data-emphasis' : ''} style="margin-top:${gap}px${f ? ';color:var(--accent)' : ''}">${e(v.role)}</div>` +
        `<div ${T('本文')} style="margin-top:${S}px;white-space:normal">${e(v.quote)}</div></div>`;
    });
    return { css: '', body: `<div data-full-width style="display:flex;align-items:flex-start;gap:${B}px;width:${W}px">${cols.join('')}</div>` };
  },
};
