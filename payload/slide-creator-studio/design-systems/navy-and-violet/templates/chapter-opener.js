'use strict';
// 章扉(章の番号と章の名前を大きく置き、結論の一文の位置に、その章が答える質問を置く)。見本: examples/chapter-opener.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'chapter-opener',
  fullWidth: false,
  fullWidthWhy: '章扉は、役目の決まったスライドで、図を持たない。原則「図に本文領域の広さを使わせる」は、役目の決まったスライドを対象の外とする。',
  when: '資料の章の始まりを示す。資料の章が、値「章扉を付ける資料の章の数の下限」以上の資料で、章ごとに 1 枚置く。タイトル(section)に章の名前を、結論の一文(conclusion)に、その章が答える質問を 1 行で書く。原則「章扉に、章の名前と、章が答える質問を持たせる」に合わせ、ほかの中身は置かない。',
  parts: ['章の番号', '章の名前'],
  schema: {
    number: { type: 'text', required: true, maxChars: '章の番号の字数の上限' },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, e } = P;
    const B = V('間隔.まとまりとまとまり'); // まとまりとまとまりの間
    return {
      css: '',
      body: `<div style="display:flex;align-items:baseline;gap:${B}px">` +
        `<div ${T('一文のスライドの文')} data-part="章の番号" style="flex:none;color:var(--sub)">${e(data.content.number)}</div>` +
        `<div ${T('一文のスライドの文')} data-part="章の名前">${e(data.section)}</div></div>`,
    };
  },
};
