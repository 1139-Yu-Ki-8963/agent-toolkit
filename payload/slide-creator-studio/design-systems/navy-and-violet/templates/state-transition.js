'use strict';
// 状態遷移図(画面や段階の 1 つずつを、縦に長いカードで左から右へ並べ、移り方を、名前を添えた矢印で示す)。見本: examples/state-transition.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'state-transition',
  when: '画面や段階(2〜4 つ)が、どの順に、何をすると移るかを言う。状態のカードを左から右へ並べ、隣へ進む移り方を、名前を添えた右向きの矢印で示す。前の状態へ戻る移り方が 1 つあるときは、カードの下を通る戻る矢印で示す。結論の一文が 1 つの状態か、戻り方を指すときは、その状態の名前か、戻る矢印の名前を focus にして、紫にする。手順ごとに絵があるときは steps-illustrated を、時点が日数を持つときは timeline-steps を使う。原則「矢印の線の折れを絞る」に合わせ、進む矢印はまっすぐ、戻る矢印は 2 回の折れとする。',
  parts: ['状態のカード', '主役のカード', '矢印', '矢印に添える名前', '戻る矢印'],
  schema: {
    states: {
      type: 'list', required: true, maxItems: '状態の数の上限',
      item: {
        type: 'object',
        fields: {
          name: { type: 'text', required: true, maxChars: '状態の名前の字数の上限' },
          note: { type: 'text', maxChars: '状態の説明の字数の上限' },
          next: { type: 'text', maxChars: '状態の矢印に添える名前の字数の上限' },
        },
      },
    },
    back: {
      type: 'object',
      fields: {
        from: { type: 'text', required: true },
        to: { type: 'text', required: true },
        label: { type: 'text', required: true, maxChars: '状態の矢印に添える名前の字数の上限' },
      },
    },
    focus: { type: 'text' },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, S, e, px, r2 } = P;
    const c = data.content;
    const n = c.states.length;
    if (n < 2) throw new Error('states は、2 つ以上');
    const cardW = V('状態のカードの幅'), cardH = V('状態のカードの高さ'), pad = V('カードの余白');
    const gap = (W - n * cardW) / (n - 1);
    const left = (i) => i * (cardW + gap);
    const names = c.states.map((s) => s.name);
    if (c.focus && !names.includes(c.focus) && !(c.back && c.back.label === c.focus)) throw new Error(`focus が、states の name にも back の label にもない: ${c.focus}`);
    const aH = V('矢じりの底辺') + V('矢印の図の上下の余り'), lbH = V('文字の行の高さ.矢印に添える名前');
    const depth = V('矢じりの奥行き'), half = V('矢じりの底辺') / 2, lw = V('矢印の線の太さ');
    let html = '';
    c.states.forEach((s, i) => {
      const f = s.name === c.focus;
      html += `<div ${f ? 'data-part="主役のカード"' : 'data-part="状態のカード"'}${f ? ' data-emphasis' : ''} class="tc${f ? ' mn' : ''}" style="left:${r2(left(i))}px;top:0;width:${px(cardW)};height:${cardH}px;padding:${pad}px">` +
        `<div ${T('図の中のカードの名前')}>${e(s.name)}</div>` + (s.note ? `<div ${T('図の中の説明')} style="margin-top:${S}px">${e(s.note)}</div>` : '') + '</div>';
      if (i < n - 1) {
        const x = left(i) + cardW;
        if (!s.next) throw new Error(`states[${i}] が、次の状態への移り方の名前(next)を持たない`);
        html += `<div ${T('矢印に添える名前')} data-part="矢印に添える名前" style="left:${r2(x)}px;top:${r2(cardH / 2 - aH / 2 - S - lbH)}px;width:${px(gap)};text-align:center">${e(s.next)}</div>`;
        html += `<svg data-part="矢印" style="left:${r2(x)}px;top:${r2(cardH / 2 - aH / 2)}px" width="${r2(gap)}" height="${aH}" viewBox="0 0 ${r2(gap)} ${aH}" aria-hidden="true">${P.rightArrowShapes(S, gap - S, aH / 2, 'var(--ink)')}</svg>`;
      }
    });
    let total = cardH;
    if (c.back) {
      const a = names.indexOf(c.back.from), b = names.indexOf(c.back.to);
      if (a < 0 || b < 0 || b >= a) throw new Error('back の from は、to より後ろの状態の名前にする');
      const drop = V('戻る矢印の下への出の長さ');
      const xa = left(a) + cardW / 2, xb = left(b) + cardW / 2;
      const f = c.back.label === c.focus;
      const color = f ? 'var(--accent)' : 'var(--ink)';
      const m = half + V('戻る矢印の図の左右の余り');                       // 図の左右の余り(矢じりの幅の半分)
      const w = xa - xb + m * 2, hh = drop + lw / 2;
      html += `<svg data-part="戻る矢印"${f ? ' data-emphasis' : ''} style="left:${r2(xb - m)}px;top:${cardH}px" width="${r2(w)}" height="${r2(hh)}" viewBox="0 0 ${r2(w)} ${r2(hh)}" aria-hidden="true">` +
        `<path d="M${r2(w - m)} ${S}V${drop}H${m}V${S + depth}" fill="none" style="stroke:${color}" stroke-width="${lw}"/>` +
        `<path d="M${m - half} ${S + depth}L${m} ${S}L${m + half} ${S + depth}Z" style="fill:${color}"/></svg>`;
      html += `<div ${T('矢印に添える名前')} data-part="矢印に添える名前" style="left:${r2(xb)}px;top:${r2(cardH + drop + S)}px;width:${px(xa - xb)};text-align:center${f ? ';color:var(--accent)' : ''}">${e(c.back.label)}</div>`;
      total = cardH + drop + S + lbH;
    }
    const css = `.tc{box-sizing:border-box;background:var(--tint);border-radius:${V('カードの角丸')}px}.tc.mn{background:var(--accent)}.tc.mn [data-role]{color:var(--bg)}`;
    return { css, body: `<div class="fg" data-full-width style="width:${W}px;height:${r2(total)}px">${html}</div>` };
  },
};
