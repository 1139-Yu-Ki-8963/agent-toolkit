'use strict';
// 工程ごとに減って 0% で閉じる量の逆三角形と、三角形の外の量を減らすもの。見本: examples/remaining-triangle.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'remaining-triangle',
  when: '工程を順に進むごとに、ある種類の量(割合)が減り、最後の工程のあとに 0% になる。その種類の外にある別の種類の量を、工程の外の 1 つのものが減らす。工程は 5 つまで。工程で減る種類の量を、上の辺を最初の量、下の頂点を 0% とする逆三角形にし、工程ごとの層を、同じ高さで、すき間なく上から下へ積む(部品「残りの三角形」)。層の境の幅は、その工程のあとに残る量に比例させ、境の右端に残る量を置き、層の左に工程の名前を置く。工程の外の種類の量は、三角形の右に、減らす前と減らしたあとの 2 本の帯(部品「外の帯」)にし、2 本を下向きの矢印でつなぎ、矢印に、減らすものの名前を添える。最後の工程のあとの 0% を強調の色にする。量が作る人の置いた値のときは、三角形と帯を破線の枠(部品「置いた値」)で描き、ラベルに置いた値であることを書く。最後に 0% にならない量は、この型でなく、量の推移の型にする。',
  parts: ['ラベル', '残りの三角形', '外の帯', '置いた値', '矢印'],
  schema: {
    label: { type: 'text', required: true },
    start: { type: 'object', required: true, fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true } } },
    steps: {
      type: 'list', required: true, maxItems: '残りの三角形の層の数の上限',
      item: { type: 'object', fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true } } },
    },
    outside: {
      type: 'object', required: true,
      fields: {
        name: { type: 'text', required: true },
        kind: { type: 'text', required: true },
        before: { type: 'quantity', required: true },
        after: { type: 'quantity', required: true },
      },
    },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, e, r2, px, roleW } = P;
    const c = data.content;
    const n = c.steps.length;
    if (c.steps[n - 1].value.n !== 0) throw new Error('最後の工程のあとの量が 0 でない。この型は、0% で閉じる量に使う');
    const lineH = V('文字の行の高さ.本文'), valH = V('文字の行の高さ.棒の値');
    const labH = V('文字の行の高さ.ラベル') + V('間隔.名前と、その中身');
    const gapX = V('間隔.まとまりとまとまり'), near = V('間隔.名前と、その中身');
    const TW = V('残りの三角形の上の辺の幅'), LH = V('残りの三角形の層の高さ');
    const per = TW / c.start.value.n;                        // 値でない: 1% あたりの幅(三角形と外の帯で同じ)
    const nameCol = Math.max(...c.steps.map((s) => roleW('本文', s.name)));
    const tx = nameCol + gapX, cx = tx + TW / 2;            // 値でない: 三角形の左端と、左右の真ん中
    const valW = Math.max(...[c.start.value, ...c.steps.map((s) => s.value)].map((q) => [...h.quantity(q)].length)) * V('太字の欧文の字の幅の比') * P.roleSize('棒の値');   // 値でない: 字の数に、1 字の幅の見積もりを掛ける
    const y0 = labH + lineH + near;                         // 値でない: 種類の名前の行の 8px 下に、上の辺を置く
    const yOf = (i) => y0 + LH * i;
    const wOf = (q) => q.n * per;
    const pts = [c.start.value, ...c.steps.map((s) => s.value)];
    const lw = V('置いた値の破線の線の太さ'), dash = `${V('置いた値の破線の線の長さ')} ${V('置いた値の破線の切れ目')}`;
    const sep = V('残りの三角形の層の境の線の太さ');
    let svg = '', html = '';
    // 層。境の幅は、その時点に残る量に比例する。層と層の境は、地の色の線で分ける。
    c.steps.forEach((s, i) => {
      const a = wOf(pts[i]) / 2, b = wOf(pts[i + 1]) / 2;   // 値でない: 幅の半分
      svg += `<path data-part="残りの三角形" d="M${r2(cx - a)} ${r2(yOf(i))}H${r2(cx + a)}L${r2(cx + b)} ${r2(yOf(i + 1))}H${r2(cx - b)}Z" style="fill:var(--line);stroke:var(--bg)" stroke-width="${sep}"/>`;
      html += `<div ${T('本文')} style="left:0;top:${px(yOf(i) + (LH - lineH) / 2)}">${e(s.name)}</div>`;   // 値でない: 層の上下の真ん中
    });
    // 置いた値の枠。三角形の外形を、破線でなぞる。
    const outline = pts.map((q, i) => `${r2(cx + wOf(q) / 2)} ${r2(yOf(i))}`).join('L') + 'L' + pts.slice().reverse().map((q, j) => `${r2(cx - wOf(q) / 2)} ${r2(yOf(n - j))}`).join('L');   // 値でない: 右の辺を下り、左の辺を上る
    svg += `<path data-part="置いた値" d="M${outline}Z" fill="none" style="stroke:var(--ink)" stroke-width="${lw}" stroke-dasharray="${dash}"/>`;
    // 種類の名前と、境ごとの残る量。量は、境の右端の 8px 右に、境の高さを行の真ん中にして置く。
    html += `<div ${T('本文')} style="left:${px(tx)};top:${px(labH)}">${e(c.start.name)}</div>`;
    pts.forEach((q, i) => {
      const last = i === n;
      // 量の字の箱の上端の高さで、上の層の右の辺がどこを通るかを求め、境の右端とその点の右のほうから 8px 右に置く(上の層の辺に字が掛からないように)。
      const top = yOf(i) - valH / 2;   // 値でない: 境の高さを行の真ん中に
      const edge = i === 0 ? wOf(q) / 2 : wOf(pts[i]) / 2 + (wOf(pts[i - 1]) / 2 - wOf(pts[i]) / 2) * (yOf(i) - top) / LH;   // 値でない: 上の層の辺の、字の箱の上端の高さでの位置
      html += `<div ${T('棒の値', last ? 'em' : '')}${last ? ' data-emphasis' : ''} style="left:${px(cx + Math.max(wOf(q) / 2, edge) + near)};top:${px(top)}">${e(h.quantity(q))}</div>`;   // 値でない: 境の高さを行の真ん中に
    });
    // 外の帯。三角形の量の列の右に、減らす前と減らしたあとの 2 本を、下向きの矢印でつないで置き、下端を三角形の下の頂点にそろえる。
    const ox = tx + TW + near + valW + gapX;
    const bh = V('外の帯の高さ'), ah = LH;                   // 矢印の長さは、層の高さと同じ
    const yb2 = yOf(n) - bh / 2, ya = yb2 - ah, yb1 = ya - bh, yk = yb1 - near - lineH;   // 値でない: 下から上へ積む
    const bar = (q, y) => `<rect data-part="外の帯" x="${r2(ox)}" y="${r2(y)}" width="${r2(wOf(q))}" height="${bh}" style="fill:var(--sub)"/><rect data-part="置いた値" x="${r2(ox + lw / 2)}" y="${r2(y + lw / 2)}" width="${r2(wOf(q) - lw)}" height="${bh - lw}" fill="none" style="stroke:var(--ink)" stroke-width="${lw}" stroke-dasharray="${dash}"/>`;   // 値でない: 線の内側に、太さの半分を引く
    svg += bar(c.outside.before, yb1) + bar(c.outside.after, yb2);
    html += `<div ${T('本文')} style="left:${px(ox)};top:${px(yk)}">${e(c.outside.kind)}</div>`;
    [[c.outside.before, yb1], [c.outside.after, yb2]].forEach(([q, y]) => {
      html += `<div ${T('棒の値')} style="left:${px(ox + wOf(q) + near)};top:${px(y + (bh - valH) / 2)}">${e(h.quantity(q))}</div>`;   // 値でない: 帯の上下の真ん中
    });
    const lw2 = V('矢印の線の太さ'), depth = V('矢じりの奥行き'), hb = V('矢じりの底辺') / 2;   // 値でない: 底辺の半分
    const ax = ox + wOf(c.outside.after) / 2, a0 = ya + near, a1 = ya + ah - near;   // 値でない: 減らしたあとの帯の左右の真ん中
    svg += `<g data-part="矢印"><path d="M${r2(ax)} ${r2(a0)}V${r2(a1 - depth)}" fill="none" style="stroke:var(--ink)" stroke-width="${lw2}"/><path d="M${r2(ax - hb)} ${r2(a1 - depth)}L${r2(ax)} ${r2(a1)}L${r2(ax + hb)} ${r2(a1 - depth)}Z" style="fill:var(--ink)"/></g>`;
    html += `<div ${T('矢印に添える名前')} style="left:${px(ax + hb + near)};top:${px(ya + (ah - lineH) / 2)}">${e(c.outside.name)}</div>`;   // 値でない: 矢印の上下の真ん中
    const figH = yOf(n) + valH / 2;                          // 値でない: 0% の行の下端まで
    const css = `.rt{position:relative}
.rt>[data-role]{position:absolute;white-space:nowrap}
.rt>svg{position:absolute;left:0;top:0}
.rt .em{color:var(--blue)}`;
    const body = `<div class="rt" style="width:${W}px;height:${px(figH)}">` + P.label(c.label, null, 'position:absolute;left:0;top:0') +
      `<svg data-full-width width="${W}" height="${r2(figH)}" viewBox="0 0 ${W} ${r2(figH)}" aria-hidden="true">${svg}</svg>${html}</div>`;
    return { css, body };
  },
};
