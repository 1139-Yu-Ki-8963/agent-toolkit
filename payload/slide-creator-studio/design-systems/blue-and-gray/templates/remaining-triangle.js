'use strict';
// 順に重ねる段階ごとに減って 0% で閉じる量の逆三角形と、三角形の外の種類を見つけ出すもの。見本: examples/remaining-triangle.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'remaining-triangle',
  when: '順に重ねる段階(工程や、確かめ方の種類)ごとに、ある種類の量(割合)が減り、最後の段階のあとに 0% になる。その種類の外にある別の種類を、段階の外の 1 つのものが見つけ出す。段階は 5 つまで。段階で減る種類の量を、上の辺を最初の量、下の頂点を 0% とする、辺のまっすぐな逆三角形にする(部品「残りの三角形」)。層の高さを、その段階で減った量に比例させ、層の境の幅を、その段階のあとに残る量に比例させる。段階の名前は三角形の左の列に、層の上下の真ん中の真横に置き、残る量は三角形の右の列に、境の真横に置いて、それぞれ水平の細い線(部品「引き出し線」)でつなぐ。上の辺の量だけは、線を引かずに上の辺の真横に置く。続けて並ぶ段階が 1 つのまとまりの中の分け方のときは、その段階の名前の上の行に、まとまりの名前を置き、その段階の名前の左に、段階をまたぐ括り(部品「括り」)を置く。量の列の右に、外の種類の名前だけを持つ、線で囲んだ入れ物(部品「外のエリア」)を、下端を三角形の下の頂点にそろえて置き、その上に、見つけ出すもののカード(部品「見つけ出すもののカード」)を、上端を三角形の上の辺にそろえて置いて、カードから入れ物へ、働きの名前を添えた下向きの矢印を引く。最後の段階のあとの 0% を強調の色にする。どの層も、名前と量の行の高さより厚くなる量でないと、名前と量を真横に置けないので、この型は止まる。最後に 0% にならない量は、この型でなく、量の推移の型にする。',
  parts: ['ラベル', '残りの三角形', '引き出し線', '括り', '置いた値', '外のエリア', '見つけ出すもののカード', '矢印'],
  schema: {
    label: { type: 'text' },
    start: { type: 'object', required: true, fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true } } },
    steps: {
      type: 'list', required: true, maxItems: '残りの三角形の層の数の上限',
      item: { type: 'object', fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true }, group: { type: 'text' } } },
    },
    outside: {
      type: 'object', required: true,
      fields: {
        kind: { type: 'text', required: true },
        finder: { type: 'text', required: true },
        verb: { type: 'text', required: true },
      },
    },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, e, r2, px, roleW } = P;
    const c = data.content;
    const n = c.steps.length;
    if (c.steps[n - 1].value.n !== 0) throw new Error('最後の段階のあとの量が 0 でない。この型は、0% で閉じる量に使う');
    const lineH = V('文字の行の高さ.本文'), valH = V('文字の行の高さ.棒の値'), labLH = V('文字の行の高さ.ラベル');
    const labH = c.label ? labLH + V('間隔.名前と、その中身') : 0;   // 値でない: ラベルを持たないときは 0
    const gapX = V('間隔.まとまりとまとまり'), near = V('間隔.名前と、その中身'), pad = V('カードの余白');
    const TW = V('残りの三角形の上の辺の幅'), TH = V('残りの三角形の高さ'), AW = V('外のエリアの幅');
    const lw = V('置いた値の破線の線の太さ'), dash = `${V('置いた値の破線の線の長さ')} ${V('置いた値の破線の切れ目')}`;
    const sep = V('残りの三角形の層の境の線の太さ'), thin = V('引き出し線の太さ');
    const bw = V('括りの線の太さ'), arm = V('残りの三角形の括りの腕の長さ');
    const start = c.start.value.n;
    const pts = [c.start.value, ...c.steps.map((s) => s.value)];
    // どの層も、名前と量の行の高さより厚くする。薄い層は、名前と量を真横に置けない。
    const rowH = Math.max(lineH, valH);
    c.steps.forEach((s, i) => {
      if (TH * (pts[i].n - pts[i + 1].n) / start < rowH * s.name.split('\n').length) throw new Error(`層「${s.name}」が行の高さ(${rowH}px)より薄い。どの段階も、減る量を最初の量の ${Math.ceil(rowH / TH * 100)}% 以上にする`);   // 値でない: エラーの文で、減る量の下限を % で言う
    });
    // まとまり: 続けて同じ group を持つ段階の組。
    const groups = [];
    c.steps.forEach((s, i) => {
      if (!s.group) return;
      const g = groups[groups.length - 1];
      if (g && g.name === s.group && g.last === i - 1) g.last = i; else groups.push({ name: s.group, first: i, last: i });
    });
    const inGroup = (i) => groups.some((g) => i >= g.first && i <= g.last);
    // 横の並び: 名前の列(まとまりの名前、括り、まとまりの中の名前)、48px、三角形、48px、量の列、48px、外のエリアと見つけ出すもののカードの列。
    const gnx = bw + arm + near;   // 値でない: 括りの縦線と腕と 8px のあとに、まとまりの中の名前
    const nameW = (t) => Math.max(...t.split('\n').map((k) => roleW('本文', k)));   // 値でない: 名前を改行の位置で折ったときの、いちばん長い行の幅
    const nameEnd = (i) => (inGroup(i) ? gnx : 0) + nameW(c.steps[i].name);
    const nameCol = Math.max(...c.steps.map((s, i) => nameEnd(i)), ...groups.map((g) => roleW('本文', g.name)));
    const tx = nameCol + gapX, cx = tx + TW / 2;   // 値でない: 三角形の左右の真ん中
    const valW = Math.max(...pts.map((q) => [...h.quantity(q)].length)) * V('太字の欧文の字の幅の比') * P.roleSize('棒の値');   // 値でない: 字の数に、1 字の幅の見積もりを掛ける
    const vx = tx + TW + gapX, ax = vx + valW + gapX;   // 値でない: 列を左から積む
    // 縦の並び: ラベル、種類の名前の行、8px、三角形、0% の行の下半分。
    const kindY = labH, ty = kindY + lineH + near + valH / 2;   // 値でない: 上から積む。種類の名前の行は、上の辺の量の行の上半分の、さらに 8px 上
    const yOf = (q) => ty + TH * (1 - q.n / start);   // 値でない: 残りの量から、境の高さ(辺がまっすぐになる)
    const wOf = (q) => TW * q.n / start;              // 値でない: 残りの量に比例する幅
    const figH = ty + TH + valH / 2;                 // 値でない: 0% の行の下端
    let svg = '', html = '';
    // 層。辺はまっすぐで、層と層の境は地の色の線で分ける。
    c.steps.forEach((s, i) => {
      const a = wOf(pts[i]) / 2, b = wOf(pts[i + 1]) / 2, y1 = yOf(pts[i]), y2 = yOf(pts[i + 1]);   // 値でない: 幅の半分
      svg += `<path data-part="残りの三角形" d="M${r2(cx - a)} ${r2(y1)}H${r2(cx + a)}L${r2(cx + b)} ${r2(y2)}H${r2(cx - b)}Z" style="fill:${V(`残りの三角形の層の色.${i + 1}`)};stroke:var(--bg)" stroke-width="${sep}"/>`;
    });
    svg += `<path data-part="置いた値" d="M${r2(cx - TW / 2)} ${r2(ty)}H${r2(cx + TW / 2)}L${r2(cx)} ${r2(ty + TH)}Z" fill="none" style="stroke:var(--ink)" stroke-width="${lw}" stroke-dasharray="${dash}"/>`;
    html += `<div ${T('本文')} style="left:${px(cx - roleW('本文', c.start.name) / 2)};top:${px(kindY)}">${e(c.start.name)}</div>`;   // 値でない: 三角形の左右の真ん中にそろえる
    const line = (x1, x2, y) => `<path data-part="引き出し線" d="M${r2(x1)} ${r2(y)}H${r2(x2)}" fill="none" style="stroke:var(--sub)" stroke-width="${thin}"/>`;
    // 段階の名前。層の上下の真ん中の真横に置き、三角形の左の辺へ水平の線を引く。
    const mids = c.steps.map((s, i) => (yOf(pts[i]) + yOf(pts[i + 1])) / 2);   // 値でない: 層の上下の真ん中
    c.steps.forEach((s, i) => {
      const x = inGroup(i) ? gnx : 0;
      const edge = cx - TW * (1 - (mids[i] - ty) / TH) / 2;   // 値でない: 左の辺の、層の真ん中の高さでの位置
      const rows = s.name.split('\n');   // 値でない: データの改行の位置で折る
      html += `<div ${T('本文')} style="left:${px(x)};top:${px(mids[i] - rows.length * lineH / 2)}">${rows.map((k) => `<span class="nw">${e(k)}</span>`).join('<br>')}</div>`;
      svg += line(x + nameW(s.name) + near, edge - near, mids[i]);
    });
    // まとまりの括り。まとまりの最初と最後の名前の行の上端から下端まで縦線を引き、両端から名前の側へ腕を出す。名前は、縦線の左に、上下の真ん中にそろえる。
    groups.forEach((g) => {
      const y1 = mids[g.first] - lineH / 2, y2 = mids[g.last] + lineH / 2, x = bw / 2;   // 値でない: 線の太さの半分だけ内側
      const above = g.first > 0 ? mids[g.first - 1] + lineH / 2 : kindY + lineH;   // 値でない: 1 つ上の行の下端
      if (y1 - above < lineH) throw new Error(`まとまり「${g.name}」の名前の行が入らない。まとまりの 1 つ上の層を厚くする`);
      svg += `<path data-part="括り" d="M${r2(x + arm)} ${r2(y1)}H${r2(x)}V${r2(y2)}H${r2(x + arm)}" fill="none" style="stroke:var(--ink)" stroke-width="${bw}"/>`;
      html += `<div ${T('本文')} style="left:0;top:${px(y1 - lineH)}">${e(g.name)}</div>`;   // 値でない: 括りの上の端の、すぐ上の行
    });
    // 残る量。境の真横に置き、境の右の端から量の手前まで水平の線を引く。上の辺の量は、上の辺の真横なので線を引かない。0% だけを強調の色にする。
    pts.forEach((q, i) => {
      const last = i === n, y = yOf(q);
      html += `<div ${T('棒の値', last ? 'em' : '')}${last ? ' data-emphasis' : ''} style="left:${px(vx)};top:${px(y - valH / 2)}">${e(h.quantity(q))}</div>`;   // 値でない: 行の真ん中
      if (i > 0) svg += line(cx + wOf(q) / 2 + near, vx - near, y);
    });
    // 外のエリア。外の種類の名前だけを持つ入れ物で、下端を三角形の下の頂点にそろえる。高さは、名前の行の数と上下の余白。
    const kindParts = c.outside.kind.split('\n');   // 値でない: データの改行の位置で、文節ごとに折る
    const kindLines = kindParts.length;
    const AH = kindLines * lineH + 2 * pad;   // 値でない: 名前の行と上下の余白
    const ay = ty + TH - AH;   // 値でない: 下端を三角形の下の頂点にそろえる
    html += `<div class="oa" data-part="外のエリア" style="left:${px(ax)};top:${px(ay)};width:${AW}px;height:${px(AH)}"><div ${T('本文')}>${kindParts.map((k) => `<span class="nw">${e(k)}</span>`).join('<br>')}</div></div>`;
    // 見つけ出すもののカード。外のエリアの上に、左右の真ん中をそろえて置き、カードから外のエリアへ下向きの矢印を引く。
    const cardH = lineH + 2 * pad, cardW = roleW('図の中のカードの名前', c.outside.finder) + 2 * pad;   // 値でない: 名前と余白
    const acx = ax + AW / 2;   // 値でない: 外のエリアの左右の真ん中
    const cardY = ty;   // 値でない: カードの上端を、三角形の上の辺にそろえる
    html += `<div class="fc" data-part="見つけ出すもののカード" style="left:${px(acx - cardW / 2)};top:${px(cardY)}"><div ${T('図の中のカードの名前')}>${e(c.outside.finder)}</div></div>`;
    const lw2 = V('矢印の線の太さ'), depth = V('矢じりの奥行き'), hb = V('矢じりの底辺') / 2;   // 値でない: 底辺の半分
    const a0 = cardY + cardH + near, a1 = ay - near;   // 値でない: カードと外のエリアから 8px 離す
    svg += `<g data-part="矢印"><path d="M${r2(acx)} ${r2(a0)}V${r2(a1 - depth)}" fill="none" style="stroke:var(--ink)" stroke-width="${lw2}"/><path d="M${r2(acx - hb)} ${r2(a1 - depth)}L${r2(acx)} ${r2(a1)}L${r2(acx + hb)} ${r2(a1 - depth)}Z" style="fill:var(--ink)"/></g>`;
    html += `<div ${T('矢印に添える名前')} style="left:${px(acx + hb + near)};top:${px((a0 + a1) / 2 - V('文字の行の高さ.矢印に添える名前') / 2)}">${e(c.outside.verb)}</div>`;   // 値でない: 矢じりの底辺の右の端から 8px 右、矢印の上下の真ん中
    if (c.label) html += P.label(c.label, null, 'position:absolute;left:0;top:0');
    const css = `.rt{position:relative}
.rt>[data-role],.rt>[data-part]{position:absolute;white-space:nowrap}
.rt>svg{position:absolute;left:0;top:0}
.rt .em{color:var(--blue)}
.rt .oa{box-sizing:border-box;padding:${pad}px;background:var(--bg);border:${V('外のエリアの枠の線の太さ')}px solid var(--line);display:flex;flex-direction:column;justify-content:center}
.rt .nw{white-space:nowrap}
.rt .fc{box-sizing:border-box;padding:${pad}px;background:var(--tint);border-radius:${V('カードの角丸')}px}`;
    const body = `<div class="rt" style="width:${W}px;height:${px(figH)}"><svg data-full-width width="${W}" height="${r2(figH)}" viewBox="0 0 ${W} ${r2(figH)}" aria-hidden="true">${svg}</svg>${html}</div>`;
    return { css, body };
  },
};
