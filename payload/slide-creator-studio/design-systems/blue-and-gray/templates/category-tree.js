'use strict';
// 分け方の木(左の親から右の子へ、枝の線でつなぐ横向きの木)。見本: examples/category-tree.data.json
const makeParts = require('../parts');

module.exports = {
  name: 'category-tree',
  when: '元の資料が言う分け方(親の分類の下に子の分類があり、いちばん下の分類が項目を持つ)を、その分け方のまま見せる。分類の段は 3 つまで。左の列から右へ、親の分類、子の分類の順に名前を置き、親と子を枝の線でつなぐ(部品「分け方の枝」)。いちばん下の分類(葉)ごとに 1 行を取り、葉の名前の右の項目の列に、葉の説明の 1 行と、項目の名前を本文の字で左から右へ並べる。葉の名前と項目の列は、葉の線でつなぐ。原則「文を枠で区切っただけのスライドを置かない」の、階層を入れ子でなく枝の線で見せる図である。量を比べる中身は、この型でなく、量の比較の型にする。',
  parts: ['ラベル', '分け方の枝', '付録の番号'],
  schema: {
    label: { type: 'text' },
    labelRef: { type: 'text' },
    nodes: {
      type: 'list', required: true,
      item: {
        type: 'object',
        fields: {
          name: { type: 'text', required: true },
          parent: { type: 'text' },
          note: { type: 'text' },
          items: { type: 'list', item: { type: 'text' } },
        },
      },
    },
    aside: { type: 'text' },
  },
  render(data, tokens, h) {
    const P = makeParts(tokens, h);
    const { V, T, W, e, r2, px, roleW } = P;
    const c = data.content;
    const byName = new Map(c.nodes.map((n) => [n.name, n]));
    const depth = (n) => (n.parent ? depth(byName.get(n.parent)) + 1 : 0);
    for (const n of c.nodes) if (n.parent && !byName.has(n.parent)) throw new Error(`parent が nodes にない: ${n.parent}`);
    const maxDepth = Math.max(...c.nodes.map(depth));
    if (maxDepth + 1 > V('分け方の木の段の数の上限')) throw new Error('分類の段が、値「分け方の木の段の数の上限」を超える');
    // 名前の字の幅の見積もり。欧文の字(空白を除く)は値「分け方の木の欧文の字の幅の比」、空白はその半分、ほかの字は 1 字として、文字の大きさを掛ける。
    const nameW = (t) => [...t].reduce((s, ch) => s + (ch === ' ' ? V('分け方の木の欧文の字の幅の比') / 2 : /[\x21-\x7e]/.test(ch) ? V('分け方の木の欧文の字の幅の比') : 1), 0) * P.roleSize('図の中のカードの名前');   // 値でない: 空白は欧文の字の半分、ほかの字は 1 字
    // 段の列と列の間は、親の名前から縦の線までと、縦の線から子の名前までの、2 本の横の線が、どちらも名前との間(間隔.分け方の枝と名前)と、葉の線の長さの下限を持つ幅。
    const gapX = 2 * (V('間隔.分け方の枝と名前') + V('分け方の葉の線の長さの下限'));   // 値でない: 縦の線の左と右の 2 本
    const lineH = V('文字の行の高さ.本文'), rowGap = V('間隔.同じまとまりの部品と部品');
    const itemGap = V('間隔.同じまとまりの部品と部品');
    const labH = c.label ? V('文字の行の高さ.ラベル') + V('間隔.名前と、その中身') : 0;   // ラベルのない木は、ラベルの行を持たない
    // 段の列の幅は、その段の名前と、子を持つ分類の説明の、いちばん長い字の幅(材料から計算した値)。
    const colW = [];
    for (const n of c.nodes) {
      const d = depth(n);
      const isParent = c.nodes.some((m) => m.parent === n.name);
      const w = Math.max(nameW(n.name), isParent && n.note ? roleW('本文', n.note) : 0);
      colW[d] = Math.max(colW[d] || 0, w);
    }
    const xOf = (d) => colW.slice(0, d).reduce((s, w) => s + w + gapX, 0);   // 値でない: 前の段の列の幅と列の間を足す
    // 項目の列の左端は、いちばん下の段の列の右端から、名前と線の間、葉の線の長さの下限、線と項目の間を空けた所。
    const itemsX = xOf(maxDepth) + colW[maxDepth] + 2 * V('間隔.分け方の枝と名前') + V('分け方の葉の線の長さの下限');   // 値でない: 線の左右の 2 つの間
    const itemsW = W - itemsX;
    // 葉の行の高さ。説明の 1 行と、項目を左から右へ詰めた行の数(字の幅の見積もり)。
    const leaves = c.nodes.filter((n) => !c.nodes.some((m) => m.parent === n.name));
    let y = labH;
    const pos = new Map();
    for (const lf of leaves) {
      if (!lf.items || !lf.items.length) throw new Error(`葉の分類が項目を持たない: ${lf.name}`);
      let lines = 1, used = 0;
      for (const it of lf.items) {
        const w = roleW('本文', it);
        if (used && used + itemGap + w > itemsW) { lines++; used = w; } else used = used ? used + itemGap + w : w;
      }
      const textLines = (t) => (t ? Math.ceil(roleW('本文', t) / itemsW) : 0);
      const hgt = (lines + textLines(lf.note)) * lineH;
      pos.set(lf.name, { y, cy: y + lineH / 2, h: hgt });   // 値でない: 名前の行の中央
      y += hgt;
      // 次の葉の親が変わる所は、値「間隔.まとまりとまとまり」、同じ親の葉の間は、値「間隔.同じまとまりの部品と部品」。
      const nx = leaves[leaves.indexOf(lf) + 1];
      if (nx) y += nx.parent === lf.parent ? rowGap : V('間隔.まとまりとまとまり');
    }
    let figH = y;
    // 親の分類の位置。子の名前の行の中央の、いちばん上といちばん下の真ん中にそろえる。
    const place = (n) => {
      if (pos.has(n.name)) return pos.get(n.name);
      const kids = c.nodes.filter((m) => m.parent === n.name).map(place);
      const cy = (kids[0].cy + kids[kids.length - 1].cy) / 2;   // 値でない: 真ん中
      const p = { y: cy - lineH / 2, cy, kids };   // 値でない: 行の中央を、真ん中にそろえる
      pos.set(n.name, p);
      return p;
    };
    c.nodes.forEach(place);
    const lw = V('分け方の枝の線の太さ'), gap = V('間隔.分け方の枝と名前');
    let svg = '';
    const line = (d) => `<path d="${d}" fill="none" style="stroke:var(--sub)" stroke-width="${lw}"/>`;
    let html = '';
    for (const n of c.nodes) {
      const d = depth(n), p = pos.get(n.name);
      const nx = xOf(d);
      html += `<div ${T('図の中のカードの名前')} style="position:absolute;left:${px(nx)};top:${px(p.y)};padding-right:${px(gap)};background:var(--bg)">${e(n.name)}</div>`;
      if (p.kids) {
        // 親の名前の右から、列の間の真ん中まで横に出て、子の行の中央の高さで、子の名前の左へ入る。
        const x0 = nx, xm = xOf(d + 1) - gapX / 2, x1 = xOf(d + 1) - gap;   // 値でない: 列の間の真ん中
        const kids = c.nodes.filter((m) => m.parent === n.name).map((m) => pos.get(m.name));
        svg += line(`M${r2(x0)} ${r2(p.cy)}H${r2(xm)}`);
        svg += line(`M${r2(xm)} ${r2(kids[0].cy)}V${r2(kids[kids.length - 1].cy)}`);
        for (const k of kids) svg += line(`M${r2(xm)} ${r2(k.cy)}H${r2(x1)}`);
        if (n.note) html += `<div ${T('本文')} style="position:absolute;left:${px(nx)};top:${px(p.y + lineH)}">${e(n.note)}</div>`;
      } else {
        // 葉の名前の右から、項目の列の左まで、葉の線を引く。
        svg += line(`M${r2(nx)} ${r2(p.cy)}H${r2(itemsX - gap)}`);
        const note = n.note ? `<div ${T('本文', 'nt')}>${e(n.note)}</div>` : '';
        html += `<div class="ti" style="left:${px(itemsX)};top:${px(p.y)};width:${px(itemsW)}">${note}<div class="tw">${n.items.map((it) => `<span ${T('本文')}>${e(it)}</span>`).join('')}</div></div>`;
      }
    }
    // 分け方の外の補いの文。いちばん下の葉の名前の行の下に、段の列の左端から項目の列の手前までの幅で置く。
    if (c.aside) {
      const lastLeaf = pos.get(leaves[leaves.length - 1].name);
      const ay = lastLeaf.y + lineH + rowGap, aw = itemsX - V('間隔.まとまりとまとまり');
      const ah = Math.ceil(roleW('本文', c.aside) / aw) * lineH;
      html += `<div ${T('本文', 'as')} style="position:absolute;left:0;top:${px(ay)};width:${px(aw)}">${e(c.aside)}</div>`;
      figH = Math.max(figH, ay + ah);
    }
    const css = `.ct{position:relative}
.ct>[data-role]{white-space:nowrap}
.ct .ti{position:absolute}
.ct .ti>[data-role],.ct>.as{white-space:normal}
.ct .tw{display:flex;flex-wrap:wrap;column-gap:${itemGap}px}
.ct>svg{position:absolute;left:0;top:0}`;
    const body = `<div class="ct" style="width:${W}px;height:${px(figH)}">` + (c.label ? P.label(c.label, c.labelRef, 'position:absolute;left:0;top:0') : '') +
      `<svg data-part="分け方の枝" data-full-width width="${W}" height="${r2(figH)}" viewBox="0 0 ${W} ${r2(figH)}" aria-hidden="true">${svg}</svg>${html}</div>`;
    return { css, body };
  },
};
