'use strict';
// 目次(資料の章の名前だけを、章の順に縦に並べる)。見本: examples/contents.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'contents',
  sectionFixed: '目次',
  fullWidth: false,
  fullWidthWhy: '目次は、役目の決まったスライドで、図を持たない。原則「図に本文領域の広さを使わせる」は、役目の決まったスライドを対象の外とする。',
  when: '資料の章の名前を、章の順に見せる。中身のスライドが、値「目次を付ける中身のスライドの枚数の下限」以上の資料に、1 枚だけ置く。原則「目次に、資料の章の名前だけを持たせる」に合わせ、章の番号と章の名前だけを置き、章の説明は置かない。',
  parts: ['章の番号', '章の名前'],
  schema: {
    chapters: { type: 'list', required: true, maxItems: '目次の章の数の上限', item: { type: 'text', maxChars: '目次の章の名前の字数の上限' } },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, e } = P;
    const B = V('間隔.まとまりとまとまり'); // まとまりとまとまりの間
    const numW = V('章の番号の列の幅');
    const rows = data.content.chapters.map((name, i) =>
      `<div style="display:flex;align-items:baseline;margin-top:${i ? B : 0}px">` +
      `<div ${T('まとめの資料の章の名前')} data-part="章の番号" style="flex:none;width:${numW}px;color:var(--sub)">${i + 1}</div>` +
      `<div ${T('まとめの資料の章の名前')} data-part="章の名前">${e(name)}</div></div>`);
    return { css: '', body: rows.join('') };
  },
};
