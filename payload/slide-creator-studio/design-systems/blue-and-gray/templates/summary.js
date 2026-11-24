'use strict';
// まとめ(現状、原因、提案、効果を 1 枚で言う)。見本: examples/summary.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'summary',
  sectionFixed: 'まとめ',
  when: '現状、原因、提案、効果を 1 枚で言う。役割の違う章のまとめで、前後の関係(量が減る)を持つ。原則「まとめに、中身のスライドの結論だけを持たせる」の対象。原則「役割の違う部品を、形か色で見分けられるようにする」に合わせ、現状の棒を薄く、効果の棒を青にする。上から、現状の値の行と棒、原因、提案、効果の値の行と棒の順に積み、現状の棒と原因の間と、提案と効果の間を、値「間隔.まとめの現状の棒と原因」「間隔.まとめの提案と効果」の広い間に、原因と提案の間を、値「間隔.まとめの原因と提案」の狭い間にして、現状、なぜ減るか(原因と提案)、効果の 3 つのまとまりに分ける。図の上の、量を言うラベルと現状の値の行は、左端を棒の左端(行の見出しの列の右の、値「間隔.行の見出しの列と図」の右)にそろえる。行の見出しの列の左端にそろえる代わりに棒の左端にそろえるのは、ラベルを、左の行の名前の列でなく、右の棒の量の名前として読ませるためである。',
  parts: ['ラベル', '行の見出し', '名前と値の行', '比べる棒', '減る矢印', '推計の範囲', '付録の番号'],
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
    const { V, T, W, S, e, px, r2, span } = P;
    const c = data.content;
    const hd = V('行の見出しの列の幅(まとめ)');
    const x0 = hd + V('間隔.行の見出しの列と図');   // 図の左端
    const figW = W - x0;
    const barH = V('まとめの棒の高さ');
    const sc = P.scale(figW, c.current.n);
    const wCur = c.current.n * sc, wEff = c.effect.n * sc;
    const tip = wEff + V('間隔.矢じりの先と変えた後の棒');
    const kH = V('文字の行の高さ.棒の値');        // 量の行の高さ
    const lbH = V('文字の行の高さ.行の見出し');
    const stH = V('文字の行の高さ.まとめの原因と提案');
    const mH = V('文字の行の高さ.主な数字');
    const diff = c.current.n - c.effect.n;
    const diffText = `${diff >= 0 ? V('減った差の符号') : V('増えた差の符号')}${h.quantity({ n: Math.abs(diff), unit: c.effect.unit })}`;
    const rn = (name, top, hh) => `<div ${T('行の見出し')} data-part="行の見出し" style="left:0;top:${r2(top + (hh - lbH) / 2)}px">${e(name)}</div>`;

    const toBar = V('間隔.名前と値の行と棒');
    const barCur = kH + toBar;                     // 現状の棒の上端
    const causeTop = barCur + barH + V('間隔.まとめの現状の棒と原因');
    const propTop = causeTop + stH + V('間隔.まとめの原因と提案');
    const effRow = propTop + stH + V('間隔.まとめの提案と効果'); // 効果の値の行の上端
    const barEff = effRow + mH + toBar;
    const rangeTop = barEff + barH + V('間隔.比べる棒と推計の範囲の帯');
    let html = '';
    html += `<div class="k" style="left:${x0}px;top:0">${span('ラベル', c.quantityLabel, 'data-part="ラベル"')}${span('棒の値', h.quantity(c.current))}</div>`;
    // 現状の行: 行の見出しと、いちばん長い棒を、本文領域の幅いっぱいの行の要素に入れる。
    html += `<div data-full-width style="left:0;top:${barCur}px;width:${W}px;height:${barH}px">${rn(c.rowNames.current, 0, barH).replace('style="', 'style="position:absolute;')}<div data-part="比べる棒" style="position:absolute;left:${x0}px;top:0;width:${px(wCur)};height:${barH}px;background:var(--line)"></div></div>`;
    html += rn(c.rowNames.cause, causeTop, stH) + `<div ${T('まとめの原因と提案')} style="left:${x0}px;top:${causeTop}px">${e(c.cause)}</div>`;
    html += rn(c.rowNames.proposal, propTop, stH) + `<div ${T('まとめの原因と提案')} style="left:${x0}px;top:${propTop}px">${e(c.proposal)}</div>`;
    html += `<div class="k" data-part="名前と値の行" style="left:${x0}px;top:${effRow}px;gap:0"><span ${T('棒の値')} style="flex:0 0 ${px(tip)}">${e(h.quantity(c.effect))}</span><span ${T('主な数字')} style="flex:0 0 ${px(wCur - tip)};text-align:center">${e(diffText)}</span></div>`;
    html += rn(c.rowNames.effect, barEff, barH);
    html += `<div data-part="比べる棒" data-emphasis style="left:${x0}px;top:${barEff}px;width:${px(wEff)};height:${barH}px;background:var(--blue)"></div>`;
    html += P.shrinkArrow(wCur, barH, tip).replace('<svg ', `<svg style="position:absolute;left:${x0}px;top:${barEff}px" `);
    let total = barEff + barH;
    if (c.range) {
      const r = P.parseRange(c.range);
      const left = x0 + r.min * sc, width = (r.max - r.min) * sc, th = V('推計の範囲の帯の太さ');
      html += `<div data-part="推計の範囲" style="left:${r2(left)}px;top:${rangeTop}px;width:${px(width)};height:${th}px;background:var(--blue)"></div>`;
      const noteTop = rangeTop + th + V('間隔.推計の範囲の帯とその説明');
      html += `<div class="k" style="left:${r2(left)}px;top:${noteTop}px;gap:0">${span('ラベル', V('推計の範囲の説明の語'), 'data-part="ラベル"')}${span('値の説明', c.range, `style="margin-left:${S}px"`)}</div>`;
      total = noteTop + V('文字の行の高さ.値の説明');
    }
    return { css: '', body: `<div class="fg" style="width:${W}px;height:${total}px">${html}</div>` };
  },
};
