'use strict';
// 次のアクション(日付の線と、アクションごとの点)。見本: examples/next-actions.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'next-actions',
  sectionFixed: '次のアクション',
  when: '相手に、いつまでに何を頼むかを言う。読者に求めるアクションの点を、大きい紫の点にし、ほかのアクションの点と見分ける。アクションは 3 つまで。点は、日付に比例した位置に置く。',
  parts: ['時間の線', '点', 'ラベル'],
  schema: {
    reader: { type: 'text', required: true },
    readerLabel: { type: 'text', required: true },
    actions: {
      type: 'list', required: true, maxItems: '次のアクションの点の数の上限',
      item: {
        type: 'object',
        fields: {
          who: { type: 'text', required: true },
          what: { type: 'text', required: true },
          date: { type: 'text', required: true },
          on: { type: 'text', required: true },
        },
      },
    },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, e, r2 } = P;
    const c = data.content;
    // 点の位置は、最初のアクションの日(on)からの日数で決める。表に出す言葉は date。
    // on は、YYYY-MM-DD か、YYYY-MM-W<n>(その月の第 n 週。月曜から始まる週で、その月の最初の月曜を含む週が第 1 週)。週だけが決まる期日は、その週の最初の日(月曜)に置く。
    const MS_PER_DAY = 86400000; // 値でない: 1 日のミリ秒の数(Date.UTC のミリ秒を、日の数にする)
    const dayNo = (on) => {
      const w = /^(\d{4})-(\d{2})-W([1-5])$/.exec(on);
      if (w) {
        const first = Date.UTC(Number(w[1]), Number(w[2]) - 1, 1) / MS_PER_DAY;
        const toMonday = (8 - new Date(first * MS_PER_DAY).getUTCDay()) % 7;
        return first + toMonday + 7 * (Number(w[3]) - 1);
      }
      const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(on);
      if (!m) throw new Error(`on が YYYY-MM-DD でも YYYY-MM-W<n> でもない: ${on}`);
      return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])) / MS_PER_DAY;
    };
    const day0 = dayNo(c.actions[0].on);
    const acts = c.actions.map((a) => ({ ...a, day: dayNo(a.on) - day0, reader: a.date === c.reader }));
    acts.forEach((a) => { a.d = V(a.reader ? '見てほしい点の直径' : '点の直径'); });
    const first = acts[0], last = acts[acts.length - 1];
    const sizeOf = (a) => (a.reader ? '次のアクションの読者の期日' : '次のアクションの期日');
    const lastW = Math.max(P.roleW('次のアクションの文', last.who), P.roleW('次のアクションの文', last.what), P.roleW(sizeOf(last), last.date));
    const spanD = last.day - first.day;
    const cx0 = first.d / 2;
    let day = V('時間の線の 1 日の長さの上限');
    if (spanD > 0) day = Math.min(day, Math.floor((W - lastW - cx0 + last.d / 2) / spanD));
    acts.forEach((a) => { a.cx = cx0 + (a.day - first.day) * day; a.left = a.cx - a.d / 2; });
    const tlH = V('時間の線の点の行の高さ');
    const reader = acts.find((a) => a.reader);
    const textH = (a) => V(`文字の行の高さ.${sizeOf(a)}`) + 2 * V('文字の行の高さ.次のアクションの文');
    const lbH = V('文字の行の高さ.ラベル');
    const toDate = V('間隔.ラベルと主な数字の行'); // 読者の期日は、主な数字の大きさの字
    const aboveH = reader ? lbH + toDate + textH(reader) : 0;
    const toText = V('間隔.時間の線と点の文字');
    const lineTop = reader ? aboveH + toText : 0;
    const belowTop = lineTop + tlH + toText;
    const belowH = Math.max(0, ...acts.filter((a) => !a.reader).map(textH));
    const total = belowTop + belowH;
    const block = (a) => `<div class="ac" style="left:${r2(a.left)}px;"><div ${T(sizeOf(a))}>${e(a.date)}</div>` +
      `<div ${T('次のアクションの文', a.reader ? 'f' : '')}>${e(a.who)}</div><div ${T('次のアクションの文', a.reader ? 'f' : '')}>${e(a.what)}</div></div>`;
    let html = P.timeline(acts.map((a) => ({ left: a.left, d: a.d, emphasis: a.reader })), W, { style: `left:0;top:${lineTop}px;position:absolute` });
    if (reader) {
      html += `<div ${T('ラベル')} data-part="ラベル" style="left:${r2(reader.left)}px;top:0">${e(c.readerLabel)}</div>`;
      html += block(reader).replace('<div class="ac" style="', `<div class="ac" style="top:${lbH + toDate}px;`);
    }
    for (const a of acts.filter((x) => !x.reader)) html += block(a).replace('<div class="ac" style="', `<div class="ac" style="top:${belowTop}px;`);
    return { css: `.ac .f{font-weight:${V('文字の太さ.次のアクションの読者の文')}}\n.ac [data-role]{display:block}`, body: `<div class="fg" style="width:${W}px;height:${total}px">${html}</div>` };
  },
};
