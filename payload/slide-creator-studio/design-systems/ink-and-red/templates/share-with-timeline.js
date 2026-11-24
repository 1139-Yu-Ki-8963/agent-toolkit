'use strict';
// 割合と、時間の線(括りでつなぐ)。見本: examples/share-with-timeline.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'share-with-timeline',
  when: 'ある割合の件で、何がどの順に起きたかを言う。結論の一文が、割合か件数と、それが起きる時点の両方を言う。時点は 3 つまでで、日数を持たず、順だけを持つ。原則「同じ話の要素を近くに置く」に合わせ、割合の帯と時間の線を括りでつなぐ。結論の一文が指す時点の点を赤にし、赤い帯と、括りでつないだ赤い点を、1 まとまりの強調と数える(値「強調の要素の数の上限」、部品「点」)。',
  parts: ['ラベル', '名前と値の行', '主役の帯グラフ', '括り', '時間の線', '点', '言葉の説明', '付録の番号'],
  schema: {
    denominator: { type: 'text', required: true },
    denominatorRef: { type: 'text' },
    items: {
      type: 'list', required: true, maxItems: '帯グラフの項目の数の上限',
      item: { type: 'object', fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true } } },
    },
    focus: { type: 'text', required: true },
    bracketLabel: { type: 'text', required: true },
    points: {
      type: 'list', required: true, maxItems: '時間の順と手順の点の数の上限',
      item: {
        type: 'object',
        fields: {
          time: { type: 'text', required: true },
          heading: { type: 'text' },
          gloss: { type: 'text' },
          focusLabel: { type: 'text' },
        },
      },
    },
    focusPoint: { type: 'text', required: true },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, W, B, e, px, span, label } = P;
    const c = data.content;
    const total = c.items.reduce((a, i) => a + i.value.n, 0);
    const gapV = V('隣り合う「ほか」の項目の間');
    const isF = (it) => it.name === c.focus;
    const gaps = c.items.map((it, i) => (i > 0 && !isF(it) && !isF(c.items[i - 1]) ? gapV : 0));
    const avail = W - gaps.reduce((a, b) => a + b, 0);
    const widths = c.items.map((it) => (avail * it.value.n) / total);
    const fi = c.items.findIndex(isF);
    const fLeft = widths.slice(0, fi).reduce((a, b) => a + b, 0) + gaps.slice(0, fi + 1).reduce((a, b) => a + b, 0);
    const fW = widths[fi];
    const rowH = V('文字の行の高さ.主な数字');
    const bandH = V('主役の帯グラフの高さ');

    const cells = c.items.map((it, i) => {
      const f = isF(it);
      return `<div class="k" style="flex:0 0 ${px(widths[i])};${gaps[i] ? `margin-left:${gaps[i]}px;` : ''}">${span('項目の名前', it.name)}${span(f ? '主な数字' : '棒の値', h.quantity(it.value))}</div>`;
    });
    let other = 0;
    const segs = c.items.map((it, i) => {
      const color = isF(it) ? '--red' : ((other++ % 2 === 0) ? '--line' : '--sub');
      return `<div style="flex:0 0 ${px(widths[i])};${gaps[i] ? `margin-left:${gaps[i]}px;` : ''}background:var(${color})"${isF(it) ? ' data-emphasis' : ''}></div>`;
    });

    // 時間の線。順だけを持つ時点は、本文領域を同じ幅に分けた列の左端に、点の左端をそろえる。
    const n = c.points.length;
    const colW = (W - B * (n - 1)) / n;
    const pts = c.points.map((p, i) => {
      const focus = p.time === c.focusPoint;
      return { left: i * (colW + B), d: V(focus ? '見てほしい点の直径' : '点の直径'), red: focus, emphasis: false };
    });
    const tl = P.timeline(pts, W);
    const fp = c.points.findIndex((p) => p.time === c.focusPoint);
    const focusLabel = c.points[fp].focusLabel;
    const lbH = V('文字の行の高さ.見てほしい点のラベル'), tlH = V('時間の線の点の行の高さ');
    const flab = focusLabel ? `<span class="fl t-見てほしい点のラベル" data-role="${V('文字の種類.見てほしい点のラベル')}" style="left:${px(pts[fp].left + pts[fp].d + V('間隔.見てほしい点と見てほしい点のラベル'))};top:${px((tlH - lbH) / 2)}">${e(focusLabel)}</span>` : '';
    const cols = c.points.map((p) =>
      '<div>' + span('時点の名前', p.time) +
      (p.heading ? span('点の見出し', p.heading) : '') +
      (p.gloss ? span('言葉の説明', p.gloss, 'data-part="言葉の説明"') : '') + '</div>');

    const body =
      label(c.denominator, c.denominatorRef) +
      `\n<div class="it" data-part="名前と値の行" style="height:${rowH}px;margin-top:${V('間隔.ラベルと主な数字の行')}px;line-height:${rowH}px">${cells.join('')}</div>` +
      `\n<div class="br" data-part="主役の帯グラフ" data-full-width style="height:${bandH}px;margin-top:${V('間隔.名前と値の行と棒')}px">${segs.join('')}</div>` +
      '\n' + P.bracket(W, fLeft, fLeft + fW) +
      `\n${label(c.bracketLabel, '', `width:${px(fW)};margin-left:${px(fLeft)};margin-top:${V('間隔.括りと括りの名前')}px;text-align:center`)}` +
      `\n<div class="tw" style="height:${tlH}px;margin-top:${V('間隔.括りの名前と時間の線')}px">${tl}${flab}</div>` +
      `\n<div class="pt" style="grid-template-columns:repeat(${n},${px(colW)})">${cols.join('')}</div>`;
    return { css: `.tw{position:relative}\n.tw svg{position:absolute;left:0;top:0}\n.tw .fl{position:absolute;padding:0 ${V('間隔.時間の線と見てほしい点のラベル')}px;background:var(--bg);display:block}`, body };
  },
};
