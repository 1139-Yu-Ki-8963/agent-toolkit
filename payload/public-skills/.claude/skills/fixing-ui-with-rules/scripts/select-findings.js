#!/usr/bin/env node
const fs = require("fs");
if (process.argv.length !== 4) { console.error("使い方: node select-findings.js <直す対象の json のパス> <返事の文>"); process.exit(2); }
const [jsonPath, reply] = process.argv.slice(2);
let list;
try { list = JSON.parse(fs.readFileSync(jsonPath, "utf8")); } catch { console.error(`json を読めない: ${jsonPath}`); process.exit(2); }
if (!Array.isArray(list) || list.some((e) => !e || !Number.isInteger(e.number))) { console.error(`json が番号を持つ指摘の配列でない: ${jsonPath}`); process.exit(2); }
const byNumber = new Map(list.map((e) => [e.number, e]));
const nums = (s) => [...s.matchAll(/(\d+)(?:\s*[~〜-]\s*(\d+))?/g)].flatMap((m) => (m[2] ? Array.from({ length: Math.max(0, m[2] - m[1] + 1) }, (_, i) => Number(m[1]) + i) : [Number(m[1])]));
const fix = new Set(), skip = new Map(), plans = {}, bad = [];
let all = false;
for (const raw of reply.normalize("NFKC").match(/(?:\([^)]*\)|[^。\n(])+/g) || []) {
  const s = raw.trim().replace(/(\d+)\s*は?\s*案\s*(\d+)/g, (_, n, k) => { plans[n] = Number(k); fix.add(Number(n)); return ""; });
  const no = s.match(/^(.*?)直さない\s*(?:\(([^)]*)\))?/);
  if (/全部|すべて|全て/.test(no ? no[1] : s) && /直/.test(s)) all = true;
  if (no) { const cut = no[1].lastIndexOf("直"); nums(no[1].slice(0, cut + 1)).forEach((n) => fix.add(n)); nums(no[1].slice(cut + 1)).forEach((n) => skip.set(n, (no[2] || "").trim())); }
  else if (/直/.test(s) || /^[\d\s、,~〜-]+$/.test(s)) nums(s).forEach((n) => fix.add(n));
  else if (/\d/.test(s)) bad.push(s);
}
if (!all && fix.size === 0 && skip.size === 0 && bad.length === 0) bad.push(reply);
if (all) list.forEach((e) => fix.add(e.number));
skip.forEach((_, n) => fix.delete(n));
const unknown = [...new Set([...fix, ...skip.keys(), ...Object.keys(plans).map(Number)])].filter((n) => !byNumber.has(n)).sort((a, b) => a - b);
for (const [n, k] of Object.entries(plans)) { const e = byNumber.get(Number(n)); if (e && fix.has(Number(n)) && (!Array.isArray(e.fix_after) || k < 1 || k > e.fix_after.length)) bad.push(`${n} は案 ${k}`); }
if (unknown.length) console.log(`一覧にない番号: ${unknown.join("、")}`);
if (bad.length) console.log(`読み取れない返事: ${bad.join("、")}`);
if (unknown.length || bad.length) process.exit(1);
const rank = (n) => (byNumber.get(n).weight === "直す" ? 0 : 1);
const out = { fix: [...fix].sort((a, b) => rank(a) - rank(b) || a - b), skip: [...skip].sort((a, b) => a[0] - b[0]).map(([number, reason]) => ({ number, reason })), plans: Object.fromEntries(Object.entries(plans).filter(([n]) => fix.has(Number(n)))) };
console.log(JSON.stringify(out));
