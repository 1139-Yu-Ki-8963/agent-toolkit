#!/usr/bin/env node
'use strict';
// 使い方: node tools/measure.js <資料のフォルダ> [--root <置き場>] [--images <画像のフォルダ>]
// 描いた <名前>.dc.html を測るスクリプトの全文を、標準出力に出す。値(スライドの大きさ、下限の値、パス)は、埋まっている。
// AI は、出た全文を、Playwright の MCP のツール browser_run_code_unsafe の code に、そのまま渡す
// (ToolSearch で select:mcp__playwright__browser_run_code_unsafe を読み込む)。
// 返る JSON は、スライドごとの短いまとめと不合格の一覧。スクリプトが、同じ JSON を <資料のフォルダ>/測った値.json に自分で書く。
// node tools/check.js <資料のフォルダ> --measured <資料のフォルダ>/測った値.json に渡す。
// 画像は、<資料のフォルダ>/確認用の画像/<名前>.png に書く。
const fs = require('fs');
const path = require('path');
const lib = require('./lib');

function main() {
  const opts = lib.parseArgs(process.argv.slice(2));
  const deckDir = opts._[0] && path.resolve(opts._[0]);
  if (!deckDir) throw new Error('使い方: node tools/measure.js <資料のフォルダ>');
  const root = lib.projectRoot(opts.root);
  const deck = lib.readJson(path.join(deckDir, 'deck.json'));
  const ds = lib.loadDesignSystem(root, deck.designSystem);
  const namesPath = opts['value-names'] ? path.resolve(opts['value-names']) : path.join(root, '.claude/rules/slide-writing/value-names.json');
  const names = lib.readJson(namesPath);
  const imgDir = opts.images ? path.resolve(opts.images) : path.join(deckDir, '確認用の画像');
  fs.mkdirSync(imgDir, { recursive: true });
  const size = { width: lib.tokenValue(ds.tokens, 'スライドの幅'), height: lib.tokenValue(ds.tokens, 'スライドの高さ') };
  if (!(size.width > 0 && size.height > 0)) throw new Error('tokens.json に、値「スライドの幅」「スライドの高さ」がない');
  const slides = deck.slides.map((name) => {
    const src = path.join(deckDir, `${name}.dc.html`);
    if (!fs.existsSync(src)) throw new Error(`${name}.dc.html がない(先に node tools/render.js を回す)`);
    const dp = path.join(deckDir, `${name}.data.json`);
    const tpl = fs.existsSync(dp) ? ds.templates[lib.readJson(dp).template] : null;
    return { name, src, out: path.join(imgDir, `${name}.png`), fullWidthExempt: !!(tpl && tpl.fullWidth === false) };
  });
  const settings = { size, slides, limits: lib.buildLimits(ds.tokens, names, ds.parts), frameParts: lib.FRAME_PARTS, jsonPath: path.join(deckDir, '測った値.json') };
  let script = fs.readFileSync(path.join(__dirname, 'measure-page.js'), 'utf8');
  script = script.replace('/*SETTINGS*/ {}', () => JSON.stringify(settings));
  script = script.replace('/*MEASURED_ERRORS*/ null', () => lib.measuredErrors.toString());
  process.stdout.write(script);
}

try { main(); } catch (e) { console.error(e.message); process.exit(1); }
