'use strict';
// つながり(土台と、差し替えるものの関係)。見本: examples/base-and-swap.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'base-and-swap',
  when: '土台と、差し替えるものの関係を言う。1 つの共通のものの上に、差し替えられるものが載り、その上を手順が通る。上から、手順を持つものの帯、差し替えるカードの段、土台の帯の 3 段で見せ、選んだ 1 つを主役のカードにする。原則「役割の違う部品を、形か色で見分けられるようにする」に合わせ、変わらないものは濃い帯、差し替えるものは薄いカードにする。',
  parts: ['土台の帯', '図の中のカード', '主役のカード', '列の上のラベル'],
  schema: {
    process: { type: 'object', required: true, fields: { name: { type: 'text', required: true }, note: { type: 'text', required: true } } },
    swapLabel: { type: 'text', required: true },
    options: {
      type: 'list', required: true, maxItems: '差し替えるカードの数の上限',
      item: { type: 'object', fields: { name: { type: 'text', required: true }, note: { type: 'text', required: true } } },
    },
    selected: { type: 'text', required: true },
    foundation: { type: 'object', required: true, fields: { name: { type: 'text', required: true }, note: { type: 'text', required: true } } },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, e, px, span } = P;
    const c = data.content;
    const n = c.options.length;
    const colW = (W - V('つながりの差し替えるカードの間') * (n - 1)) / n;
    const band = (b) => `<div class="band" data-part="土台の帯" data-full-width>${span('図の中のカードの名前', b.name)}${span('補う説明', b.note)}</div>`;
    const cards = c.options.map((o) => {
      const sel = o.name === c.selected;
      // data-part は、部品の名前をそのままの字で書く(tools/check.js の部品の実装の検査が、字で探す)。
      const attr = sel ? 'class="card main" data-part="主役のカード" data-emphasis' : 'class="card" data-part="図の中のカード"';
      return `<div ${attr}>${span('図の中のカードの名前', o.name)}${span('補う説明', o.note)}</div>`;
    });
    const body = band(c.process) +
      `\n<div ${T('列の上のラベル', 'lb')} data-part="列の上のラベル" style="margin-top:${V('間隔.上の帯と列の上のラベル')}px">${e(c.swapLabel)}</div>` +
      `\n<div class="cs" style="grid-template-columns:repeat(${n},${px(colW)})">${cards.join('')}</div>` +
      '\n' + band(c.foundation);
    return { css: '', body };
  },
};
