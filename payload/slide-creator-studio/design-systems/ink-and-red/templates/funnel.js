'use strict';
// 段ごとの人数の減り方(横棒の段。上から下へだんだん短くなる)。見本: examples/funnel.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'funnel',
  when: '段階を順に通るうちに、残った量が減っていく(2〜4 段の、段ごとの量)。段ごとの残った量を、同じ左端と同じ目盛りの横棒で、上から下へ段の順に並べ、結論の一文が指す段の棒 1 本を赤にする。いちばん上の段の量が、本文領域の幅いっぱいの棒になる。原則「図に本文領域の広さを使わせる」に合わせ、棒の高さは、4 本の棒の値を使う。結論の一文が指す段の値も、ほかの段と同じ棒の値の字(44px、行の高さ 62px)のままにし、主な数字(88px、行の高さ 96px)にしない。4 段の図は、ラベルと 4 つの行と棒と間で 620px で、1 つの行を 96px にすると 654px になり、本文領域の高さ(650px)を超えるからである。見せたい段は、赤い棒で見分けさせる。', // 値でない: when の文が、図の高さと幅の計算を説明する数で、描く値は V() で引く
  parts: ['ラベル', '名前と値の行', '量を比べる棒', '付録の番号'],
  schema: {
    label: { type: 'text', required: true },
    labelRef: { type: 'text' },
    items: {
      type: 'list', required: true, maxItems: '段ごとの棒の数の上限',
      item: { type: 'object', fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true } } },
    },
    focus: { type: 'text', required: true },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, W, S, px, span, label } = P;
    const rowGap = V('間隔.棒と次の項目の行'), barGap = V('間隔.名前と値の行と棒');
    const c = data.content;
    const barH = V('量を比べる棒の高さ(4 本)');
    const rowH = V('文字の行の高さ.棒の値');
    const maxN = Math.max(...c.items.map((i) => i.value.n));
    const sc = W / maxN;
    if (!c.items.some((i) => i.name === c.focus)) throw new Error(`focus が items の名前にない: ${c.focus}`);
    const rows = c.items.map((it, i) => {
      const f = it.name === c.focus;
      return `<div class="it" data-part="名前と値の行" style="height:${rowH}px;margin-top:${i === 0 ? S : rowGap}px;line-height:${rowH}px"><div class="k">` +
        span('項目の名前', it.name) + span('棒の値', h.quantity(it.value)) + '</div></div>' +
        `\n<div data-part="量を比べる棒"${f ? ' data-emphasis' : ''}${i === 0 ? ' data-full-width' : ''} style="height:${barH}px;margin-top:${barGap}px;width:${px(it.value.n * sc)};background:var(${f ? '--red' : '--line'})"></div>`;
    });
    return { css: '', body: label(c.label, c.labelRef) + '\n' + rows.join('\n') };
  },
};
