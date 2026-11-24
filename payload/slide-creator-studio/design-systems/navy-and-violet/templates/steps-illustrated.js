'use strict';
// 手順(イラスト)(手順ごとに、絵、動作の見出し、1 行の説明を持つカードを、矢印でつないで横に並べる)。見本: examples/steps-illustrated.data.json
const makeParts = require('../parts');
const illustration = require('../illustration');

module.exports = {
  name: 'steps-illustrated',
  when: '2 つか 3 つの手順のすべてに、手順の中身を表すイラスト(場面、手、物)がある。手順ごとのカードを、左から右へ、矢印でつないで並べる。絵のない手順が 1 つでもあるときと、時点が日数を持つときは、timeline-steps を使う。結論の一文が 1 つの手順を指すときは、その手順の見出しを focus にして、カードを紫にする。原則「矢印でつないで横に並べるカードを絞る」に合わせ、カードは 3 つまで。',
  parts: ['手順のカード', 'ラベル', 'イラストの枠', 'イラスト', '矢印', '主役のカード'],
  schema: {
    steps: {
      type: 'list', required: true, maxItems: '矢印でつないで横に並べるカードの数の上限',
      item: {
        type: 'object',
        fields: {
          image: { type: 'image', required: true },
          heading: { type: 'text', required: true, maxChars: '手順(イラスト)の手順の見出しの字数の上限' },
          note: { type: 'text', required: true, maxChars: '手順(イラスト)の手順の説明の字数の上限' },
        },
      },
    },
    focus: { type: 'text' },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, S, e, px } = P;
    const c = data.content;
    const n = c.steps.length;
    if (n < 2) throw new Error('steps は、2 つか 3 つ');
    if (c.focus && !c.steps.some((s) => s.heading === c.focus)) throw new Error(`focus が steps の heading にない: ${c.focus}`);
    const gap = V('手順のカードの間'), pad = V('カードの余白'), boxH = V('イラストの枠の高さ'), nameGap = V('絵と、絵が表す名前の間');
    const cardW = (W - (n - 1) * gap) / n, inner = cardW - pad * 2;
    const arrowLen = V('手順の矢印の長さ'), aH = V('矢じりの底辺') + V('矢印の図の上下の余り'), a0 = (gap - arrowLen) / 2;
    const arrow = `<svg data-part="矢印" style="flex:none" width="${gap}" height="${aH}" viewBox="0 0 ${gap} ${aH}" aria-hidden="true">${P.rightArrowShapes(a0, a0 + arrowLen, aH / 2, 'var(--ink)')}</svg>`;
    const cards = c.steps.map((s, i) => {
      const f = s.heading === c.focus;
      return `<div ${f ? 'data-part="主役のカード"' : 'data-part="手順のカード"'}${f ? ' data-emphasis' : ''} class="sc${f ? ' mn' : ''}" style="width:${px(cardW)};padding:${pad}px">` +
        `<div ${T('ラベル')} data-part="ラベル">手順 ${i + 1}</div>` +
        illustration(P, h, s.image, inner, boxH, { style: `margin-top:${S}px` }) +
        `<div ${T('図の中のカードの名前')} style="margin-top:${nameGap}px">${e(s.heading)}</div>` +
        `<div ${T('図の中の説明')} style="margin-top:${S}px">${e(s.note)}</div></div>`;
    });
    const css = `.sc{box-sizing:border-box;flex:none;background:var(--tint);border-radius:${V('カードの角丸')}px}.sc.mn{background:var(--accent)}.sc.mn [data-role]{color:var(--bg)}`;
    return { css, body: `<div data-full-width style="display:flex;align-items:center;width:${W}px">${cards.join(arrow)}</div>` };
  },
};
