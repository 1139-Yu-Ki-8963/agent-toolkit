#!/usr/bin/env node
'use strict';
// 使い方: node tools/render.js <資料のフォルダ> [--root <design-systems/ を持つ置き場>]
// deck.json と <名前>.data.json を読み、デザインシステムのテンプレートと frame.js を呼んで、
// <名前>.dc.html と canvas.json を資料のフォルダに書く。
// render.js の役目は、ファイルの読み書きと、テンプレートを選んで呼ぶことだけ。.dc.html の全体は frame.js が組む。
const fs = require('fs');
const path = require('path');
const lib = require('./lib');

function main() {
  const opts = lib.parseArgs(process.argv.slice(2));
  const deckDir = opts._[0] && path.resolve(opts._[0]);
  if (!deckDir) throw new Error('使い方: node tools/render.js <資料のフォルダ>');
  const root = lib.projectRoot(opts.root);
  const deck = lib.readJson(path.join(deckDir, 'deck.json'));
  const ds = lib.loadDesignSystem(root, deck.designSystem);
  if (typeof ds.frame !== 'function') throw new Error(`frame.js が関数を出していない: ${ds.dir}`);
  const h = lib.makeHelpers(ds.tokens, { baseDir: deckDir, dsDir: ds.dir });
  const boards = {};
  const order = [];
  deck.slides.forEach((name, i) => {
    const data = lib.readJson(path.join(deckDir, `${name}.data.json`));
    const tpl = ds.templates[data.template];
    if (!tpl) throw new Error(`${name}: テンプレートがない: ${data.template}`);
    const rendered = tpl.render(data, ds.tokens, h);
    const html = ds.frame(data, deck, ds.tokens, rendered);
    fs.writeFileSync(path.join(deckDir, `${name}.dc.html`), html);
    const file = `${name}.dc.html`;
    boards[file] = { x: i * 2000, y: 0, w: 1920, h: 1080, title: `${data.page} ${data.section}` };
    order.push(file);
  });
  const canvasPath = path.join(deckDir, 'canvas.json');
  let at = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
  if (fs.existsSync(canvasPath)) {
    try { at = lib.readJson(canvasPath).createdOnFiles.at || at; } catch (e) { /* 作り直す */ }
  }
  const canvas = {
    v: 3,
    createdOnFiles: { v: 1, at },
    title: deck.title,
    launch: { view: 'canvas' },
    pages: [],
    boards,
    order,
    notes: {},
    designSystems: [],
  };
  fs.writeFileSync(canvasPath, JSON.stringify(canvas, null, 2) + '\n');
  console.log(`書いた: ${order.length} 枚の .dc.html と canvas.json (${deckDir})`);
}

try { main(); } catch (e) { console.error(e.message); process.exit(1); }
