'use strict';
// 付録(数字の出どころの表)。見本: examples/source-table.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'source-table',
  when: '数字の出どころを並べる付録。資料の数字を、出どころ(記録)ごとのまとまりの行に、数字の名前、値、式か数え方で並べる。強調の色を持たない。原則「表の罫線を横線だけにする」に合わせ、罫線を引かず、行を間隔と出どころの面で分ける。',
  parts: ['表', '出どころの面'],
  schema: {
    headers: { type: 'list', required: true, maxItems: '付録の表の列数の上限', item: { type: 'text' } },
    groups: {
      type: 'list', required: true,
      item: {
        type: 'object',
        fields: {
          source: { type: 'text', required: true },
          period: { type: 'text' },
          rows: {
            type: 'list', required: true,
            item: {
              type: 'object',
              fields: {
                name: { type: 'text', required: true },
                value: { type: 'list', required: true, item: { type: 'quantity' } },
                how: { type: 'text', required: true },
              },
            },
          },
        },
      },
    },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, e } = P;
    const c = data.content;
    const lineH = V('文字の行の高さ.表のセル');
    const faceMin = V('出どころの面の高さの下限(2 行)');
    const cells = [];
    const th = (txt, extra = '') => `<div ${T('表の見出し', extra)} style="margin-bottom:${V('表の見出し行と最初の行の間')}px">${e(txt)}</div>`;
    cells.push(th(c.headers[0]), th(c.headers[1]), th(c.headers[2], 'r'), th(c.headers[3]));
    c.groups.forEach((g, gi) => {
      if (gi > 0) cells.push('<div class="gp"></div>');
      const n = g.rows.length;
      const period = g.period ? String(g.period).replace(/^、/, '').replace(/^[(（](.*)[)）]$/, '$1') : '';
      const faceH = Math.max(n * lineH, (period ? 2 : 1) * lineH + (faceMin - 2 * lineH));
      const rowH = faceH / n;
      const rs = `style="height:${rowH}px;line-height:${rowH}px"`;
      g.rows.forEach((r, ri) => {
        if (ri === 0) {
          cells.push(`<div class="so" data-part="出どころの面" style="grid-row:span ${n}"><span ${T('表のセル', 'sn')}>${e(g.source)}</span>${period ? `<span ${T('表のセル')}>${e(period)}</span>` : ''}</div>`);
        }
        cells.push(`<div ${T('表の行の名前')} ${rs}>${e(r.name)}</div>`);
        cells.push(`<div ${T('表のセル', 'v')} ${rs}>${e(r.value.map((q) => h.quantity(q)).join('、'))}</div>`);
        cells.push(`<div ${T('値の説明')} ${rs}>${e(r.how)}</div>`);
      });
    });
    return {
      css: '.tb .v{text-align:right}\n.tb .r{text-align:right}',
      body: `<div class="tb" data-part="表" data-full-width style="grid-template-columns:${V('出どころの面の幅')}px auto auto auto;width:${P.W}px;height:${V('本文領域の高さ')}px">\n${cells.join('\n')}\n</div>`,
    };
  },
};
