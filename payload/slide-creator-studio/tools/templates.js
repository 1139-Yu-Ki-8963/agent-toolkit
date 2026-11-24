#!/usr/bin/env node
'use strict';
// 使い方: node tools/templates.js <デザインシステムの名前> [--root <置き場>]
// 絞り込み: --brief で、型の名前と when だけ。--only <型の名前>[,<型の名前>…] で、その型だけ。
// 出力: テンプレートごとに、型の名前、when、使う部品、見本のデータ、schema の欄(欄の道筋、型、必須か、上限の値の名前と値)を、JSON で出す。
// スキルが、型を決めるときと、データを書くときに、テンプレートのファイルを全部読まずに済ませるための道具。値は持たない(tokens.json から読む)。
const fs = require('fs');
const path = require('path');
const lib = require('./lib');

// schema の欄を、道筋(items[].name など)ごとの 1 行に平らにする。
function flatten(defs, prefix, tokens, out) {
  for (const [k, def] of Object.entries(defs || {})) walk(def, prefix ? `${prefix}.${k}` : k, tokens, out);
  return out;
}
function walk(def, p, tokens, out) {
  const row = { path: p, type: def.type, required: !!def.required };
  if (def.type === 'image') row.shape = { src: '画像のファイルのパス(資料のフォルダからの相対パス、または ds:illustration/<名前>)', alt: '画像の代わりの文(空にしない)' };
  for (const key of ['maxChars', 'maxItems']) {
    if (def[key] === undefined) continue;
    const named = typeof def[key] !== 'number';
    const value = named ? lib.tokenValue(tokens, def[key]) : def[key];
    row[key] = { name: named ? def[key] : null, value: value === undefined ? null : value };
  }
  out.push(row);
  if (def.type === 'object') flatten(def.fields, p, tokens, out);
  if (def.type === 'list' && def.item) walk(def.item, p + '[]', tokens, out);
}

function main() {
  const opts = lib.parseArgs(process.argv.slice(2));
  const name = opts._[0];
  if (!name) throw new Error('使い方: node tools/templates.js <デザインシステムの名前>');
  const ds = lib.loadDesignSystem(lib.projectRoot(opts.root), name);
  const exdir = path.join(ds.dir, 'examples');
  const examples = fs.existsSync(exdir) ? fs.readdirSync(exdir).filter((f) => f.endsWith('.data.json')) : [];
  const only = typeof opts.only === 'string' ? opts.only.split(',') : null;
  if (only) for (const o of only) if (!ds.templates[o]) throw new Error(`テンプレートがない: ${o}`);
  const picked = Object.entries(ds.templates).filter(([tname]) => !only || only.includes(tname));
  const blocks = picked.map(([tname, t]) => {
    if (opts.brief) return `    ${JSON.stringify({ name: t.name || tname, when: t.when })}`;
    const fields = flatten(t.schema, '', ds.tokens, []);
    const ex = examples.filter((f) => { try { return lib.readJson(path.join(exdir, f)).template === tname; } catch (e) { return false; } });
    const head = JSON.stringify({ name: t.name || tname, when: t.when, parts: t.parts, examples: ex }).slice(0, -1);
    return `    ${head},\n     "fields": [\n${fields.map((f) => '       ' + JSON.stringify(f)).join(',\n')}]}`;
  });
  const errs = ds.templateErrors.map((e) => `${e.file}: ${e.message}`);
  process.stdout.write(`{\n  "designSystem": ${JSON.stringify(name)},\n  "templateErrors": ${JSON.stringify(errs)},\n  "templates": [\n${blocks.join(',\n')}\n  ]\n}\n`);
}

try { main(); } catch (e) { console.error(e.message); process.exit(1); }
