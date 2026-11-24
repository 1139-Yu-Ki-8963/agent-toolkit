'use strict';
// 量の比較(棒 2 本)。見本: examples/compare-two-with-formula.data.json
const makeParts = require('../parts');
const compareBars = require('../compare-bars');

module.exports = {
  name: 'compare-two-with-formula',
  when: '桁の違う 2 つの量を、式を添えて比べる。単位をそろえた 2 つの量の棒を、いちばん長い棒が本文領域の幅に入る目盛りで描き、棒の値の右に、計算の元の式を値の説明で添える。棒は、データの items の順に上から並べ、値の大きさで並べ替えない(部品「量を比べる棒」)。軸は、いちばん長い棒の長さで、棒の下に引く。原則「図に本文領域の広さを使わせる」に合わせ、棒の高さは、棒だけを図にする組み方の値とする。',
  parts: ['ラベル', '名前と値の行', '量を比べる棒', '軸', '付録の番号'],
  schema: {
    label: { type: 'text', required: true },
    labelRef: { type: 'text' },
    items: {
      type: 'list', required: true, maxItems: '前後の棒の数',
      item: { type: 'object', fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true }, note: { type: 'text', required: true }, } },
    },
    focus: { type: 'text', required: true },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    return { css: '', body: compareBars(P, h, data.content) };
  },
};
