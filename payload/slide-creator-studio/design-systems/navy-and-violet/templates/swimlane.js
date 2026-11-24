'use strict';
// スイムレーン(役割ごとの帯に、その役割が行う手順のカードを置き、手順の順を矢印でつなぐ)。見本: examples/swimlane.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'swimlane',
  when: '誰が、どの順に、何を担うかを言う(役割 2〜3 つ、手順 2〜4 つ)。役割ごとの横の帯に、その役割が行う手順のカードを、手順の順に左から右へ 1 列に 1 つずつ置き、矢印でつなぐ。結論の一文が 1 つの手順を指すときは、その手順の名前を focus にして、カードを紫にする。役割が 1 つだけのときと、時点が日数を持つときは、timeline-steps を使う。原則「矢印の線の折れを絞る」に合わせ、別の帯へ移る矢印は、1 回の折れとする。',
  parts: ['役割の帯', '行の見出し', '役割ごとの手順のカード', '主役のカード', '矢印'],
  schema: {
    lanes: { type: 'list', required: true, maxItems: '役割の数の上限', item: { type: 'text', maxChars: '役割の名前の字数の上限' } },
    steps: {
      type: 'list', required: true, maxItems: '役割ごとの手順の数の上限',
      item: {
        type: 'object',
        fields: {
          lane: { type: 'text', required: true },
          name: { type: 'text', required: true, maxChars: '役割ごとの手順の名前の字数の上限' },
          note: { type: 'text', maxChars: '役割ごとの手順の説明の字数の上限' },
        },
      },
    },
    focus: { type: 'text' },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, S, e, px, r2 } = P;
    const B = V('間隔.まとまりとまとまり'); // まとまりとまとまりの間
    const c = data.content;
    const nL = c.lanes.length, m = c.steps.length;
    if (m < 2) throw new Error('steps は、2 つ以上');
    for (const s of c.steps) if (!c.lanes.includes(s.lane)) throw new Error(`steps の lane が lanes にない: ${s.lane}`);
    if (c.focus && !c.steps.some((s) => s.name === c.focus)) throw new Error(`focus が steps の name にない: ${c.focus}`);
    const hdW = V('行の見出しの列の幅'), x0 = hdW + B, figW = W - x0;
    const laneH = V('役割の帯の高さ'), laneGap = V('役割の帯と帯の間'), pad = V('カードの余白');
    const cgap = V('役割ごとの手順のカードの間'), cardH = V('役割ごとの手順のカードの高さ');
    const cardW = (figW - pad * 2 - (m - 1) * cgap) / m;
    const lbH = V('文字の行の高さ.行の見出し');
    const laneTop = (k) => k * (laneH + laneGap);
    const total = nL * laneH + (nL - 1) * laneGap;
    let html = '';
    c.lanes.forEach((name, k) => {
      html += `<div data-part="役割の帯" style="left:${x0}px;top:${laneTop(k)}px;width:${px(figW)};height:${laneH}px;background:var(--tint);border-radius:${V('カードの角丸')}px"></div>`;
      html += `<div ${T('行の見出し')} data-part="行の見出し" style="left:0;top:${r2(laneTop(k) + (laneH - lbH) / 2)}px">${e(name)}</div>`;
    });
    const box = c.steps.map((s, i) => {
      const k = c.lanes.indexOf(s.lane);
      const left = x0 + pad + i * (cardW + cgap), top = laneTop(k) + (laneH - cardH) / 2;
      return { left, top, right: left + cardW, bottom: top + cardH, cx: left + cardW / 2, cy: top + cardH / 2 };
    });
    c.steps.forEach((s, i) => {
      const f = s.name === c.focus, b = box[i];
      html += `<div ${f ? 'data-part="主役のカード"' : 'data-part="役割ごとの手順のカード"'}${f ? ' data-emphasis' : ''} class="wc${f ? ' mn' : ''}" style="left:${r2(b.left)}px;top:${r2(b.top)}px;width:${px(cardW)};height:${cardH}px;padding:0 ${pad}px">` +
        `<div ${T('図の中のカードの名前')}>${e(s.name)}</div>` + (s.note ? `<div ${T('図の中の説明')} style="margin-top:${S}px">${e(s.note)}</div>` : '') + '</div>';
    });
    // 矢印。同じ帯の次の手順へは、まっすぐな右向き。別の帯の次の手順へは、右へ出て、次のカードの上か下へ 1 回折れる。
    const depth = V('矢じりの奥行き'), half = V('矢じりの底辺') / 2, lw = V('矢印の線の太さ');
    let paths = '';
    for (let i = 0; i < m - 1; i++) {
      const a = box[i], b = box[i + 1];
      if (Math.abs(a.cy - b.cy) < 0.5) paths += P.rightArrowShapes(a.right + S, b.left - S, a.cy, 'var(--ink)');
      else {
        const down = b.cy > a.cy;
        const tipY = down ? b.top - S : b.bottom + S, baseY = down ? tipY - depth : tipY + depth;
        paths += `<path d="M${r2(a.right + S)} ${r2(a.cy)}H${r2(b.cx)}V${r2(baseY)}" fill="none" style="stroke:var(--ink)" stroke-width="${lw}"/>` +
          `<path d="M${r2(b.cx - half)} ${r2(baseY)}L${r2(b.cx)} ${r2(tipY)}L${r2(b.cx + half)} ${r2(baseY)}Z" style="fill:var(--ink)"/>`;
      }
    }
    html += `<svg data-part="矢印" style="left:0;top:0" width="${W}" height="${total}" viewBox="0 0 ${W} ${total}" aria-hidden="true">${paths}</svg>`;
    const css = `.wc{box-sizing:border-box;background:var(--bg);border-radius:${V('カードの角丸')}px;display:flex;flex-direction:column;justify-content:center}.wc.mn{background:var(--accent)}.wc.mn [data-role]{color:var(--bg)}`;
    return { css, body: `<div class="fg" data-full-width style="width:${W}px;height:${total}px">${html}</div>` };
  },
};
