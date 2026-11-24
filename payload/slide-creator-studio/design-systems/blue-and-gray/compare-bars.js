'use strict';
// compare-two と compare-two-with-formula が共有する、2 本の棒(量を比べる棒)の組み立て。
module.exports = function compareBars(P, h, c) {
  const { V, W, S, px, span, label } = P;
  const barH = V('量を比べる棒の高さ(2 本、3 本)');
  const full = c.axisMax ? c.axisMax.total : null;
  const fullN = full ? full.n : 0;
  const maxN = Math.max(...c.items.map((i) => i.value.n));
  const sc = P.scale(W, maxN, fullN);
  const focus = c.items.find((i) => i.name === c.focus);
  const rows = c.items.map((it, i) => {
    const f = it === focus;
    const rowH = V(f ? '文字の行の高さ.主な数字' : '文字の行の高さ.棒の値');
    const note = it.note ? `<span class="t-値の説明 n" data-role="${V('文字の種類.値の説明')}">${h.esc(it.note)}</span>` : '';
    // ラベルのすぐ下の行が主な数字を持つときだけ、ラベルとの間を、値「間隔.ラベルと主な数字の行」にする。
    // 2 本目からは、前の棒の下端と、次の名前と値の行の間を、値「間隔.量を比べる棒と次の名前と値の行」にする。
    const top = i > 0 ? V('間隔.量を比べる棒と次の名前と値の行') : (f ? V('間隔.ラベルと主な数字の行') : S);
    return `<div class="it" data-part="名前と値の行" style="height:${rowH}px;margin-top:${top}px;line-height:${rowH}px"><div class="k">` +
      span('項目の名前', it.name) + span(f ? '主な数字' : '棒の値', h.quantity(it.value)) + note + '</div></div>' +
      `\n<div data-part="量を比べる棒"${f ? ' data-emphasis' : ''} style="height:${barH}px;margin-top:${V('間隔.名前と値の行と棒')}px;width:${px(it.value.n * sc)};background:var(${f ? '--blue' : '--line'})"></div>`;
  });
  const axisW = fullN ? fullN * sc : maxN * sc;
  const endLabel = fullN ? h.quantity({ n: full.n, unit: full.unit }) + (c.axisMax.name ? `(${c.axisMax.name})` : '') : h.quantity({ n: maxN, unit: c.items[0].value.unit });
  const zero = h.quantity({ n: 0, unit: fullN ? full.unit : c.items[0].value.unit });
  return label(c.label, c.labelRef) + '\n' + rows.join('\n') + '\n' + P.axis(axisW, endLabel, zero);
};
