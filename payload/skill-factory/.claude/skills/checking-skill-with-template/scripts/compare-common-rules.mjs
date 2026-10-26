#!/usr/bin/env node
import { readFileSync } from "node:fs";
const [T, C] = process.argv.slice(2);
let tpl, cpy;
try { if (process.argv.length !== 4) throw new Error(); tpl = readFileSync(T, "utf8"); cpy = readFileSync(C, "utf8"); } catch { console.error(`使い方: ${process.argv[1]} <雛形のパス> <全スキル共通の決まり.md のパス>`); process.exit(2); }
const split = (x) => { const a = x.split("\n"); if (a.at(-1) === "") a.pop(); return a; };
const tl = split(tpl), cl = split(cpy);
const s = tl.indexOf("## 全スキル共通の決まり"), e = tl.indexOf("## 雛形の本文", s + 1);
if (s === -1 || e === -1) { console.error(`雛形 ${T} に「## 全スキル共通の決まり」と「## 雛形の本文」の章がない`); process.exit(2); }
const b = tl.indexOf("````markdown", s), f = tl.indexOf("````", b + 1);
if (b === -1 || b > e || f === -1 || f > e) { console.error(`雛形 ${T} の「全スキル共通の決まり」の章にコードブロックがない`); process.exit(2); }
const want = tl.slice(b + 1, f);
let d = 0; while (d < want.length && d < cl.length && want[d] === cl[d]) d++;
if (d === want.length && d === cl.length) process.exit(0);
console.log(`| 全スキル共通の決まり | 章のコードブロックの中身 | ${C}:${d + 1} | 雛形の章と一字一句同じでない |`);
process.exit(1);
