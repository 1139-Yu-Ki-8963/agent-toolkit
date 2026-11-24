'use strict';
// 部品の HTML を作る関数の集まり。テンプレート(templates/*.js)が使う。値は、すべて tokens.json から読む。
// 幅と位置の計算(値に比例する長さ、点の位置)は、テンプレートの render が持つ。ここは、部品の形だけを持つ。
// 字数の数え方(1 つだけ)。改行は数えない。全角は 1 字、半角の数字と英字は値「数字の半角の幅(字の大きさに対する比)」の字、
// そのほかの半角の記号は値「半角の記号の幅(字の大きさに対する比)」の字として数える。
function countChars(text, tokens) {
  const val = (n) => ((tokens.values && tokens.values[n]) || tokens.local[n]).value;
  const alnum = val('数字の半角の幅(字の大きさに対する比)'), sym = val('半角の記号の幅(字の大きさに対する比)');
  let n = 0;
  for (const ch of String(text)) {
    if (ch === '\n' || ch === '\r') continue;
    if (/[0-9A-Za-z]/.test(ch)) n += alnum;
    else if (/[\u0020-\u007e]/.test(ch)) n += sym;
    else n += 1;
  }
  return n;
}

module.exports = function makeParts(tokens, h) {
  const V = (name) => {
    const v = h.value(name);
    if (v === undefined) throw new Error(`tokens.json に値がない: ${name}`);
    return v;
  };
  const e = h.esc;
  const r2 = (n) => Math.round(n * 100) / 100; // 値でない: px の数を、小数 2 桁に丸める
  const px = (n) => `${r2(n)}px`;
  // S は、部品「ラベル」と「列の上のラベル」が言う、名前と、すぐ下か右の中身の間。ほかの関係は、関係ごとの値を V で引く。
  const S = V('間隔.名前と、その中身');      // 8
  const W = V('本文領域の幅');                  // 1728

  // 文字の幅の見積もり(px)。字数(countChars)に、字の大きさを掛ける。
  const textW = (text, size) => countChars(text, tokens) * size;
  const roleSize = (role) => V(`文字の大きさ.${role}`);
  const roleW = (role, text) => textW(text, roleSize(role));

  // 文字の要素の属性。class は、文字の種類(CSS の見た目)、data-role は、原則「文字の大きさを、種類ごとの下限以上にする」の文字の種類(測る道具が下限を引く)。
  const T = (fine, extraClass = '') => `class="t-${fine}${extraClass ? ' ' + extraClass : ''}" data-role="${V('文字の種類.' + fine)}"`;
  const span = (fine, text, attr = '') => `<span ${T(fine)}${attr ? ' ' + attr : ''}>${e(text)}</span>`;
  // 付録の番号は、間を空けずに、半角の括弧に入れて末尾に付ける(部品「付録の番号」)。
  const refHtml = (ref) => (ref ? `<span data-part="付録の番号">(${e(ref)})</span>` : '');
  const withRef = (text, ref) => e(text) + refHtml(ref);
  // ラベル(分母を言うラベルなど)。末尾に、付録の番号を、間を空けずに置く。
  const label = (text, ref, style = '') =>
    `<div ${T('ラベル', 'lb')} data-part="ラベル"${style ? ` style="${style}"` : ''}>${withRef(text, ref)}</div>`;
  const labelText = (text, ref) => text + (ref ? `(${ref})` : '');

  // 矢じり(右向き)と線。start から end(矢じりの先)まで。y は線の高さ。
  function rightArrowShapes(start, end, y, color) {
    const depth = V('矢じりの奥行き'), half = V('矢じりの底辺') / 2, lw = V('矢印の線の太さ');
    return `<path d="M${r2(start)} ${y}H${r2(end - depth)}" fill="none" style="stroke:${color}" stroke-width="${lw}"/>` +
      `<path d="M${r2(end - depth)} ${y - half}L${r2(end)} ${y}L${r2(end - depth)} ${y + half}Z" style="fill:${color}"/>`;
  }
  // 時間の線と点。points: [{left, d, emphasis}]。左端は最初の点の左端、右端は最後の点の右端の 48px 右。
  function timeline(points, width, opts = {}) {
    const hgt = V('時間の線の点の行の高さ'), cy = hgt / 2;
    const first = points[0], last = points[points.length - 1];
    const end = last.left + last.d + V('時間の線の右の延び');
    let s = `<svg data-part="時間の線"${Math.abs(width - W) < 0.5 ? ' data-full-width' : ''} class="tl" width="${width}" height="${hgt}" viewBox="0 0 ${width} ${hgt}" aria-hidden="true"${opts.style ? ` style="${opts.style}"` : ''}>`;
    s += rightArrowShapes(first.left, end, cy, 'var(--ink)');
    for (const p of points) {
      s += `<circle data-part="点"${p.emphasis ? ' data-emphasis' : ''} cx="${r2(p.left + p.d / 2)}" cy="${cy}" r="${r2(p.d / 2)}" style="fill:${p.emphasis || p.blue ? 'var(--blue)' : 'var(--ink)'}"/>`;
    }
    return s + '</svg>';
  }
  // 括り。x0 から x1 までの幅の、下へ向かう線を持たない括り。
  function bracket(width, x0, x1) {
    const lw = V('括りの線の太さ'), top = V('括りの縦線の上の端'), y = V('括りの横線の位置'), hgt = V('括りの図の高さ');
    return `<svg data-part="括り" class="bk" width="${width}" height="${hgt}" viewBox="0 0 ${width} ${hgt}" aria-hidden="true">` +
      `<path d="M${r2(x0 + lw / 2)} ${top}V${y}H${r2(x1 - lw / 2)}V${top}" fill="none" style="stroke:var(--ink)" stroke-width="${lw}"/></svg>`;
  }
  // 軸(両端に縦線)と、その 8px 下の、0 と全体の値。
  // 縦線は、線の太さの半分だけ内側に引き、縦線の外の端を、svg の左端と右端(棒の 0 の位置と全体の位置)にそろえる。
  // svg の高さは、縦線の長さに線の太さの半分を足した高さで、横線の下の端が svg の下端になる。
  function axis(width, endLabel, startLabel) {
    const lw = V('軸の線の太さ'), t = V('軸の端の縦線の長さ'), half = lw / 2;
    return `<svg data-part="軸"${Math.abs(width - W) < 0.5 ? ' data-full-width' : ''} class="ax" width="${r2(width)}" height="${t + half}" viewBox="0 0 ${r2(width)} ${t + half}" aria-hidden="true"><path d="M${half} 0V${t}H${r2(width - half)}V0" fill="none" style="stroke:var(--line)" stroke-width="${lw}"/></svg>` +
      `<div class="av" style="width:${px(width)}">${span('グラフの軸の値', startLabel)}${span('グラフの軸の値', endLabel)}</div>`;
  }
  // 減る矢印(左向き、本文の文字の色)。svg の幅 svgW、高さ hgt。tip は矢じりの先の位置。
  function shrinkArrow(svgW, hgt, tip) {
    const depth = V('矢じりの奥行き'), half = V('矢じりの底辺') / 2, lw = V('矢印の線の太さ'), cy = hgt / 2;
    return `<svg data-part="減る矢印" width="${r2(svgW)}" height="${hgt}" viewBox="0 0 ${r2(svgW)} ${hgt}" aria-hidden="true">` +
      `<path d="M${r2(svgW)} ${cy}H${r2(tip + depth)}" fill="none" style="stroke:var(--ink)" stroke-width="${lw}"/>` +
      `<path d="M${r2(tip + depth)} ${cy - half}L${r2(tip)} ${cy}L${r2(tip + depth)} ${cy + half}Z" style="fill:var(--ink)"/></svg>`;
  }
  // 棒の長さの 1 単位あたりの px。決まった全体があるときは、その全体が幅いっぱい。ないときは、いちばん長い棒が幅いっぱい(原則「図に本文領域の広さを使わせる」)。
  function scale(width, maxN, fullN) {
    if (fullN) return width / fullN;
    return width / maxN;
  }
  // 結論の一文の行の数の見積もり。改行(\n)があれば、その行の数。ないときは、字数から決める。
  function conclusionLines(text) {
    const per = roleSize('結論の一文');
    const lines = String(text).split('\n');
    let n = 0;
    for (const l of lines) n += Math.max(1, Math.ceil(textW(l, per) / W - 1e-9));
    return n;
  }
  // 結論の一文の HTML。数と単位(「約1,400個」)は、途中で改行しない塊にする。
  // 改行(\n)を持たず、1 行に収まらない文は、前後がどちらも 1 行に収まる読点のうち、真ん中にいちばん近い読点の後ろで改行する。
  function conclusionHtml(text) {
    const size = roleSize('結論の一文');
    let lines = String(text).split('\n');
    // 改行(\n)を持つ文でも、全体が 1 行に入るなら、1 行で置く(部品「結論の一文」の意図)。
    if (lines.length > 1 && textW(lines.join(''), size) <= W) lines = [lines.join('')];
    if (lines.length === 1 && textW(lines[0], size) > W) {
      const s = lines[0];
      let best = -1, bestDiff = Infinity;
      for (let i = 0; i < s.length - 1; i++) {
        if (s[i] !== '、') continue;
        const a = textW(s.slice(0, i + 1), size), b = textW(s.slice(i + 1), size);
        if (a <= W && b <= W && Math.abs(a - b) < bestDiff) { best = i; bestDiff = Math.abs(a - b); }
      }
      if (best >= 0) lines = [s.slice(0, best + 1), s.slice(best + 1)];
    }
    // 単位の漢字は、値「結論の一文の数と単位の塊の単位の漢字の数の上限」の字までを塊に入れる。
    const kanjiMax = V('結論の一文の数と単位の塊の単位の漢字の数の上限');
    const chunk0 = /約?[0-9][0-9,.]*[A-Za-z%]*[\u4e00-\u9fff]/;
    const chunk = new RegExp(`${chunk0.source}{0,${kanjiMax}}`, 'g');
    return lines.map((l) => e(l).replace(chunk, (m) => `<span style="white-space:nowrap">${m}</span>`)).join('<br>');
  }
  // 範囲の文字「25〜35件」から、下の端と上の端の数を読む。
  function parseRange(text) {
    const m = /(-?\d+(?:\.\d+)?)\s*[〜~～]\s*(-?\d+(?:\.\d+)?)/.exec(String(text).replace(/(\d),(?=\d)/g, '$1'));
    if (!m) throw new Error(`範囲の文字を読めない: ${text}`);
    return { min: Number(m[1]), max: Number(m[2]) };
  }
  const fmt = (n, unit) => h.quantity({ n, unit });
  return { V, T, e, r2, px, S, W, textW, roleW, roleSize, span, label, withRef, refHtml, labelText, rightArrowShapes, timeline, bracket, axis, shrinkArrow, scale, conclusionLines, parseRange, conclusionHtml, fmt };
};
module.exports.countChars = countChars;
