'use strict';
// 時間の順、手順(日数を持つ時点を、時間の線の上の点で見せる)。見本: examples/timeline-steps.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'timeline-steps',
  when: 'いつ、誰が、何をするかの順を言う。時点が、日数を持つ(基準の時点から何日前か、何日後か)。時点は 3 つまで。行を持つすべての点が同じ名前の行を持つときは、行の見出しの列を置く。点の見出しの行は、行の見出しを持たない(部品「行の見出し」)。原則「同じ話の要素を近くに置く」に合わせ、点ごとの文字を、点の左端にそろえる。',
  parts: ['時間の線', '点', '行の見出し'],
  schema: {
    rowHeaders: {
      type: 'object', required: true,
      fields: { time: { type: 'text', required: true }, rows: { type: 'list', required: true, item: { type: 'text' } } },
    },
    points: {
      type: 'list', required: true, maxItems: '時間の順と手順の点の数の上限',
      item: {
        type: 'object',
        fields: {
          time: { type: 'text', required: true },
          days: { type: 'text', required: true },
          heading: { type: 'text' },
          rows: { type: 'list', item: { type: 'text' } },
        },
      },
    },
    focus: { type: 'text', required: true },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, W, S, e, r2, span } = P;
    const headGap = V('間隔.点の見出しと行'), rowGap = V('間隔.時間の順の行と行');
    const c = data.content;
    const hdW = V('行の見出しの列の幅');
    const origin = hdW + V('行の見出しの列と中身の間');
    const pts = c.points.map((p) => ({ ...p, d: V(p.time === c.focus ? '見てほしい点の直径' : '点の直径'), days: Number(p.days) }));
    const first = pts[0], last = pts[pts.length - 1];
    const textW = (p) => Math.max(P.roleW('時点の名前', p.time), p.heading ? P.roleW('点の見出し', p.heading) : 0, ...(p.rows || []).map((r) => P.roleW('図の中の説明', r)));
    // 1 日の長さ: 隣り合う点の文字の列と列の間が、下限(64px)以上になる、いちばん小さい整数。
    const gapMin = V('時間の線の文字の列と列の間の下限');
    let day = 1;
    for (let i = 0; i + 1 < pts.length; i++) {
      const dd = pts[i + 1].days - pts[i].days;
      if (dd > 0) day = Math.max(day, Math.ceil((textW(pts[i]) + gapMin - pts[i].d / 2 + pts[i + 1].d / 2) / dd - 1e-9));
    }
    const cx0 = origin + first.d / 2;
    // 最後の点の文字が本文領域の右端に入る範囲を超えないようにする(超えるときは、文字の列と列の間が下限より狭くなる)。
    const spanD = last.days - first.days;
    if (spanD > 0) {
      const lastWMax = Math.max(P.roleWMax('時点の名前', last.time), last.heading ? P.roleWMax('点の見出し', last.heading) : 0, ...(last.rows || []).map((r) => P.roleWMax('図の中の説明', r)));
      day = Math.max(1, Math.min(day, Math.floor((W - lastWMax - cx0 + last.d / 2) / spanD)));
    }
    pts.forEach((p) => { p.cx = cx0 + (p.days - first.days) * day; p.left = p.cx - p.d / 2; });
    const tlH = V('時間の線の点の行の高さ');
    const tl = P.timeline(pts.map((p) => ({ left: p.left, d: p.d, red: p.time === c.focus, emphasis: p.time === c.focus })), W)
      .replace('<svg ', '<svg style="left:0;top:0" ');
    const tvH = V('文字の行の高さ.時点の名前'), stH = V('文字の行の高さ.点の見出し'), rH = V('文字の行の高さ.図の中の説明');
    const top0 = tlH + V('間隔.時間の線と点の文字');                       // 時点の名前の上端
    const stTop = top0 + tvH + S;
    const r1Top = stTop + stH + headGap;
    const nRows = c.rowHeaders.rows.length;
    const total = r1Top + nRows * rH + (nRows - 1) * rowGap;
    const lbH = V('文字の行の高さ.行の見出し');
    let html = tl;
    html += `<div ${P.T('行の見出し')} data-part="行の見出し" style="left:0;top:${top0 + (tvH - lbH) / 2}px">${e(c.rowHeaders.time)}</div>`;
    c.rowHeaders.rows.forEach((r, i) => {
      html += `<div ${P.T('行の見出し')} data-part="行の見出し" style="left:0;top:${r1Top + i * (rH + rowGap)}px">${e(r)}</div>`;
    });
    for (const p of pts) {
      html += `<div style="left:${r2(p.left)}px;top:${top0}px">` + span('時点の名前', p.time);
      if (p.heading) html += span('点の見出し', p.heading, `style="margin-top:${S}px"`);
      (p.rows || []).forEach((r, k) => { html += span('図の中の説明', r, `style="margin-top:${k ? rowGap : headGap}px"`); });
      html += '</div>';
    }
    return { css: '', body: `<div class="fg" style="width:${W}px;height:${total}px">${html}</div>` };
  },
};
