'use strict';
// 前後(1 つの量の、変える前と変えた後の棒と、減る矢印と差)。見本: examples/before-after.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'before-after',
  when: '1 つの量が、前と後で減る(変わったものが、1 つの量である)。2 つ以上の量は、量ごとに 1 枚に分ける。原則「役割の違う部品を、形か色で見分けられるようにする」に合わせ、変える前を薄い灰色、変えた後を紫にし、差を主な数字にする。変える前の棒を本文領域の幅いっぱいにし、減った分を、変える前の棒の右端から左へ向く減る矢印で見せる(部品「比べる棒」「減る矢印」)。量が増える話は、変えた後の棒が本文領域の幅を超え、減る矢印の向きも合わないので、この型でなく、量の比較(compare-two)にする。',
  parts: ['ラベル', '名前と値の行', '比べる棒', '減る矢印', '推計の範囲', '推計の範囲の説明', '付録の番号'],
  schema: {
    label: { type: 'text', required: true },
    labelRef: { type: 'text' },
    before: { type: 'object', required: true, fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true } } },
    after: {
      type: 'object', required: true,
      fields: { name: { type: 'text', required: true }, value: { type: 'quantity', required: true }, range: { type: 'text' }, rangeNote: { type: 'text' } },
    },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, S, e, px, span, label } = P;
    const c = data.content;
    const barH = V('比べる棒の高さ');
    const sc = P.scale(W, c.before.value.n);
    const wBefore = c.before.value.n * sc, wAfter = c.after.value.n * sc;
    const tip = wAfter + V('間隔.矢じりの先と変えた後の棒');
    const diff = c.before.value.n - c.after.value.n;
    const diffApprox = !!(c.before.value.approx || c.after.value.approx); // 前か後が見込みなら、差も見込み
    const diffText = `${diffApprox ? V('見込みの差の頭の語') : ''}${diff >= 0 ? V('減った差の符号') : V('増えた差の符号')}${h.quantity({ n: Math.abs(diff), unit: c.after.value.unit })}`;
    const rowAfterH = V('文字の行の高さ.主な数字');
    const rowBeforeH = V('文字の行の高さ.棒の値');
    // 差は、減る矢印(矢じりの先から、線の右端まで)の左右の中央に置く。名前と値の組が矢じりの先に入らないときは、組の幅まで広げる。
    const pairW = P.roleW('項目の名前', c.after.name) + V('間隔.項目の名前と値') + P.roleW('棒の値', h.quantity(c.after.value));
    const nameW = Math.max(tip, pairW + V('間隔.名前と値の組と差の数字'));
    let range = '';
    if (c.after.range) {
      const r = P.parseRange(c.after.range);
      const left = r.min * sc, width = (r.max - r.min) * sc;
      range = `\n<div class="rl" data-part="推計の範囲" style="height:${V('推計の範囲の帯の太さ')}px;margin-top:${V('間隔.比べる棒と推計の範囲の帯')}px"><i style="left:${px(left)};width:${px(width)};height:${V('推計の範囲の帯の太さ')}px;background:var(--accent)"></i></div>` +
        `\n<div class="it" data-part="推計の範囲の説明" style="margin-top:${V('間隔.推計の範囲の帯とその説明')}px;margin-left:${px(left)}">${span('ラベル', V('推計の範囲の説明の語'))}<span style="margin-left:${S}px"></span>${span('値の説明', c.after.range + (c.after.rangeNote ? `(${c.after.rangeNote})` : ''))}</div>`;
    }
    const body =
      label(c.label, c.labelRef) +
      `\n<div class="it" data-part="名前と値の行" style="height:${rowBeforeH}px;margin-top:${S}px"><div class="k">${span('項目の名前', c.before.name)}${span('棒の値', h.quantity(c.before.value))}</div></div>` +
      `\n<div class="rl" data-part="比べる棒" style="height:${barH}px;margin-top:${V('間隔.名前と値の行と棒')}px"><i data-full-width style="left:0;width:${px(wBefore)};height:${barH}px;background:var(--line)"></i></div>` +
      `\n<div class="it" data-part="名前と値の行" style="height:${rowAfterH}px;margin-top:${V('間隔.変える前の棒と変えた後の名前と値の行')}px"><div class="k" style="flex:0 0 ${px(nameW)}">${span('項目の名前', c.after.name)}${span('棒の値', h.quantity(c.after.value))}</div>` +
      `<div style="flex:0 0 ${px(wBefore - nameW)};text-align:center"><span ${T('主な数字')}>${e(diffText)}</span></div></div>` +
      `\n<div class="rl" data-part="比べる棒" style="height:${barH}px;margin-top:${V('間隔.名前と値の行と棒')}px"><i data-emphasis style="left:0;width:${px(wAfter)};height:${barH}px;background:var(--accent)"></i>` +
      P.shrinkArrow(wBefore, barH, tip).replace('<svg ', '<svg style="position:absolute;left:0;top:0" ') + '</div>' +
      range;
    return { css: '', body };
  },
};
