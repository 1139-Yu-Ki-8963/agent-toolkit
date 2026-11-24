'use strict';
// 量の比較(棒 2 本)。見本: examples/compare-two-with-formula.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'compare-two-with-formula',
  when: '桁の違う 2 つの量を、式を添えて比べる。単位をそろえた 2 つの量の棒を、棒の右の値まで本文領域の幅に入る目盛りで描き、棒の上の行に、名前と計算の元の式を値の説明で添える。目盛り(量の 1 単位あたりの px)は、2 本の棒のどちらも、棒の右端と、16px 右の値の字の右端が本文領域の幅に入る、いちばん大きい値とし、整数に丸めない。丸めると、長い棒が本文領域の幅に届かず、図の右に、理由のない空きが残る。値は、棒の右に、棒の高さの上下の中央にそろえて置く。棒の上端か底にそろえると、値が、上か下の行に寄って見え、どの棒の値かが位置で決まらない。値を名前の行でなく棒の右に置く理由は、部品「名前と値の行」が持つ。 原則「図に本文領域の広さを使わせる」に合わせ、棒の高さは、棒だけを図にする組み方の値とする。', // 値でない: when の文が、図の高さと幅の計算を説明する数で、描く値は V() で引く
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
    const { V, W, S, px, span, label } = P;
    const c = data.content;
    const barH = V('量を比べる棒の高さ(2 本、3 本)');
    const gapV = V('量を比べる棒と値の間');
    const valueFine = (it) => (it.name === c.focus ? '主な数字' : '棒の値');
    // 目盛り: 棒の右端と、その右の値が、本文領域の幅に入る、いちばん大きい px。
    let sc = Infinity;
    for (const it of c.items) sc = Math.min(sc, (W - gapV - P.roleW(valueFine(it), h.quantity(it.value))) / it.value.n);
    const maxN = Math.max(...c.items.map((i) => i.value.n));
    const rows = c.items.map((it, i) => {
      const f = it.name === c.focus;
      const rowH = V(f ? '文字の行の高さ.主な数字' : '文字の行の高さ.棒の値');
      return `<div class="nm" data-part="名前と値の行" style="margin-top:${i === 0 ? S : V('間隔.式を持つ項目と項目')}px">${span('項目の名前', it.name)}${span('値の説明', it.note, `style="margin-left:${V('間隔.項目の名前と値の説明')}px"`)}</div>\n` +
        `<div class="rw" data-full-width style="height:${barH}px;margin-top:${V('間隔.名前と値の行と棒')}px"><i data-part="量を比べる棒"${f ? ' data-emphasis' : ''} style="width:${px(it.value.n * sc)};height:${barH}px;background:var(${f ? '--red' : '--line'})"></i>` +
        span(valueFine(it), h.quantity(it.value), `style="margin-left:${gapV}px"`) + '</div>';
    });
    const unit = c.items[0].value.unit;
    return {
      css: '.nm{display:flex;align-items:baseline;white-space:nowrap/*1 行に置く字の折り返しの指定*/}\n.rw{display:flex;align-items:center;white-space:nowrap/*1 行に置く字の折り返しの指定*/}\n.rw>i{display:block;flex:none}',
      body: label(c.label, c.labelRef) + '\n' + rows.join('\n') + '\n' + P.axis(maxN * sc, h.quantity({ n: maxN, unit }), h.quantity({ n: 0, unit })),
    };
  },
};
