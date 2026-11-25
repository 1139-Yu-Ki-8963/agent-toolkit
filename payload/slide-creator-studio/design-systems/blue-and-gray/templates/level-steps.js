'use strict';
// 工程の順(上から下へ、工程のカードを下向きの矢印でつなぎ、工程ごとに当たる項目を右に置く)。見本: examples/level-steps.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'level-steps',
  when: '元の資料が言う工程の順と、工程ごとに当たる項目を見せる。工程は 1 枚に 5 つまで。左の列に、工程の名前のカードを上から下へ工程の順に積み、カードとカードの間に下向きの矢印を引いて、順を形で見せる。工程ごとに、カードの右に、当たる項目を本文の字で左から右へ並べ、元の資料が工程の説明を持つときは、項目の上に 1 行で置く。工程が 6 つ以上のときは、2 枚に分け、2 枚目のいちばん上の工程の上に、前の枚から続く下向きの矢印を置く。時点が日数を持つ順は、この型でなく、timeline-steps にする。',
  parts: ['工程のカード', '矢印', 'ラベル'],
  schema: {
    continued: { type: 'text' },
    steps: {
      type: 'list', required: true, maxItems: '工程の順の工程の数の上限',
      item: {
        type: 'object',
        fields: {
          name: { type: 'text', required: true },
          note: { type: 'text' },
          blocks: { type: 'list', required: true, item: { type: 'object', fields: { label: { type: 'text' }, items: { type: 'list', required: true, item: { type: 'text' } } } } },
        },
      },
    },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, e, r2, px, roleW } = P;
    const c = data.content;
    const lineH = V('文字の行の高さ.本文'), itemGap = V('間隔.同じまとまりの部品と部品');
    const cardW = V('工程のカードの幅'), gapY = V('間隔.まとまりとまとまり'), colGap = V('間隔.まとまりとまとまり');
    const itemsX = cardW + colGap, itemsW = W - itemsX;
    // 行の高さ。説明の 1 行と、項目(とまとまりの名前)を左から右へ詰めた行の数(字の幅の見積もり)。
    const rowH = (s) => {
      let hgt = s.note ? Math.ceil(roleW('本文', s.note) / itemsW) * lineH : 0;
      for (const b of s.blocks) {
        if (b.label) hgt += Math.ceil(roleW('本文', b.label) / itemsW) * lineH;
        let used = 0, n = 1;
        for (const it of b.items) {
          const w = roleW('本文', it);
          if (used && used + itemGap + w > itemsW) { n++; used = w; } else used = used ? used + itemGap + w : w;
        }
        hgt += n * lineH;
      }
      return hgt;
    };
    const arrow = (hgt, label) => {
      const lw = V('矢印の線の太さ'), depth = V('矢じりの奥行き'), half = V('矢じりの底辺') / 2, cx = cardW / 2, m = V('間隔.名前と、その中身');   // 値でない: カードの左右の真ん中
      return `<svg data-part="矢印" width="${cardW}" height="${hgt}" viewBox="0 0 ${cardW} ${hgt}" aria-hidden="true"><path d="M${r2(cx)} ${m}V${hgt - m - depth}" fill="none" style="stroke:var(--ink)" stroke-width="${lw}"/><path d="M${r2(cx - half)} ${hgt - m - depth}L${r2(cx)} ${hgt - m}L${r2(cx + half)} ${hgt - m - depth}Z" style="fill:var(--ink)"/></svg>`;
    };
    const rows = c.steps.map((s, i) => {
      // カードの高さの下限は、カードの名前の字の大きさと、上下の、字の大きさに対する余白の下限の和(原則「カードの中の文字のまわりに余白を持たせる」)。
      const nameFs = V('文字の大きさ.図の中のカードの名前'), cardMinH = nameFs + 2 * nameFs * V('カードの中の文字のまわりの余白の下限');   // 値でない: 上と下の 2 つの余白
      const hgt = Math.max(rowH(s), lineH, cardMinH);
      const note = s.note ? `<div ${T('本文', 'sn')}>${e(s.note)}</div>` : '';
      const blocks = s.blocks.map((b) => `${b.label ? `<div ${T('本文', 'sn')}>${e(b.label)}</div>` : ''}<div class="sb">${b.items.map((it) => `<span ${T('本文')}>${e(it)}</span>`).join('')}</div>`).join('');
      return (i > 0 ? arrow(gapY) : '') +
        `<div class="sr" style="height:${px(hgt)}"><div class="sc" data-part="工程のカード"><div ${T('図の中のカードの名前')}>${e(s.name)}</div></div><div class="si">${note}${blocks}</div></div>`;
    });
    const head = c.continued ? `<div class="sh">${arrow(gapY)}<div ${T('ラベル')}>${e(c.continued)}</div></div>` : '';
    const css = `.ls{display:flex;flex-direction:column}
.ls .sr{display:grid;grid-template-columns:${cardW}px 1fr;column-gap:${colGap}px}
.ls .sc{background:var(--tint);border-radius:${V('カードの角丸')}px;padding:0 ${V('カードの余白')}px;display:flex;align-items:center;justify-content:center;text-align:center}
.ls .sn{white-space:normal}
.ls .si{align-self:center}
.ls .sb{display:flex;flex-wrap:wrap;column-gap:${itemGap}px;align-items:baseline}.ls .sh{display:flex;align-items:center;column-gap:${colGap}px}`;
    return { css, body: `<div class="ls" data-full-width style="width:${W}px">${head}${rows.join('')}</div>` };
  },
};
