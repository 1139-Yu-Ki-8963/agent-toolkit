'use strict';
// まとめ(現状、原因、提案、効果を 1 枚で言う)。見本: examples/summary.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'summary',
  sectionFixed: 'まとめ',
  when: '現状、原因、提案、効果を 1 枚で言う。役割の違う章のまとめで、前後の関係(量が減る)を持つ。原則「まとめに、中身のスライドの結論だけを持たせる」の対象。原則「役割の違う部品を、形か色で見分けられるようにする」に合わせ、現状の棒を薄く、効果の棒を赤にする。',
  parts: ['ラベル', '行の見出し', '比べる棒', '減る矢印', '推計の範囲', '推計の範囲の説明'],
  schema: {
    quantityLabel: { type: 'text', required: true },
    rowNames: { type: 'object', required: true, fields: { current: { type: 'text', required: true }, cause: { type: 'text', required: true }, proposal: { type: 'text', required: true }, effect: { type: 'text', required: true } } },
    current: { type: 'quantity', required: true },
    cause: { type: 'text', required: true },
    proposal: { type: 'text', required: true },
    effect: { type: 'quantity', required: true },
    range: { type: 'text' },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, e, px, r2, span } = P;
    const rowGap = V('間隔.まとめの行と行'), barGap = V('間隔.名前と値の行と棒');
    const c = data.content;
    if (!(c.effect.n < c.current.n)) throw new Error(`効果の量が、現状の量より少なくない(この型は、減る量だけを描く): ${c.current.n} → ${c.effect.n}`);
    const x0 = V('行の見出しの列の幅(まとめ)');   // 図の左端
    const figW = W - x0;
    const barH = V('まとめの棒の高さ');
    const sc = figW / c.current.n; // いちばん長い棒が、図の幅いっぱい
    const wCur = c.current.n * sc, wEff = c.effect.n * sc;
    const tip = wEff + V('減る矢印の先と変えた後の棒の間');
    const kH = V('文字の行の高さ.棒の値');        // 量の行の高さ
    const lbH = V('文字の行の高さ.行の見出し');
    const stH = V('文字の行の高さ.まとめの原因と提案');
    const mH = V('文字の行の高さ.主な数字');
    const diff = c.current.n - c.effect.n;
    const diffText = `${diff >= 0 ? '−' : '+'}${h.quantity({ n: Math.abs(diff), unit: c.effect.unit })}`;
    const rn = (name, top, hh) => `<div ${T('行の見出し')} data-part="行の見出し" style="left:0;top:${r2(top + (hh - lbH) / 2)}px">${e(name)}</div>`;

    const barCur = kH + barGap;                    // 現状の棒の上端
    const causeTop = barCur + barH + rowGap;
    const propTop = causeTop + stH + rowGap;
    const effRow = propTop + stH + rowGap;         // 効果の値の行の上端
    const barEff = effRow + mH + barGap;
    const rangeTop = barEff + barH + V('間隔.棒と推計の範囲');
    let html = '';
    html += `<div class="k" style="left:${x0}px;top:0">${span('ラベル', c.quantityLabel, 'data-part="ラベル"')}${span('棒の値', h.quantity(c.current))}</div>`;
    // 現状の行: 行の見出しと、いちばん長い棒を、本文領域の幅いっぱいの行の要素に入れる。
    html += `<div data-full-width style="left:0;top:${barCur}px;width:${W}px;height:${barH}px">${rn(c.rowNames.current, 0, barH).replace('style="', 'style="position:absolute;')}<div data-part="比べる棒" style="position:absolute;left:${x0}px;top:0;width:${px(wCur)};height:${barH}px;background:var(--line)"></div></div>`;
    html += rn(c.rowNames.cause, causeTop, stH) + `<div ${T('まとめの原因と提案')} style="left:${x0}px;top:${causeTop}px">${e(c.cause)}</div>`;
    html += rn(c.rowNames.proposal, propTop, stH) + `<div ${T('まとめの原因と提案')} style="left:${x0}px;top:${propTop}px">${e(c.proposal)}</div>`;
    html += `<div class="k" style="left:${x0}px;top:${effRow}px;gap:0"><span ${T('棒の値')} style="flex:0 0 ${px(tip)}">${e(h.quantity(c.effect))}</span><span ${T('主な数字')} style="flex:0 0 ${px(wCur - tip)};text-align:center">${e(diffText)}</span></div>`;
    html += rn(c.rowNames.effect, barEff, barH);
    html += `<div data-part="比べる棒" data-emphasis style="left:${x0}px;top:${barEff}px;width:${px(wEff)};height:${barH}px;background:var(--red)"></div>`;
    html += P.shrinkArrow(wCur, barH, tip).replace('<svg ', `<svg style="position:absolute;left:${x0}px;top:${barEff}px" `);
    let total = barEff + barH;
    if (c.range) {
      const r = P.parseRange(c.range);
      const left = x0 + r.min * sc, width = (r.max - r.min) * sc, th = V('推計の範囲の帯の太さ');
      html += `<div data-part="推計の範囲" style="left:${r2(left)}px;top:${rangeTop}px;width:${px(width)};height:${th}px;background:var(--red)"></div>`;
      // 範囲の名前と値は、帯の左端にそろえ、本文領域の右端を超えるときだけ、右端にそろえる(before-after と同じ)。
      const rangeName = V('推計の範囲の名前'), nameGap = V('間隔.推計の範囲の名前と値');
      const labelLeft = P.fitLeft(left, P.roleWMax('ラベル', rangeName) + nameGap + P.roleWMax('値の説明', c.range));
      html += `<div class="k" data-part="推計の範囲の説明" style="left:${r2(labelLeft)}px;top:${rangeTop + th + V('間隔.推計の範囲と説明')}px;gap:0">${span('ラベル', rangeName)}${span('値の説明', c.range, `style="margin-left:${nameGap}px"`)}</div>`;
      total = rangeTop + th + V('間隔.推計の範囲と説明') + V('文字の行の高さ.値の説明');
    }
    return { css: '', body: `<div class="fg" style="width:${W}px;height:${total}px">${html}</div>` };
  },
};
