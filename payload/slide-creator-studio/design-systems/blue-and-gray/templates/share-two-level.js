'use strict';
// 2 段の内訳(全体を 2 つに分け、1 つをさらに 2 つに分ける、帯 2 本)。見本: examples/share-two-level.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'share-two-level',
  when: '全体を 2 つに分け、そのうち 1 つを、さらに 2 つに分ける(内訳が 2 段)。結論の一文が、2 段目の 1 つの項目を、いちばん大きいと言う。上の帯に全体の 2 つの項目、下の帯に、分けた項目の 2 つを、同じ目盛りで、分けた項目の真下に置き、2 段目の見せたい項目 1 つを青にする。原則「同じ話の要素を近くに置く」に合わせ、下の帯の左端と幅を、分けた項目の左端と幅にそろえる。下の帯の上に、「<分けた項目の名前と量>のうち」のラベルを、上の帯の下に、値「間隔.上の帯と下の帯のラベル」の間を置いて、下の帯の左端にそろえて置く。ラベルの右端が本文領域の右端を超えるときだけ、ラベルを本文領域の右端に右ぞろえにする。ラベルを 2 行に折り返す代わりに右へ寄せるのは、ラベルを 1 行の名前のまま、原則「要素を本文領域の中に置く」に合わせるためで、下の帯の左端より左に寄っても、ラベルの右端は、下の帯の右側の上に残る。',
  parts: ['ラベル', '名前と値の行', '帯グラフ', '付録の番号'],
  schema: {
    denominator: { type: 'text', required: true },
    denominatorRef: { type: 'text' },
    items: {
      type: 'list', required: true, maxItems: '割合の単独の帯の項目の数の上限',
      item: {
        type: 'object',
        fields: {
          name: { type: 'text', required: true },
          value: { type: 'quantity', required: true },
          children: {
            type: 'list', maxItems: '割合の単独の帯の項目の数の上限',
            item: { type: 'object', fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true } } },
          },
        },
      },
    },
    focus: { type: 'text', required: true },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, W, S, px, span, label } = P;
    const c = data.content;
    const gapV = V('隣り合う「ほか」の項目の間');
    const bandH = V('帯グラフを縦に並べる帯の高さ(2 本)');
    const parent = c.items.find((i) => i.children && i.children.length);
    if (!parent) throw new Error('children を持つ項目がない');
    const kidsSum = parent.children.reduce((a, i) => a + i.value.n, 0);
    if (kidsSum !== parent.value.n) throw new Error(`内訳の合計が合わない: ${kidsSum} と ${parent.value.n}`);
    const total = c.items.reduce((a, i) => a + i.value.n, 0);
    const gapsTop = c.items.map((it, i) => (i > 0 ? gapV : 0)); // 上の帯の項目は、どれも見せたい項目でない
    const availTop = W - gapsTop.reduce((a, b) => a + b, 0);
    const wTop = c.items.map((it) => (availTop * it.value.n) / total);
    const left = c.items.indexOf(parent) === 0 ? 0 : wTop.slice(0, c.items.indexOf(parent)).reduce((a, b) => a + b, 0) + gapsTop.slice(0, c.items.indexOf(parent) + 1).reduce((a, b) => a + b, 0);
    const pw = wTop[c.items.indexOf(parent)];
    const isF = (it) => it.name === c.focus;
    if (!parent.children.some(isF)) throw new Error(`focus が内訳の名前にない: ${c.focus}`);
    const gapsKid = parent.children.map((it, i) => (i > 0 && !isF(it) && !isF(parent.children[i - 1]) ? gapV : 0));
    const wKid = parent.children.map((it) => ((pw - gapsKid.reduce((a, b) => a + b, 0)) * it.value.n) / kidsSum);
    const rowTop = V('文字の行の高さ.棒の値');
    const rowKid = V('文字の行の高さ.主な数字');
    const cellTop = c.items.map((it, i) => `<div class="k" style="flex:0 0 ${px(wTop[i])};${gapsTop[i] ? `margin-left:${gapsTop[i]}px;` : ''}">${span('項目の名前', it.name)}${span('棒の値', h.quantity(it.value))}</div>`);
    const segTop = c.items.map((it, i) => `<div style="flex:0 0 ${px(wTop[i])};${gapsTop[i] ? `margin-left:${gapsTop[i]}px;` : ''}background:var(--line)"></div>`);
    const cellKid = parent.children.map((it, i) => {
      const f = isF(it);
      return `<div class="k" style="flex:0 0 ${px(wKid[i])};${gapsKid[i] ? `margin-left:${gapsKid[i]}px;` : ''}">${span('項目の名前', it.name)}${span(f ? '主な数字' : '棒の値', h.quantity(it.value))}</div>`;
    });
    const segKid = parent.children.map((it, i) => `<div style="flex:0 0 ${px(wKid[i])};${gapsKid[i] ? `margin-left:${gapsKid[i]}px;` : ''}background:var(${isF(it) ? '--blue' : '--line'})"${isF(it) ? ' data-emphasis' : ''}></div>`);
    // 下の帯のラベル: 分けた項目の名前と量(上の帯の項目から作る)。左端は下の帯の左端にそろえ、右端が本文領域を超えるときは右端にそろえる。
    const kidLabel = `${parent.name}${h.quantity(parent.value)}${V('内訳のラベルの語尾')}`;
    const kidLabelLeft = Math.min(left, W - P.roleW('ラベル', kidLabel));
    const body = label(c.denominator, c.denominatorRef) +
      `\n<div class="it" data-part="名前と値の行" style="height:${rowTop}px;margin-top:${S}px;line-height:${rowTop}px">${cellTop.join('')}</div>` +
      `\n<div class="br" data-part="帯グラフ" data-full-width style="height:${bandH}px;margin-top:${V('間隔.名前と値の行と棒')}px">${segTop.join('')}</div>\n` +
      label(kidLabel, null, `margin-top:${V('間隔.上の帯と下の帯のラベル')}px;margin-left:${px(kidLabelLeft)}`) +
      `\n<div class="it" data-part="名前と値の行" style="height:${rowKid}px;margin-top:${V('間隔.ラベルと主な数字の行')}px;margin-left:${px(left)};line-height:${rowKid}px">${cellKid.join('')}</div>` +
      `\n<div class="br" data-part="帯グラフ" style="height:${bandH}px;margin-top:${V('間隔.名前と値の行と棒')}px;margin-left:${px(left)};width:${px(pw)}">${segKid.join('')}</div>`;
    return { css: '', body };
  },
};
