'use strict';
// render.js と check.js が共有する、ファイルの読み込みと小さな関数。値は持たない。
const fs = require('fs');
const path = require('path');

function readJson(p) {
  let text;
  try { text = fs.readFileSync(p, 'utf8'); } catch (e) { throw new Error(`ファイルを読めない: ${p}`); }
  try { return JSON.parse(text); } catch (e) { throw new Error(`JSON として読めない: ${p} (${e.message})`); }
}

// --root <dir> で、design-systems/ と .claude/rules/slide-writing/ を持つ置き場を替える。省くと、tools/ の 1 つ上。
function projectRoot(rootArg) {
  return rootArg ? path.resolve(rootArg) : path.resolve(__dirname, '..');
}

function loadDesignSystem(root, name) {
  const dir = path.resolve(root, 'design-systems', name);
  if (!fs.existsSync(dir)) throw new Error(`デザインシステムのフォルダがない: ${dir}`);
  const ds = { name, dir, tokens: null, parts: null, templates: {}, templateErrors: [], frame: null, countChars: null };
  ds.tokens = readJson(path.join(dir, 'tokens.json'));
  ds.parts = readJson(path.join(dir, 'parts.json'));
  const tdir = path.join(dir, 'templates');
  if (fs.existsSync(tdir)) {
    for (const f of fs.readdirSync(tdir).filter((x) => x.endsWith('.js')).sort()) {
      const p = path.join(tdir, f);
      try { delete require.cache[require.resolve(p)]; ds.templates[f.replace(/\.js$/, '')] = require(p); }
      catch (e) { ds.templateErrors.push({ file: f, message: e.message }); }
    }
  }
  const fp = path.join(dir, 'frame.js');
  if (fs.existsSync(fp)) {
    delete require.cache[require.resolve(fp)];
    const m = require(fp);
    ds.frame = typeof m === 'function' ? m : m.frame;
    ds.countChars = typeof m.countChars === 'function' ? m.countChars : null;
  }
  return ds;
}

// tokens.json の values か local から、値の名前の項目を返す。ないときは undefined。
function tokenEntry(tokens, name) {
  if (tokens.values && Object.prototype.hasOwnProperty.call(tokens.values, name)) return tokens.values[name];
  if (tokens.local && Object.prototype.hasOwnProperty.call(tokens.local, name)) return tokens.local[name];
  return undefined;
}
function hasValue(entry) {
  return entry !== undefined && entry !== null && entry.value !== undefined && entry.value !== null && entry.value !== '';
}
function tokenValue(tokens, name) {
  const e = tokenEntry(tokens, name);
  return hasValue(e) ? e.value : undefined;
}

function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// 桁区切りの文字は、値の名前「数の桁区切り」(values か local)が決める。ないときは区切らない。
const SEPARATOR_NAME = '数の桁区切り';
function formatQuantity(q, tokens) {
  const sep = tokens ? tokenValue(tokens, SEPARATOR_NAME) : undefined;
  let n = String(q.n);
  if (sep) {
    const [int, dec] = n.split('.');
    n = int.replace(/\B(?=(\d{3})+(?!\d))/g, sep) + (dec !== undefined ? '.' + dec : '');
  }
  return (q.approx ? '約' : '') + n + q.unit;
}

// 画像の欄(型 image)の src から、ファイルのパスを得る。`ds:<デザインシステムの中のパス>` は、デザインシステムのフォルダからの相対パス(素材は `ds:illustration/<名前>`)。
// それ以外は、資料のフォルダからの相対パス。置き場の外を指すパスは、エラーにする。
const IMAGE_TYPES = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.svg': 'image/svg+xml', '.webp': 'image/webp' };
function resolveImage(src, ctx) {
  if (typeof src !== 'string' || !src) throw new Error('画像の src が、空でない文字列でない');
  const ds = src.startsWith('ds:');
  const base = ds ? ctx && ctx.dsDir : ctx && ctx.baseDir;
  if (!base) throw new Error(`画像 ${src} の置き場が、決まっていない`);
  const file = path.resolve(base, ds ? src.slice(3) : src);
  if (path.relative(base, file).startsWith('..') || path.isAbsolute(ds ? src.slice(3) : src)) throw new Error(`画像 ${src} が、置き場の外を指している`);
  const mime = IMAGE_TYPES[path.extname(file).toLowerCase()];
  if (!mime) throw new Error(`画像 ${src} の拡張子が、${Object.keys(IMAGE_TYPES).join(' ')} のどれでもない`);
  if (!fs.existsSync(file)) throw new Error(`画像のファイルがない: ${file}`);
  return { file, mime };
}
// 画像の元の大きさ(px)。png、gif、jpeg は、ファイルの頭から読み、svg は、width と height か viewBox から読む。読めないときは null。
function imageSize(file, mime) {
  const b = fs.readFileSync(file);
  if (mime === 'image/png' && b.length > 24) return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
  if (mime === 'image/gif' && b.length > 10) return { w: b.readUInt16LE(6), h: b.readUInt16LE(8) };
  if (mime === 'image/jpeg') {
    for (let i = 2; i + 9 < b.length;) {
      if (b[i] !== 0xFF) { i++; continue; }
      const m = b[i + 1];
      if (m >= 0xC0 && m <= 0xCF && m !== 0xC4 && m !== 0xC8 && m !== 0xCC) return { h: b.readUInt16BE(i + 5), w: b.readUInt16BE(i + 7) };
      i += 2 + b.readUInt16BE(i + 2);
    }
  }
  if (mime === 'image/svg+xml') {
    const tag = /<svg\b[^>]*>/i.exec(b.toString('utf8'));
    if (tag) {
      const num = (n) => { const m = new RegExp(`\\s${n}="([\\d.]+)(?:px)?"`).exec(tag[0]); return m ? parseFloat(m[1]) : null; };
      const w = num('width'), hh = num('height');
      if (w && hh) return { w, h: hh };
      const vb = /viewBox="[\d.\-]+[ ,]+[\d.\-]+[ ,]+([\d.]+)[ ,]+([\d.]+)"/.exec(tag[0]);
      if (vb) return { w: parseFloat(vb[1]), h: parseFloat(vb[2]) };
    }
  }
  return null;
}
// 画像の欄 {src, alt} を、data URI(base64)の <img> の HTML にする。.dc.html は、外のファイルを指さない。attrs は、<img> に足す属性の文字列。
function imageHtml(img, ctx, attrs) {
  const { file, mime } = resolveImage(img && img.src, ctx);
  const uri = `data:${mime};base64,${fs.readFileSync(file).toString('base64')}`;
  return `<img src="${uri}" alt="${esc(img.alt)}"${attrs ? ' ' + attrs : ''}>`;
}

// ctx: { baseDir: 資料のフォルダ(画像の相対パスの基準), dsDir: デザインシステムのフォルダ(`ds:` の基準) }。画像を使わないときは省ける。
function makeHelpers(tokens, ctx) {
  return {
    esc, quantity: (q) => formatQuantity(q, tokens), value: (name) => tokenValue(tokens, name),
    image: (img, attrs) => imageHtml(img, ctx, attrs),
    imageSize: (img) => { const { file, mime } = resolveImage(img && img.src, ctx); return imageSize(file, mime); },
  };
}

function parseArgs(argv) {
  const opts = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const k = a.slice(2);
      const next = argv[i + 1];
      if (next !== undefined && !next.startsWith('--')) { opts[k] = next; i++; } else opts[k] = true;
    } else opts._.push(a);
  }
  return opts;
}

module.exports = { resolveImage, imageSize, imageHtml, readJson, projectRoot, loadDesignSystem, tokenEntry, hasValue, tokenValue, esc, formatQuantity, makeHelpers, parseArgs, SEPARATOR_NAME };

// ---- 測った値の検査(自己完結の関数。measure.js が、この関数の文字列を、ブラウザの中のスクリプトに埋めて使う) ----
// m: 1 枚分の測った値。limits: buildLimits が作る、値の名前と値の対。値を持たない対は、value が undefined。
function measuredErrors(m, limits) {
  var TOL = 1; // 測った値の許容(px)。デザインシステムの値ではない
  var errs = [];
  var E = function (check, message) { errs.push({ check: check, message: message }); };
  var parseColor = function (s) {
    var r = /rgba?\(\s*([\d.]+)[ ,]+([\d.]+)[ ,]+([\d.]+)(?:[ ,/]+([\d.]+%?))?\s*\)/.exec(s || '');
    if (!r) return null;
    var a = r[4] === undefined ? 1 : (r[4].slice(-1) === '%' ? parseFloat(r[4]) / 100 : parseFloat(r[4]));
    return { r: +r[1], g: +r[2], b: +r[3], a: a };
  };
  var lum = function (c) {
    var f = function (v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
    return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
  };
  var contrast = function (fg, bg) {
    var f = parseColor(fg), b = parseColor(bg);
    if (!f || !b) return null;
    var fc = { r: f.r * f.a + b.r * (1 - f.a), g: f.g * f.a + b.g * (1 - f.a), b: f.b * f.a + b.b * (1 - f.a) };
    var l = [lum(fc), lum(b)].sort(function (x, y) { return y - x; });
    return (l[0] + 0.05) / (l[1] + 0.05);
  };
  var inside = function (i, o) { return i[0] >= o[0] - TOL && i[1] >= o[1] - TOL && i[2] <= o[2] + TOL && i[3] <= o[3] + TOL; };
  var label = function (e) { return (e.role || e.part || e.tag) + '「' + (e.text || '').slice(0, 20) + '」'; };
  var need = function (check, entry, fallbackName) {
    // 値を返す。ないときは、不合格を記録して undefined
    if (!entry || entry.value === undefined || entry.value === null) { E(check, '値の名前「' + (entry ? entry.name : fallbackName) + '」に、tokens.json の値がない'); return undefined; }
    return entry.value;
  };
  var parts = {};
  (limits.parts || []).forEach(function (p) { parts[p] = true; });
  var els = m.elements || [];
  var fontMin = {}, contrastMin = {};
  els.forEach(function (e) {
    if (e.part && !parts[e.part]) E('part-in-parts', 'data-part「' + e.part + '」が、parts.json にない');
    if (e.role) {
      if (!(e.role in fontMin)) {
        var ent = limits.fontMin[e.role];
        if (!ent) { E('font-size', '文字の種類「' + e.role + '」に、下限の値の名前がない'); fontMin[e.role] = undefined; }
        else fontMin[e.role] = need('font-size', ent);
      }
      if (fontMin[e.role] !== undefined && e.fontSize < fontMin[e.role]) E('font-size', label(e) + ': 文字の大きさ ' + e.fontSize + 'px が、下限 ' + fontMin[e.role] + 'px 未満');
      if (e.text) {
        if (!(e.role in contrastMin)) {
          var r = limits.contrastRole[e.role];
          contrastMin[e.role] = r && r.value !== undefined ? r.value : need('contrast', limits.contrast);
        }
        var c = contrast(e.color, e.bg);
        if (c === null) E('contrast', label(e) + ': 色を読めない(' + e.color + ' / ' + e.bg + ')');
        else if (contrastMin[e.role] !== undefined && c < contrastMin[e.role]) E('contrast', label(e) + ': コントラスト比 ' + c.toFixed(2) + ' が、下限 ' + contrastMin[e.role] + ' 未満');
      }
    }
    if (m.root && !inside(e.box, m.root)) E('bounds', label(e) + ': スライドからはみ出す [' + e.box + ']');
    if (e.inBody && m.body && !inside(e.box, m.body)) E('bounds', label(e) + ': 本文領域からはみ出す [' + e.box + ']');
    // 字の箱は、行の箱(行の高さの箱)。要素の箱の外に出た行があれば、あふれる
    if (e.textBox && !inside(e.textBox, e.box)) E('overflow', label(e) + ': 文字が箱からあふれる 文字[' + e.textBox + '] 箱[' + e.box + ']');
  });
  var texts = els.filter(function (e) { return e.role && e.textBox; });
  for (var i = 0; i < texts.length; i++) for (var j = i + 1; j < texts.length; j++) {
    var a = texts[i], b = texts[j];
    if ((a.ancestors || []).indexOf(b.id) >= 0 || (b.ancestors || []).indexOf(a.id) >= 0) continue;
    var w = Math.min(a.textBox[2], b.textBox[2]) - Math.max(a.textBox[0], b.textBox[0]);
    var h = Math.min(a.textBox[3], b.textBox[3]) - Math.max(a.textBox[1], b.textBox[1]);
    if (w > TOL && h > TOL) E('overlap', label(a) + ' と ' + label(b) + ' が重なる');
  }
  // 図の幅: data-full-width の要素は、左端が本文領域の左端、右端が本文領域の右端にそろう。対象の外のテンプレート(fullWidthExempt)は確かめない。
  if (!m.fullWidthExempt) {
    var fw = m.fullWidth || [];
    if (!fw.length) E('full-width', 'data-full-width の要素が、1 つもない');
    else if (!m.body) E('full-width', '測った値に、本文領域(クラス bd)がない');
    else fw.forEach(function (b, k) {
      if (Math.abs(b[0] - m.body[0]) > TOL || Math.abs(b[2] - m.body[2]) > TOL) E('full-width', 'data-full-width の ' + (k + 1) + ' つ目が、本文領域の幅いっぱいでない 左右[' + b[0] + ', ' + b[2] + '] 本文領域[' + m.body[0] + ', ' + m.body[2] + ']');
    });
  }
  if (m.conclusion) {
    var max = need('conclusion-lines', limits.conclusionLines);
    if (max !== undefined && m.conclusion.lines > max) E('conclusion-lines', '結論の一文が ' + m.conclusion.lines + ' 行で、上限 ' + max + ' 行を超える');
  } else E('conclusion-lines', '測った値に、結論の一文(クラス cc)がない');
  var emax = need('emphasis-count', limits.emphasisMax);
  if (emax !== undefined && m.emphasisCount > emax) E('emphasis-count', '強調の要素が ' + m.emphasisCount + ' 個で、上限 ' + emax + ' 個を超える');
  return errs;
}

// ページの骨組みの要素(data-part の名前)。全スライドで、上端と左端が同じになる。
const FRAME_PARTS = ['資料の名前とタイトル', '結論の一文', 'ページ番号', '本文領域'];

const LIMIT_NAMES = {
  fontMinPrefix: '文字の大きさの下限.',
  contrastRolePrefix: 'コントラスト比の下限.',
  contrast: 'コントラスト比の下限',
  conclusionLines: '結論の一文の行数の上限',
  emphasisCount: '強調の要素の数の上限',
  conclusionChars: '結論の一文の字数の上限',
  halfWidth: '数字の半角の幅(字の大きさに対する比)',
};

// value-names.json の名前の一覧と tokens.json から、測った値の検査に渡す値を作る。
function buildLimits(tokens, namesList, parts) {
  const pair = (name) => ({ name, value: tokenValue(tokens, name) });
  const names = namesList.map((n) => n.name);
  const byPrefix = (prefix) => Object.fromEntries(names.filter((n) => n.startsWith(prefix)).map((n) => [n.slice(prefix.length), pair(n)]));
  return {
    parts: parts.map((p) => p.name),
    fontMin: byPrefix(LIMIT_NAMES.fontMinPrefix),
    contrastRole: byPrefix(LIMIT_NAMES.contrastRolePrefix),
    contrast: pair(LIMIT_NAMES.contrast),
    conclusionLines: pair(LIMIT_NAMES.conclusionLines),
    emphasisMax: pair(LIMIT_NAMES.emphasisCount),
  };
}

// 字数の数え方。デザインシステムの frame.js が countChars(text, tokens) を出していれば、それを呼ぶ。
// なければ、改行を数えず、半角の英数字を、値「数字の半角の幅(字の大きさに対する比)」の字として数える(値がなければ 1 字)。
function countChars(text, ds) {
  if (ds.countChars) return ds.countChars(text, ds.tokens);
  const half = tokenValue(ds.tokens, LIMIT_NAMES.halfWidth);
  let n = 0;
  for (const ch of String(text).replace(/\r?\n/g, '')) n += (half !== undefined && /[0-9A-Za-z]/.test(ch)) ? half : 1;
  return Math.round(n * 1000) / 1000;
}

module.exports.measuredErrors = measuredErrors;
module.exports.buildLimits = buildLimits;
module.exports.countChars = countChars;
module.exports.LIMIT_NAMES = LIMIT_NAMES;
module.exports.FRAME_PARTS = FRAME_PARTS;
