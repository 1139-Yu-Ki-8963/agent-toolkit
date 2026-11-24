'use strict';
// 一文(主張を 1 文だけ、大きい字で見せる。主語を表す絵を 1 点だけ添えられる)。見本: examples/one-sentence.data.json
const makeParts = require('../parts');
const illustration = require('../illustration');

module.exports = {
  name: 'one-sentence',
  when: '主張だけを伝える。資料の中で、いちばん覚えてほしい 1 文を、結論の一文と同じ語で、本文領域に大きい字で置く。文の主語を表すイラストがあるときは、文の右に 1 点だけ添える。原則「一文のスライドを資料に少なく置く」に合わせ、資料に置く枚数は、値「一文のスライドの枚数の上限」まで。数字で比べる話と、手順の話は、図の型を使う。',
  parts: ['一文のスライドの文', 'イラストの枠', 'イラスト'],
  schema: {
    image: { type: 'image' },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, e, px } = P;
    const B = V('間隔.まとまりとまとまり'); // まとまりとまとまりの間
    const c = data.content;
    const text = String(data.conclusion).replace(/\r?\n/g, '');
    const boxW = V('イラストの枠の幅(一文)'), boxH = V('イラストの枠の高さ(一文)');
    const textW = c.image ? W - B - boxW : W;
    const lines = Math.ceil(P.roleW('一文のスライドの文', text) / textW - 1e-9);
    if (lines > V('一文のスライドの文の行数の上限')) throw new Error(`一文のスライドの文が ${lines} 行で、値「一文のスライドの文の行数の上限」を超える`);
    const sentence = `<div ${T('一文のスライドの文')} data-part="一文のスライドの文" style="width:${px(textW)};white-space:normal">${e(text)}</div>`;
    const image = c.image ? illustration(P, h, c.image, boxW, boxH) : '';
    return { css: '', body: `<div data-full-width style="display:flex;align-items:center;justify-content:space-between;width:${W}px">${sentence}${image}</div>` };
  },
};
