#!/usr/bin/env node
'use strict';
// 使い方: node tools/extract.js <.dc.html のファイル> [--out <フォルダ>]
// .dc.html の中に埋め込まれた、そのスライドの中身のデータ(frame.js が `<script type="application/json" data-slide-data>` で埋める)を取り出し、
// <名前>.data.json を書く。<名前> は、.dc.html のファイルの名前から `.dc.html` を除いたもの。--out を省くと、.dc.html と同じフォルダに書く。
// 埋め込みのない .dc.html(古い作りのスライド)は、メッセージを標準エラーに出して、終了コード 1 で終える。
const fs = require('fs');
const path = require('path');
const lib = require('./lib');

const NO_DATA = 'このスライドは、中身のデータを持たない。元の資料から作り直す';

function main() {
  const opts = lib.parseArgs(process.argv.slice(2));
  const file = opts._[0] && path.resolve(opts._[0]);
  if (!file) throw new Error('使い方: node tools/extract.js <.dc.html のファイル> [--out <フォルダ>]');
  if (!fs.existsSync(file)) throw new Error(`ファイルがない: ${file}`);
  if (!file.endsWith('.dc.html')) throw new Error(`.dc.html のファイルでない: ${file}`);
  const html = fs.readFileSync(file, 'utf8');
  const m = /<script\s+type="application\/json"\s+data-slide-data\s*>([\s\S]*?)<\/script>/.exec(html);
  if (!m) { console.error(NO_DATA); process.exit(1); }
  let data;
  try { data = JSON.parse(m[1]); } catch (e) { throw new Error(`埋め込みのデータを JSON として読めない: ${e.message}`); }
  const outDir = typeof opts.out === 'string' ? path.resolve(opts.out) : path.dirname(file);
  fs.mkdirSync(outDir, { recursive: true });
  const out = path.join(outDir, `${path.basename(file, '.dc.html')}.data.json`);
  fs.writeFileSync(out, JSON.stringify(data, null, 2) + '\n');
  console.log(`書いた: ${out}`);
}

try { main(); } catch (e) { console.error(e.message); process.exit(1); }
