#!/usr/bin/env node
'use strict';
// 使い方:
//   node tools/check.js <資料のフォルダ> [--measured <測った値の JSON>] [--root <置き場>] [--value-names <value-names.json>]
//   node tools/check.js --design-system <名前> [--root <置き場>] [--value-names <value-names.json>]
// 出力: {"ok": true|false, "errors": [{"slide", "check", "message"}]}。終了コード 合格 0、不合格 1。
// このファイルは、数値を持たない。値は、デザインシステムの tokens.json から読む。
// 値の名前の形(確かめに要る対応)は、次の定数だけが決める。
const fs = require('fs');
const path = require('path');
const lib = require('./lib');

const NAME = {
  fontMinPrefix: '文字の大きさの下限.',   // + data-role の名前
  contrastMinRole: 'コントラスト比の下限.', // + data-role の名前。なければ、次の名前
  contrastMin: 'コントラスト比の下限',
  conclusionLines: '結論の一文の行数の上限',
  emphasisCount: '強調の要素の数の上限',
  conclusionChars: '結論の一文の字数の上限', // value-names.json にあるときだけ確かめる
};
// データが持ってはいけない欄の名前(色、大きさ、位置、幅)
const FORBIDDEN_KEYS = new Set(['color', 'colour', 'background', 'bg', 'fill', 'stroke', 'fontSize', 'font-size', 'fontsize', 'size', 'width', 'height', 'x', 'y', 'left', 'top', 'right', 'bottom', 'position', 'style', 'css', 'class',
  '色', '背景', '文字の大きさ', '大きさ', '位置', '幅', '高さ']);
const COLOR_VALUE = /^(#[0-9a-fA-F]{3,8}|rgba?\(.*\)|hsla?\(.*\))$/;
const TOL = 1; // 測った値の許容(px)

function makeCtx(ds, namesList) {
  return { ds, tokens: ds.tokens, parts: new Set(ds.parts.map((p) => p.name)), namesList: namesList || [], names: namesList ? new Set(namesList.map((n) => n.name)) : null, errors: [] };
}
function err(ctx, slide, check, message) { ctx.errors.push({ slide, check, message }); }

// 値の名前から値を得る。値がないときは、不合格を記録して undefined を返す。
function requireValue(ctx, slide, check, name) {
  const v = lib.tokenValue(ctx.tokens, name);
  if (v === undefined) { err(ctx, slide, check, `値の名前「${name}」に、tokens.json の値がない`); return undefined; }
  return v;
}
function numValue(ctx, slide, check, name) {
  const v = requireValue(ctx, slide, check, name);
  if (v === undefined) return undefined;
  if (typeof v !== 'number') { err(ctx, slide, check, `値「${name}」が数でない: ${JSON.stringify(v)}`); return undefined; }
  return v;
}

// ---- 元の資料 ----
function norm(s) { return String(s).normalize('NFKC').replace(/[\s,，、]/g, ''); }
function sectionText(md, heading) {
  const lines = md.split(/\r?\n/);
  const want = heading.normalize('NFKC').trim();
  for (let i = 0; i < lines.length; i++) {
    const m = /^(#{1,6})\s+(.*?)\s*#*\s*$/.exec(lines[i]);
    if (!m || m[2].normalize('NFKC').trim() !== want) continue;
    const level = m[1].length;
    const out = [];
    for (let j = i + 1; j < lines.length; j++) {
      const n = /^(#{1,6})\s+/.exec(lines[j]);
      if (n && n[1].length <= level) break;
      out.push(lines[j]);
    }
    return out.join('\n');
  }
  return null;
}

// 表記の確かめ: 文字列の「数字と、その前後 2 字ずつ」の切れ端が、元の資料に、空白を外すと同じで、空白を外さないと違う並びだけであるとき、その切れ端を返す。
// 切れ端の前後 2 字は、空白でない字を数える。文字列の改行は、空白として外す。
function notationMismatches(text, source) {
  const s = String(text).replace(/\r?\n/g, '');
  const stripped = [], map = []; // 元の資料の、空白を外した文字列と、各字の元の位置
  for (let i = 0; i < source.length; i++) if (!/\s/.test(source[i])) { stripped.push(source[i]); map.push(i); }
  const flat = stripped.join('');
  const out = [];
  for (const m of s.matchAll(/\d+(?:[,.]\d+)*/g)) {
    let a = m.index, b = m.index + m[0].length;
    for (let k = 0; k < 2; k++) { while (a > 0 && /\s/.test(s[a - 1])) a--; if (a > 0) a--; }
    for (let k = 0; k < 2; k++) { while (b < s.length && /\s/.test(s[b])) b++; if (b < s.length) b++; }
    const piece = s.slice(a, b);
    const key = piece.replace(/\s/g, '');
    let found = false, exact = false;
    for (let at = flat.indexOf(key); at >= 0; at = flat.indexOf(key, at + 1)) {
      found = true;
      if (source.slice(map[at], map[at + key.length - 1] + 1) === piece) { exact = true; break; }
    }
    if (found && !exact) out.push(piece);
  }
  return out;
}

// ---- データの検査 ----
function checkData(ctx, slide, data, source) {
  const E = (check, msg) => err(ctx, slide, check, msg);
  const notation = (text, where) => {
    if (source === null || source === undefined || typeof text !== 'string') return;
    for (const piece of notationMismatches(text, source)) E('notation', `${where}: 「${piece}」が、元の資料と、空白の有無だけが違う`);
  };
  if (!data || typeof data !== 'object') return E('schema', 'データがオブジェクトでない');
  for (const k of ['template', 'section', 'page', 'conclusion']) {
    if (typeof data[k] !== 'string' || !data[k]) E('schema', `「${k}」が、空でない文字列でない`);
  }
  if (!Array.isArray(data.from) || !data.from.length || data.from.some((x) => typeof x !== 'string' || !x)) E('schema', '「from」が、見出しの文字列の配列でない');
  if (!data.content || typeof data.content !== 'object' || Array.isArray(data.content)) E('schema', '「content」がオブジェクトでない');

  // 色、大きさ、位置、幅を持たない
  (function scan(v, p) {
    if (Array.isArray(v)) v.forEach((x, i) => scan(x, `${p}[${i}]`));
    else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) {
      if (FORBIDDEN_KEYS.has(k)) E('data-no-style', `${p}.${k}: データが、色、大きさ、位置、幅の欄を持つ`);
      scan(x, `${p}.${k}`);
    } else if (typeof v === 'string' && COLOR_VALUE.test(v.trim())) E('data-no-style', `${p}: データが色の値を持つ: ${v}`);
  })(data, '$');

  // from の見出しが、元の資料にある
  if (source !== null && Array.isArray(data.from)) {
    for (const f of data.from) if (typeof f === 'string' && sectionText(source, f) === null) E('source-heading', `from の見出し「${f}」が、元の資料にない`);
  }

  // タイトル(section)が、元の資料にある語。テンプレートが sectionFixed(決まったタイトル)を持つときは、それと同じ。
  if (source !== null && typeof data.section === 'string' && data.section) {
    const fixed = ctx.ds.templates[data.template] && ctx.ds.templates[data.template].sectionFixed;
    if (typeof fixed === 'string') {
      if (data.section !== fixed) E('title-source', `タイトル「${data.section}」が、テンプレート ${data.template} の決まったタイトル「${fixed}」と違う`);
    } else {
      // タイトルは、元の資料の見出しと同じか、見出しの字数の 6 割以上を持つ、見出しの一部とする(見出しの端の数字だけを切り取らせない)。
      const sec = norm(data.section);
      const heads = source.split(/\r?\n/).map((l) => /^#{1,6}\s+(.*?)\s*#*\s*$/.exec(l)).filter(Boolean).map((m) => norm(m[1]));
      const hit = heads.some((h) => h === sec || (h.includes(sec) && sec.length >= h.length * 0.6));
      if (!hit) E('title-source', `タイトル「${data.section}」が、元の資料の見出しでない(見出しと同じか、見出しの字数の 6 割以上を持つ一部にする)`);
    }
  }

  // 結論の一文の数字が、from の見出しの節にある(導いた数を、手で書かせない)
  if (source !== null && typeof data.conclusion === 'string' && Array.isArray(data.from)) {
    const texts = data.from.map((f) => sectionText(source, f)).filter((t) => t !== null).map(norm);
    for (const m of data.conclusion.normalize('NFKC').matchAll(/\d[\d,]*(?:\.\d+)?/g)) {
      const num = m[0].replace(/,/g, '');
      const re = new RegExp('(?<![\\d.])' + num.replace('.', '\\.') + '(?![\\d])');
      if (texts.length && !texts.some((t) => re.test(t))) E('number-source', `結論の一文の数字「${m[0]}」が、出どころの見出し(${data.from.join('、')})の節にない`);
    }
  }

  notation(data.conclusion, '結論の一文');

  // 結論の一文の字数
  if (typeof data.conclusion === 'string' && ctx.names && ctx.names.has(NAME.conclusionChars)) {
    const max = numValue(ctx, slide, 'schema', NAME.conclusionChars);
    const n = lib.countChars(data.conclusion, ctx.ds);
    if (max !== undefined && n > max) E('char-limit', `結論の一文が ${n} 字で、上限 ${max} 字を超える`);
  }

  const tpl = ctx.ds.templates[data.template];
  if (!tpl) return E('schema', `テンプレートがない: ${data.template}`);
  for (const p of tpl.parts || []) if (!ctx.parts.has(p)) E('part-in-parts', `テンプレート ${tpl.name} の部品「${p}」が、parts.json にない`);
  if (!tpl.schema || typeof tpl.schema !== 'object') return E('schema', `テンプレート ${tpl.name} が schema を持たない`);
  if (!data.content || typeof data.content !== 'object') return;

  const quantityFrom = (q) => q.from ? [q.from] : (Array.isArray(data.from) ? data.from : []);
  function field(def, v, p) {
    if (v === undefined || v === null) return;
    switch (def.type) {
      case 'text':
        if (typeof v !== 'string' || !v) { E('schema', `${p}: 空でない文字列でない`); break; }
        notation(v, p);
        if (def.maxChars !== undefined) {
          const max = typeof def.maxChars === 'number' ? def.maxChars : numValue(ctx, slide, 'char-limit', def.maxChars);
          const n = lib.countChars(v, ctx.ds);
          if (max !== undefined && n > max) E('char-limit', `${p}: ${n} 字で、上限「${def.maxChars}」${max} 字を超える`);
        }
        break;
      case 'quantity': {
        if (!v || typeof v !== 'object' || Array.isArray(v)) { E('schema', `${p}: 量の欄(n, unit, approx, from)のオブジェクトでない`); break; }
        for (const k of Object.keys(v)) if (!['n', 'unit', 'approx', 'from'].includes(k)) E('schema', `${p}.${k}: 量の欄にない項目`);
        if (typeof v.n !== 'number' || !Number.isFinite(v.n)) E('schema', `${p}.n: 数でない`);
        if (typeof v.unit !== 'string' || !v.unit) E('schema', `${p}.unit: 空でない文字列でない`);
        if (v.approx !== undefined && typeof v.approx !== 'boolean') E('schema', `${p}.approx: 真偽でない`);
        if (typeof v.n === 'number' && typeof v.unit === 'string' && source !== null) {
          const heads = quantityFrom(v);
          const needle = norm(String(v.n) + v.unit);
          const texts = heads.map((h) => sectionText(source, h)).filter((t) => t !== null);
          if (!texts.length) E('number-source', `${p}: 出どころの見出し(${heads.join('、') || 'なし'})が、元の資料にない`);
          else if (!texts.some((t) => norm(t).includes(needle))) E('number-source', `${p}: 「${v.n}${v.unit}」が、出どころの見出し(${heads.join('、')})の節にない`);
        }
        break;
      }
      case 'image': {
        if (!v || typeof v !== 'object' || Array.isArray(v)) { E('schema', `${p}: 画像の欄(src, alt)のオブジェクトでない`); break; }
        for (const k of Object.keys(v)) if (!['src', 'alt'].includes(k)) E('schema', `${p}.${k}: 画像の欄にない項目`);
        if (typeof v.alt !== 'string' || !v.alt.trim()) E('schema', `${p}.alt: 空でない文字列でない(画像の代わりの文)`);
        if (typeof v.src !== 'string' || !v.src.trim()) { E('schema', `${p}.src: 空でない文字列でない(画像のファイルのパス)`); break; }
        try { lib.resolveImage(v.src, { baseDir: ctx.baseDir, dsDir: ctx.ds.dir }); } catch (e) { E('image', `${p}.src: ${e.message}`); }
        break;
      }
      case 'list': {
        if (!Array.isArray(v)) { E('schema', `${p}: 配列でない`); break; }
        if (def.maxItems !== undefined) {
          const max = typeof def.maxItems === 'number' ? def.maxItems : numValue(ctx, slide, 'item-limit', def.maxItems);
          if (max !== undefined && v.length > max) E('item-limit', `${p}: ${v.length} 個で、上限「${def.maxItems}」${max} 個を超える`);
        }
        if (def.item) v.forEach((x, i) => field(def.item, x, `${p}[${i}]`));
        break;
      }
      case 'object': {
        if (!v || typeof v !== 'object' || Array.isArray(v)) { E('schema', `${p}: オブジェクトでない`); break; }
        fields(def.fields || {}, v, p);
        break;
      }
      default: E('schema', `${p}: schema の type「${def.type}」を知らない`);
    }
  }
  function fields(defs, obj, p) {
    for (const [k, def] of Object.entries(defs)) {
      if (obj[k] === undefined || obj[k] === null) { if (def.required) E('schema', `${p}.${k}: 必須の欄がない`); continue; }
      field(def, obj[k], `${p}.${k}`);
    }
    for (const k of Object.keys(obj)) if (!(k in defs)) E('schema', `${p}.${k}: schema にない欄`);
  }
  fields(tpl.schema, data.content, 'content');
}

// ---- 描いた .dc.html の静的な検査 ----
function checkHtmlParts(ctx, slide, html) {
  for (const m of html.matchAll(/data-part="([^"]*)"/g)) {
    if (!ctx.parts.has(m[1])) err(ctx, slide, 'part-in-parts', `data-part「${m[1]}」が、parts.json にない`);
  }
}

// ---- 測った値の検査 ----
// 検査の式は lib.measuredErrors が持つ。測った値は、全部入り(elements を持つ)か、measure.js が返す短い形(errors を持つ)。
// exempt: テンプレートが fullWidth: false(図の幅の検査の対象の外)を持つか。
function checkMeasured(ctx, slide, m, exempt) {
  if (!m) return err(ctx, slide, 'measured', '測った値に、このスライドがない');
  let found;
  if (Array.isArray(m.errors)) {
    found = m.errors;
    if (!!m.fullWidthExempt !== exempt) err(ctx, slide, 'full-width', `測った値の fullWidthExempt(${!!m.fullWidthExempt})が、テンプレートの fullWidth: false の有無(${exempt})と違う`);
  } else found = lib.measuredErrors(Object.assign({}, m, { fullWidthExempt: exempt }), lib.buildLimits(ctx.tokens, ctx.namesList, ctx.ds.parts));
  for (const x of found) err(ctx, slide, x.check, x.message);
}

// 骨組みの要素の上端と左端。短い形は frame、全部入りの形は elements の data-part から読む。
function frameOf(m) {
  if (m.frame) return m.frame;
  const f = {};
  for (const e of m.elements || []) if (lib.FRAME_PARTS.includes(e.part) && !f[e.part] && e.box) f[e.part] = { top: e.box[1], left: e.box[0] };
  return f;
}
// 全スライドで、骨組みの要素の上端と左端が同じ(許容 TOL)。最初のスライドを基準にする。
function checkFramePosition(ctx, measuredSlides) {
  let base = null, baseName = null;
  for (const [name, m] of measuredSlides) {
    const f = frameOf(m);
    for (const part of lib.FRAME_PARTS) {
      if (!f[part]) { err(ctx, name, 'frame-position', `測った値に、骨組みの要素「${part}」の上端と左端がない`); continue; }
      if (!base) continue;
      const b = base[part];
      if (!b) continue;
      if (Math.abs(f[part].top - b.top) > TOL || Math.abs(f[part].left - b.left) > TOL) {
        err(ctx, name, 'frame-position', `骨組みの要素「${part}」の上端と左端 (${f[part].top}, ${f[part].left}) が、${baseName} の (${b.top}, ${b.left}) と違う`);
      }
    }
    if (!base) { base = f; baseName = name; }
  }
}

// ---- 資料の検査 ----
function loadNames(root, opts) {
  const p = opts['value-names'] ? path.resolve(opts['value-names']) : path.join(root, '.claude/rules/slide-writing/value-names.json');
  return { path: p, list: lib.readJson(p) };
}

function checkDeck(deckDir, opts) {
  const root = lib.projectRoot(opts.root);
  const deck = lib.readJson(path.join(deckDir, 'deck.json'));
  const errors0 = [];
  for (const k of ['title', 'designSystem', 'source']) if (typeof deck[k] !== 'string' || !deck[k]) errors0.push({ slide: 'deck', check: 'deck', message: `deck.json の「${k}」が、空でない文字列でない` });
  if (!Array.isArray(deck.slides) || !deck.slides.length) errors0.push({ slide: 'deck', check: 'deck', message: 'deck.json の「slides」が、空でない配列でない' });
  if (errors0.length) return errors0;
  const ds = lib.loadDesignSystem(root, deck.designSystem);
  const ctx = makeCtx(ds, loadNames(root, opts).list);
  ctx.baseDir = deckDir;
  ctx.errors.push(...ds.templateErrors.map((t) => ({ slide: 'deck', check: 'template-load', message: `${t.file}: ${t.message}` })));
  const srcPath = path.join(deckDir, deck.source);
  if (!fs.existsSync(srcPath)) err(ctx, 'deck', 'deck', `元の資料がない: ${srcPath}`);
  const source = fs.existsSync(srcPath) ? fs.readFileSync(srcPath, 'utf8') : null;
  const measured = opts.measured ? lib.readJson(path.resolve(opts.measured)) : null;
  const framed = [];
  for (const name of deck.slides) {
    const dp = path.join(deckDir, `${name}.data.json`);
    if (!fs.existsSync(dp)) { err(ctx, name, 'deck', `${name}.data.json がない`); continue; }
    let data;
    try { data = lib.readJson(dp); } catch (e) { err(ctx, name, 'schema', e.message); continue; }
    checkData(ctx, name, data, source);
    const hp = path.join(deckDir, `${name}.dc.html`);
    if (fs.existsSync(hp)) checkHtmlParts(ctx, name, fs.readFileSync(hp, 'utf8'));
    if (measured) {
      const m = (measured.slides || measured)[name];
      const tpl = ctx.ds.templates[data && data.template];
      checkMeasured(ctx, name, m, !!(tpl && tpl.fullWidth === false));
      if (m) framed.push([name, m]);
    }
  }
  if (measured) checkFramePosition(ctx, framed);
  return ctx.errors;
}

// ---- デザインシステムの検査 ----
function checkDesignSystem(name, opts) {
  const root = lib.projectRoot(opts.root);
  const tag = `design-system:${name}`;
  const ds = lib.loadDesignSystem(root, name);
  const names = loadNames(root, opts).list;
  const ctx = makeCtx(ds, names);
  const E = (check, msg, slide) => err(ctx, slide || tag, check, msg);
  // 値
  const values = ds.tokens.values || {};
  for (const n of names) {
    const e = values[n.name];
    if (!lib.hasValue(e)) E('values', `値の名前「${n.name}」に、tokens.json の values の値がない`);
    else if (typeof e.why !== 'string' || !e.why) E('values', `値「${n.name}」が、理由(why)を持たない`);
  }
  const nameSet = new Set(names.map((n) => n.name));
  for (const k of Object.keys(values)) if (!nameSet.has(k)) E('values', `values の「${k}」が、value-names.json にない(ない名前は local に置く)`);
  for (const [k, e] of Object.entries(ds.tokens.local || {})) {
    if (!lib.hasValue(e)) E('values', `local の「${k}」に値がない`);
    if (nameSet.has(k)) E('values', `local の「${k}」が、value-names.json にある名前(values に置く)`);
  }
  // 部品
  if (!Array.isArray(ds.parts)) E('parts', 'parts.json が配列でない');
  else {
    const seen = new Set();
    for (const p of ds.parts) {
      if (!p.name) E('parts', '名前のない部品がある');
      if (seen.has(p.name)) E('parts', `部品「${p.name}」が 2 回ある`);
      seen.add(p.name);
      if (typeof p.intent !== 'string' || !p.intent.trim()) E('parts', `部品「${p.name}」が、意図(intent)を持たない`);
    }
  }
  // テンプレート
  for (const t of ds.templateErrors) E('template', `${t.file}: 読めない: ${t.message}`);
  const examples = {};
  const edir = path.join(ds.dir, 'examples');
  const exFiles = fs.existsSync(edir) ? fs.readdirSync(edir).filter((f) => f.endsWith('.data.json')).sort() : [];
  for (const f of exFiles) {
    let d;
    try { d = lib.readJson(path.join(edir, f)); } catch (e) { E('example', e.message, `example:${f}`); continue; }
    (examples[d.template] = examples[d.template] || []).push({ f, d });
  }
  const exSrcPath = path.join(edir, '元の資料.md');
  const exSource = fs.existsSync(exSrcPath) ? fs.readFileSync(exSrcPath, 'utf8') : null;
  ctx.baseDir = edir;
  const h = lib.makeHelpers(ds.tokens, { baseDir: edir, dsDir: ds.dir });
  for (const [tname, tpl] of Object.entries(ds.templates)) {
    const T = `template:${tname}`;
    if (tpl.name !== tname) E('template', `name「${tpl.name}」が、ファイルの名前と違う`, T);
    if (typeof tpl.when !== 'string' || !tpl.when.trim()) E('template', 'when を持たない', T);
    if (!tpl.schema || typeof tpl.schema !== 'object') E('template', 'schema を持たない', T);
    if (!Array.isArray(tpl.parts)) E('template', 'parts が配列でない', T);
    else for (const p of tpl.parts) if (!ctx.parts.has(p)) E('template', `部品「${p}」が、parts.json にない`, T);
    if (typeof tpl.render !== 'function') E('template', 'render が関数でない', T);
    if (tpl.fullWidth === false && (typeof tpl.fullWidthWhy !== 'string' || !tpl.fullWidthWhy.trim())) E('full-width', 'fullWidth: false が、理由 fullWidthWhy(文字列)を持たない', T);
    if (tpl.fullWidth !== undefined && tpl.fullWidth !== false) E('full-width', 'fullWidth は false だけを持てる', T);
    (function walk(def) {
      if (!def || typeof def !== 'object') return;
      for (const k of ['maxChars', 'maxItems']) if (typeof def[k] === 'string' && !lib.hasValue(lib.tokenEntry(ds.tokens, def[k]))) E('template', `schema の ${k}「${def[k]}」に、tokens.json の値がない`, T);
      Object.values(def.fields || {}).forEach(walk);
      walk(def.item);
    })({ fields: tpl.schema });
    const list = examples[tname] || [];
    if (!list.length) E('example', 'examples に、見本のデータがない', T);
    for (const { f, d } of list) {
      const S = `example:${f}`;
      checkData(ctx, S, d, exSource);
      if (typeof tpl.render === 'function') {
        try {
          const out = tpl.render(d, ds.tokens, h);
          if (!out || typeof out.body !== 'string') E('example', 'render が { css, body } を返さない', S);
          else {
            checkHtmlParts(ctx, S, out.body);
            if (tpl.fullWidth !== false && !/data-full-width/.test(out.body)) E('full-width', `render の出力に data-full-width の要素がない(持たない型は、fullWidth: false と fullWidthWhy を持つ)`, S);
          }
        } catch (e) { E('example', `render が失敗: ${e.message}`, S); }
      }
    }
  }
  for (const t of Object.keys(examples)) if (!ds.templates[t]) for (const { f } of examples[t]) E('example', `見本のデータのテンプレート「${t}」がない`, `example:${f}`);
  checkCodeValues(ds, E);
  checkIntentValues(ds, E);
  checkPartsImplemented(ds, E);
  return ctx.errors;
}

// ---- コードに直に書いた見た目の数の検査(code-values) ----
// base.css: 文字の種類のクラス(.t-<文字の種類>)の大きさ、太さ、行の高さ、色は、tokens.json の「文字の大きさ.<文字の種類>」などと同じ値。
// そのほかの px の数は、直後のコメントに値の名前を持ち(`8px/*間隔.名前と、その中身*/`)、その値と同じ。
// 値から計算した数は、コメントに、値の名前を「 + 」「 - 」でつないだ式を持つ(`31px/*カードの左右の余白 - カードの枠線の太さ*/`)。色コードは、tokens.json の色の値のどれかと同じ。
// *.js(frame.js、parts.js、templates/*.js など): px の数、font-weight の数、色コード、計算に使う数を、直に書かない(値は V('<値の名前>') で引く)。
// 値でない数(2 で割って中央を出す、など)の行は、行のコメントに「値でない: <理由>」を持つ。
function allTokens(ds) { return Object.assign({}, ds.tokens.values || {}, ds.tokens.local || {}); }
function checkCodeValues(ds, E) {
  const all = allTokens(ds);
  const val = (n) => (lib.hasValue(all[n]) ? all[n].value : undefined);
  const colors = new Set(Object.values(all).map((e) => e && e.value).filter((v) => typeof v === 'string' && /^#[0-9a-fA-F]{3,8}$/.test(v)).map((v) => v.toUpperCase()));
  const cssPath = path.join(ds.dir, 'base.css');
  if (fs.existsSync(cssPath)) {
    const S = 'code:base.css';
    const css = fs.readFileSync(cssPath, 'utf8');
    for (const m of css.matchAll(/#[0-9a-fA-F]{3,8}\b/g)) if (!colors.has(m[0].toUpperCase())) E('code-values', `色コード ${m[0]} が、tokens.json の色の値にない`, S);
    for (const rule of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      const sel = rule[1].trim(), body = rule[2];
      const fine = /^\.t-([^\s{.:,>]+)$/.exec(sel);
      if (fine) {
        const want = { 'font-size': ['文字の大きさ.' + fine[1], 'px'], 'font-weight': ['文字の太さ.' + fine[1], ''], 'line-height': ['文字の行の高さ.' + fine[1], 'px'] };
        for (const [prop, [name, unit]] of Object.entries(want)) {
          const d = new RegExp('(?:^|;)\\s*' + prop + ':([^;]+)').exec(body);
          if (!d) continue;
          const v = val(name);
          if (v === undefined) E('code-values', `${sel} の ${prop} に当たる値「${name}」が、tokens.json にない`, S);
          else if (d[1].trim() !== `${v}${unit}`) E('code-values', `${sel} の ${prop}:${d[1].trim()} が、値「${name}」(${v}${unit})と違う`, S);
        }
        continue;
      }
      for (const m of body.matchAll(/(-?\d+(?:\.\d+)?)px(\/\*([^*]*)\*\/)?/g)) {
        const n = Number(m[1]);
        if (n === 0) continue;
        if (!m[3]) { E('code-values', `${sel} の ${m[1]}px が、値の名前のコメントを持たない`, S); continue; }
        let sum = 0, ok = true;
        for (const term of m[3].trim().split(/ (?=[+-] )/)) {
          const t = /^(?:([+-]) )?(.+)$/.exec(term.trim());
          const v = val(t[2].trim());
          if (typeof v !== 'number') { E('code-values', `${sel} の ${m[1]}px のコメントの値「${t[2].trim()}」が、tokens.json に数の値として、ない`, S); ok = false; break; }
          sum += t[1] === '-' ? -v : v;
        }
        if (ok && Math.abs(sum - n) > 1e-6) E('code-values', `${sel} の ${m[1]}px が、コメントの値「${m[3].trim()}」(${sum})と違う`, S);
      }
    }
  }
  const jsFiles = fs.readdirSync(ds.dir).filter((f) => f.endsWith('.js')).map((f) => f)
    .concat(fs.existsSync(path.join(ds.dir, 'templates')) ? fs.readdirSync(path.join(ds.dir, 'templates')).filter((f) => f.endsWith('.js')).map((f) => 'templates/' + f) : []).sort();
  for (const f of jsFiles) {
    const S = `code:${f}`;
    fs.readFileSync(path.join(ds.dir, f), 'utf8').split(/\r?\n/).forEach((line, i) => {
      if (/値でない: \S/.test(line)) return;
      const code = line.replace(/\/\/.*$/, '').replace(/\/\*.*?\*\//g, '').replace(/V\('[^']*'\)/g, 'V()');
      const at = `${i + 1} 行目`;
      for (const m of code.matchAll(/(?<![\w.${}])(\d+(?:\.\d+)?)px/g)) if (Number(m[1]) !== 0) E('code-values', `${at}: ${m[0]} を、直に書いている(値は V('<値の名前>') で引く)`, S);
      for (const m of code.matchAll(/font-weight:\s*(\d+)/g)) E('code-values', `${at}: ${m[0]} を、直に書いている(値は V('<値の名前>') で引く)`, S);
      for (const m of code.matchAll(/#[0-9a-fA-F]{6}\b/g)) E('code-values', `${at}: 色コード ${m[0]} を、直に書いている`, S);
      for (const m of code.matchAll(/(?:[-+*] ?(\d{2,}(?:\.\d+)?)(?![\w.]))|(?:(?<![\w.'"${\[,(])(\d{2,}(?:\.\d+)?) ?[-+*])/g)) E('code-values', `${at}: 計算に、数 ${m[1] || m[2]} を直に書いている(値は V('<値の名前>') で引く。値でない数は、行のコメントに「値でない: <理由>」を書く)`, S);
    });
  }
}

// ---- 意図の文が言う値の検査(intent-values) ----
// 部品の意図(intent)の文が言う px の数と色コードは、tokens.json の値にある(意図の文だけが持つ値を、作らせない)。
function checkIntentValues(ds, E) {
  if (!Array.isArray(ds.parts)) return;
  const all = Object.values(allTokens(ds));
  const px = new Set(all.filter((e) => e && typeof e.value === 'number' && e.unit === 'px').map((e) => e.value));
  const colors = new Set(all.map((e) => e && e.value).filter((v) => typeof v === 'string').map((v) => v.toUpperCase()));
  for (const p of ds.parts) {
    if (typeof p.intent !== 'string') continue;
    for (const m of p.intent.matchAll(/(\d+(?:\.\d+)?)px/g)) if (!px.has(Number(m[1]))) E('intent-values', `部品「${p.name}」の意図が言う ${m[0]} が、tokens.json の px の値にない`);
    for (const m of p.intent.matchAll(/#[0-9a-fA-F]{6}\b/g)) if (!colors.has(m[0].toUpperCase())) E('intent-values', `部品「${p.name}」の意図が言う ${m[0]} が、tokens.json の色の値にない`);
  }
}

// ---- 部品の実装の検査(part-implemented) ----
// parts.json の部品は、デザインシステムのコード(*.js、templates/*.js)のどれかが、data-part に書く。
// コードを持たない部品は、parts.json の項目に `"template": false`(まだテンプレートを持たない部品)を持つ。その部品の意図は、実装と照らしていない。
function checkPartsImplemented(ds, E) {
  if (!Array.isArray(ds.parts)) return;
  const files = fs.readdirSync(ds.dir).filter((f) => f.endsWith('.js')).map((f) => path.join(ds.dir, f))
    .concat(fs.existsSync(path.join(ds.dir, 'templates')) ? fs.readdirSync(path.join(ds.dir, 'templates')).filter((f) => f.endsWith('.js')).map((f) => path.join(ds.dir, 'templates', f)) : []);
  const src = files.map((f) => fs.readFileSync(f, 'utf8')).join('\n');
  for (const p of ds.parts) {
    const used = src.includes(`data-part="${p.name}"`);
    if (p.template === false && used) E('part-implemented', `部品「${p.name}」が、"template": false を持つのに、コードの data-part にある`);
    else if (p.template !== false && !used) E('part-implemented', `部品「${p.name}」が、コードのどの data-part にもない(テンプレートを持たない部品は、"template": false を持つ)`);
    if (p.template !== undefined && p.template !== false) E('part-implemented', `部品「${p.name}」の template は、false だけを持てる`);
  }
}

function main() {
  const opts = lib.parseArgs(process.argv.slice(2));
  let errors;
  try {
    if (opts['design-system']) errors = checkDesignSystem(opts['design-system'], opts);
    else if (opts._[0]) errors = checkDeck(path.resolve(opts._[0]), opts);
    else throw new Error('使い方: node tools/check.js <資料のフォルダ> [--measured <JSON>] | --design-system <名前>');
  } catch (e) {
    console.log(JSON.stringify({ ok: false, errors: [{ slide: '-', check: 'tool', message: e.message }] }, null, 2));
    process.exit(1);
  }
  console.log(JSON.stringify({ ok: errors.length === 0, errors }, null, 2));
  process.exit(errors.length ? 1 : 0);
}

main();
