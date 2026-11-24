'use strict';
// 時間の順、手順(日数を持つ時点を、時間の線の上の点で見せる)。見本: examples/timeline-steps.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'timeline-steps',
  when: 'いつ、誰が、何をするかの順を言う。時点が、日数を持つ(基準の時点から何日前か、何日後か)。時点は 3 つまで。行を持つすべての点が同じ名前の行を持つときは、行の見出しの列を置く。原則「同じ話の要素を近くに置く」に合わせ、点ごとの文字を、点の左端にそろえる。この組み方は、原則「図に本文領域の広さを使わせる」のうち、図の高さの割合の下限の対象の外とする(本文領域の幅の全体は使う)。時間の線の図は、時点の前後と日数を、横の位置と長さだけで見せ、図の高さは、点ごとの文字の行の数で決まる。高さを下限まで伸ばすには、点ごとの文字の行と行の間を広げることになり、原則「同じ話の要素を近くに置く」の、まとまりの中の間がまとまりとまとまりの間より狭い関係が崩れるからである。',
  parts: ['時間の線', '点', '行の見出し', '付録の番号'],
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
    const { V, W, e, r2, span } = P;
    const c = data.content;
    const hdW = V('行の見出しの列の幅');
    const origin = hdW + V('間隔.行の見出しの列と図');
    const pts = c.points.map((p) => ({ ...p, d: V(p.time === c.focus ? '見てほしい点の直径' : '点の直径'), days: Number(p.days) }));
    const first = pts[0], last = pts[pts.length - 1];
    const span_d = last.days - first.days;
    // 1 日の長さ: 最後の点の文字が本文領域の右端に入る範囲で、値「時間の線の 1 日の長さの上限」以下のいちばん大きい整数。
    const lastW = Math.max(P.roleW('時点の名前', last.time), last.heading ? P.roleW('点の見出し', last.heading) : 0, ...(last.rows || []).map((r) => P.roleW('図の中の説明', r)));
    const cx0 = origin + first.d / 2;
    let day = V('時間の線の 1 日の長さの上限');
    if (span_d > 0) day = Math.min(day, Math.floor((W - lastW - cx0 + last.d / 2) / span_d));
    pts.forEach((p) => { p.cx = cx0 + (p.days - first.days) * day; p.left = p.cx - p.d / 2; });
    const tlH = V('時間の線の点の行の高さ');
    const tl = P.timeline(pts.map((p) => ({ left: p.left, d: p.d, emphasis: p.time === c.focus })), W)
      .replace('<svg ', '<svg style="left:0;top:0" ');
    const tvH = V('文字の行の高さ.時点の名前'), stH = V('文字の行の高さ.点の見出し'), rH = V('文字の行の高さ.図の中の説明');
    const top0 = tlH + V('間隔.時間の線と点の文字'); // 時点の名前の上端
    const toHead = V('間隔.時点の名前と点の見出し'), toRow1 = V('間隔.点の見出しと最初の行'), rowGap = V('間隔.点の文字の行と行');
    const stTop = top0 + tvH + toHead;
    const r1Top = stTop + stH + toRow1;
    const nRows = c.rowHeaders.rows.length;
    const total = r1Top + nRows * rH + (nRows - 1) * rowGap;
    const lbH = V('文字の行の高さ.行の見出し');
    let html = tl;
    html += `<div class="t-行の見出し" data-part="行の見出し" data-role="${V('文字の種類.行の見出し')}" style="left:0;top:${top0 + (tvH - lbH) / 2}px">${e(c.rowHeaders.time)}</div>`;
    c.rowHeaders.rows.forEach((r, i) => {
      html += `<div class="t-行の見出し" data-part="行の見出し" data-role="${V('文字の種類.行の見出し')}" style="left:0;top:${r1Top + i * (rH + rowGap)}px">${e(r)}</div>`;
    });
    for (const p of pts) {
      html += `<div style="left:${r2(p.left)}px;top:${top0}px">` + span('時点の名前', p.time);
      if (p.heading) html += span('点の見出し', p.heading, `style="margin-top:${toHead}px"`);
      (p.rows || []).forEach((r, i) => { html += span('図の中の説明', r, `style="margin-top:${i === 0 ? toRow1 : rowGap}px"`); });
      html += '</div>';
    }
    return { css: '', body: `<div class="fg" style="width:${W}px;height:${total}px">${html}</div>` };
  },
};
