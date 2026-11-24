'use strict';
// 割合(主役の帯グラフ 1 本)。見本: examples/share-bar.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'share-bar',
  when: '全体のうち、1 つの項目が大半である。1 つの割合か、1 つの全体の構成比を見せ、数字の面を使う条件(内訳が 3 行、大きな数字が 2 桁以下、内訳の名前と値の行が帯に入る)の 1 つでも外れる。原則「見せ方の型を、見せたい関係で選ぶ」の関係「割合」。原則「図に本文領域の広さを使わせる」に合わせ、帯の高さは、添える部品を持たない帯の値とする。',
  parts: ['ラベル', '名前と値の行', '主役の帯グラフ', '付録の番号'],
  schema: {
    denominator: { type: 'text', required: true },
    denominatorRef: { type: 'text' },
    items: {
      type: 'list', required: true, maxItems: '帯グラフの項目の数の上限',
      item: {
        type: 'object',
        fields: {
          name: { type: 'text', required: true },
          value: { type: 'quantity', required: true },
          note: { type: 'text' },
          noteKind: { type: 'text' },
          noteRef: { type: 'text' },
        },
      },
    },
    focus: { type: 'list', required: true, maxItems: '割合の単独の帯の項目の数の上限', item: { type: 'text' } },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, S, e, px, span, label } = P;
    const c = data.content;
    const items = c.items;
    const total = items.reduce((a, i) => a + i.value.n, 0);
    const isFocus = (it) => c.focus.includes(it.name);
    const gapV = V('隣り合う「ほか」の項目の間'), gapF = V('2 つの見せたい項目の間');
    // 隣り合う「ほか」の項目の間と、隣り合う 2 つの見せたい項目の間に、白い間を置く。見せたい項目と「ほか」の項目の間は、色の違いで分かれるので、間を置かない。
    const gaps = items.map((it, i) => {
      if (i === 0) return 0;
      if (!isFocus(it) && !isFocus(items[i - 1])) return gapV;
      if (isFocus(it) && isFocus(items[i - 1])) return gapF;
      return 0;
    });
    const avail = W - gaps.reduce((a, b) => a + b, 0);
    const widths = items.map((it) => (avail * it.value.n) / total);
    const rowH = V(items.some(isFocus) ? '文字の行の高さ.主な数字' : '文字の行の高さ.棒の値');
    const bandH = V('主役の帯グラフの高さ(添える部品を持たない帯)');

    const noteText = (it) => {
      let t = it.note || '';
      if (it.noteKind === '全体に対する割合') {
        t = `${h.quantity({ n: total, unit: it.value.unit })}の${Math.round((it.value.n / total) * 10)}割`; // 値でない: 10 は、割合を「割」(10 分の 1)の数に直す数
      }
      return t;
    };
    // 幅の見積もりに使う文字列(付録の番号を含む)。描くときは、付録の番号を部品「付録の番号」の span にする。
    const noteFull = (it) => noteText(it) + (it.noteRef ? `(${it.noteRef})` : '');
    // 名前と値の行の左端は、自分の帯の左端と、前の行の右端+列の間隔の下限の大きい方。最後の項目が本文領域からはみ出すときは、本文領域の右端に右ぞろえにする。
    const colGap = V('横に並べる列の間隔の下限');
    const rowW = items.map((it) => {
      const f = isFocus(it);
      const note = f ? noteFull(it) : '';
      return P.roleWMax('項目の名前', it.name) + V('間隔.項目の名前と値') + P.roleWMax(f ? '主な数字' : '棒の値', h.quantity(it.value)) + (note ? V('間隔.値と値の説明') + P.roleWMax('値の説明', note) : 0);
    });
    const lefts = [], toEnd = items.map(() => false);
    let bandLeft = 0, prevRight = -Infinity;
    items.forEach((it, i) => {
      bandLeft += gaps[i];
      let left = Math.max(bandLeft, prevRight + colGap);
      if (i === items.length - 1 && left + rowW[i] > W) { toEnd[i] = true; left = W - rowW[i]; }
      lefts.push(left);
      prevRight = left + rowW[i];
      bandLeft += widths[i];
    });
    const cells = items.map((it, i) => {
      const f = isFocus(it);
      const val = h.quantity(it.value);
      const note = f ? noteFull(it) : '';
      const w = i + 1 < items.length && !toEnd[i + 1] ? px(lefts[i + 1] - lefts[i]) : 'auto';
      return `<div class="k" style="flex:0 0 ${w};${toEnd[i] ? 'margin-left:auto;' : ''}">` +
        span('項目の名前', it.name) + span(f ? '主な数字' : '棒の値', val) +
        (note ? `<span ${T('値の説明', 'n')}>${e(noteText(it))}${P.refHtml(it.noteRef)}</span>` : '') + '</div>';
    });
    const multi = items.filter(isFocus).length > 1;
    let other = 0;
    const segs = items.map((it, i) => {
      let color = '--red';
      if (!isFocus(it)) color = (other++ % 2 === 0) ? '--line' : '--sub';
      return `<div style="flex:0 0 ${px(widths[i])};${gaps[i] ? `margin-left:${gaps[i]}px;` : ''}background:var(${color})"${!multi && isFocus(it) ? ' data-emphasis' : ''}></div>`;
    });
    const body =
      label(c.denominator, c.denominatorRef) +
      `\n<div class="it" data-part="名前と値の行" style="height:${rowH}px;margin-top:${items.some(isFocus) ? V('間隔.ラベルと主な数字の行') : S}px;line-height:${rowH}px">${cells.join('')}</div>` +
      `\n<div class="br" data-part="主役の帯グラフ" data-full-width${multi ? ' data-emphasis' : ''} style="height:${bandH}px;margin-top:${V('間隔.名前と値の行と棒')}px">${segs.join('')}</div>`;
    return { css: '', body };
  },
};
