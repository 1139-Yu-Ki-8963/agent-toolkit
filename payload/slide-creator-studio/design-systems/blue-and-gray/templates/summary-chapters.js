'use strict';
// まとめ(章の名前と結論の一文を並べ、量が減る章には、量の流れの帯を添える)。見本: examples/summary-chapters.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'summary-chapters',
  sectionFixed: 'まとめ',
  fullWidth: false,
  fullWidthWhy: 'まとめは、役目の決まったスライドで、原則「図に本文領域の広さを使わせる」の対象の外である。章の名前と結論の一文の行を、中身の幅で、本文領域の上下の中央に置く。',
  when: '章ごとの結論を並べるまとめ。原則「まとめに、中身のスライドの結論だけを持たせる」に合わせ、中身のスライドの順に、左の列に章の名前、右の列に、その章のスライドの結論の一文を、そのまま並べる。同じ章の 2 枚目から後の結論は、章の名前を置かずに、狭い間で続ける。量が工程ごとに減る章の結論には、その結論の一文の下に、量の流れの帯(部品「量の流れの帯」)を添え、最初の量から、工程を経たあとの量を、左から右へ、工程の名前を添えた矢印でつなぎ、最後の量を強調の色にして、量と流れを形で見せる。現状、原因、提案、効果を 1 枚で言うまとめは、この型でなく、summary にする。',
  parts: ['まとめの章と結論', '量の流れの帯', 'ラベル'],
  schema: {
    items: {
      type: 'list', required: true, maxItems: 'まとめに並べる結論の数の上限',
      item: {
        type: 'object',
        fields: {
          chapter: { type: 'text', required: true },
          conclusion: { type: 'text', required: true },
          flows: {
            type: 'list', maxItems: '量の流れの帯の数の上限',
            item: { type: 'object',
            fields: {
              focus: { type: 'text' },
              label: { type: 'text', required: true },
              start: { type: 'quantity', required: true },
              steps: { type: 'list', required: true, maxItems: '量の流れの帯の工程の数の上限', item: { type: 'object', fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true } } } },
            } },
          },
        },
      },
    },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, e, r2, roleW } = P;
    const c = data.content;
    // 矢印の長さは、下に置く工程の名前の字の幅と、値「量の流れの帯の矢印の長さ」の大きいほう。
    const arrow = (name) => {
      const aw = Math.max(V('量の流れの帯の矢印の長さ'), roleW('ラベル', name));
      const lw = V('矢印の線の太さ'), depth = V('矢じりの奥行き'), half = V('矢じりの底辺') / 2, hgt = V('文字の行の高さ.棒の値'), cy = hgt / 2;   // 値でない: 底辺の半分と行の中央
      return `<div class="fa"><svg width="${aw}" height="${hgt}" viewBox="0 0 ${aw} ${hgt}" aria-hidden="true"><path d="M0 ${cy}H${aw - depth}" fill="none" style="stroke:var(--ink)" stroke-width="${lw}"/><path d="M${aw - depth} ${r2(cy - half)}L${aw} ${cy}L${aw - depth} ${r2(cy + half)}Z" style="fill:var(--ink)"/></svg><span ${T('ラベル')}>${e(name)}</span></div>`;
    };
    const flowHtml = (f) => {
      const last = f.steps.length - 1;
      const val = (q, em) => `<span ${T('棒の値', em ? 'fl' : '')}${em ? ' data-emphasis' : ''}>${e(h.quantity(q))}</span>`;
      const row = val(f.start, false) + f.steps.map((s, i) => arrow(s.name) + val(s.value, f.focus === 'last' && i === last)).join('');
      return `<div class="fw" data-part="量の流れの帯">${P.label(f.label)}<div class="fr">${row}</div></div>`;
    };
    // 行の上の間は、章が変わる行で値「間隔.まとまりとまとまり」、同じ章の 2 行目から後で値「間隔.同じまとまりの部品と部品」とする。
    const cells = c.items.map((it, i) => {
      const same = i > 0 && c.items[i - 1].chapter === it.chapter;
      const cls = i === 0 ? '' : (same ? 'ss' : 'ns');
      return `<div ${T('まとめの資料の章の名前', [cls, same ? 'em' : ''].filter(Boolean).join(' '))}>${same ? '' : e(it.chapter)}</div><div class="${['sw', cls].filter(Boolean).join(' ')}"><div ${T('まとめに並べた結論の一文', 'sc')}>${e(it.conclusion)}</div>${(it.flows || []).map(flowHtml).join('')}</div>`;
    }).join('\n');
    const css = `.smc{display:grid;grid-template-columns:auto 1fr;column-gap:${V('間隔.行の見出しの列と図')}px;align-items:baseline}
.smc .ns{margin-top:${V('間隔.まとまりとまとまり')}px}
.smc .ss{margin-top:${V('間隔.同じまとまりの部品と部品')}px}
.smc .em::before{content:"\\200b"}
.smc .sc{white-space:normal}
.smc .fw{margin-top:${V('間隔.同じまとまりの部品と部品')}px}
.smc .fr{display:flex;align-items:flex-start;column-gap:${V('間隔.名前と、その中身')}px;margin-top:${V('間隔.名前と、その中身')}px}
.smc .fa{display:flex;flex-direction:column;align-items:center}
.smc .fl{color:var(--blue)}`;
    return { css, body: `<div class="smc" data-part="まとめの章と結論">\n${cells}\n</div>` };
  },
};
