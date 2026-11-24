'use strict';
// 画像と項目(画像 1 枚と、結論を支える短い項目を横に並べる)。見本: examples/image-and-points.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'image-and-points',
  when: '結論を、1 枚の画像(イラスト、図)と、それを支える短い項目(3 つまで)で言う。画像が、結論の場面か仕組みを見せ、項目が、その根拠を 1 つずつ言う。数字で比べる話は、グラフの型を使う。原則「画像を実寸以下で置く」に合わせ、画像を枠に収まるまで縮め、拡大しない。',
  parts: ['素材の画像', '画像と項目の項目'],
  schema: {
    image: { type: 'image', required: true },
    points: {
      type: 'list', required: true, maxItems: '画像と項目の項目の数の上限',
      item: {
        type: 'object',
        fields: {
          name: { type: 'text', required: true, maxChars: '画像と項目の項目の名前の字数の上限' },
          note: { type: 'text', maxChars: '画像と項目の項目の説明の字数の上限' },
        },
      },
    },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, W, px, r2, span } = P;
    const noteGap = V('間隔.画像と項目の名前と説明'), itemGap = V('間隔.画像と項目の項目と項目');
    const c = data.content;
    const boxW = V('画像と項目の画像の枠の幅'), boxH = V('画像と項目の画像の枠の高さ');
    const size = h.imageSize(c.image);
    if (!size) throw new Error(`画像の大きさを読めない: ${c.image.src}`);
    const scale = Math.min(boxW / size.w, boxH / size.h, 1); // 拡大しない
    const dw = size.w * scale, dh = size.h * scale;
    const nameH = V('文字の行の高さ.点の見出し'), noteH = V('文字の行の高さ.図の中の説明');
    const heights = c.points.map((p) => nameH + (p.note ? noteGap + noteH : 0));
    const colH = heights.reduce((a, b) => a + b, 0) + (c.points.length - 1) * itemGap;
    let html = h.image(c.image, `data-part="素材の画像" style="left:0;top:${r2((boxH - dh) / 2)}px;width:${px(dw)};height:${px(dh)}"`);
    let top = (boxH - colH) / 2;
    c.points.forEach((p, i) => {
      html += `<div data-part="画像と項目の項目" style="left:${boxW + V('間隔.画像と項目の列')}px;top:${r2(top)}px">${span('点の見出し', p.name)}` +
        (p.note ? span('図の中の説明', p.note, `style="margin-top:${noteGap}px"`) : '') + '</div>';
      top += heights[i] + itemGap;
    });
    return { css: '', body: `<div class="fg" data-full-width style="width:${W}px;height:${boxH}px">${html}</div>` };
  },
};
