'use strict';
// 量の比較(棒 2 本)。見本: examples/compare-two.data.json
const makeParts = require('../parts');
const compareBars = require('../compare-bars');

module.exports = {
  name: 'compare-two',
  when: '2 つの量を比べる。単位をそろえた 2 つの量を、同じ左端と同じ目盛りの棒で比べ、結論の一文が指す量の棒 1 本を青にする。棒は、データの items の順に上から並べ、値の大きさで並べ替えない(部品「量を比べる棒」)。軸は、いつも棒の下に引く。全体の量が決まっているときは、全体の量を本文領域の幅いっぱいにした目盛りと、全体の長さの軸にし、決まっていないときは、いちばん長い棒を幅いっぱいにした目盛りと、その長さの軸にする(部品「軸」)。原則「図に本文領域の広さを使わせる」に合わせ、棒の高さは、棒だけを図にする組み方の値とする。',
  parts: ['ラベル', '名前と値の行', '量を比べる棒', '軸', '付録の番号'],
  schema: {
    label: { type: 'text', required: true },
    labelRef: { type: 'text' },
    items: {
      type: 'list', required: true, maxItems: '前後の棒の数',
      item: { type: 'object', fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true }, note: { type: 'text' }, } },
    },
    focus: { type: 'text', required: true },
    axisMax: { type: 'object', fields: { total: { type: 'quantity', required: true }, name: { type: 'text' } } },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    return { css: '', body: compareBars(P, h, data.content) };
  },
};
