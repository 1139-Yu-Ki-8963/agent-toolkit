#!/usr/bin/env node
import { readFileSync } from "node:fs";
const F = process.argv[2];
let text;
try { if (process.argv.length !== 3) throw new Error(); text = readFileSync(F, "utf8"); } catch { console.error(`使い方: ${process.argv[1]} <SKILL.md のパス>`); process.exit(2); }
const lines = text.split("\n"); if (lines.at(-1) === "") lines.pop();
let n = 0;
const T = "「#### ── step <番号> の情報 ──」の入力と出力の文に含まれる名前と step の番号は、受け渡す値の表の「名前」「出す step」「使う step」と、最終出力の表の「名前」と一致する。", W = { 出力: "出す", 入力: "使う" };
const row = (l, d) => { console.log(`| この雛形で作るスキルが守ること | ${T} | ${F}:${l} | ${d} |`); n++; };
let R = [], E = 0;
function run(s) { R = []; E = 0; let g = false;
  for (let m; (m = s.match(/^[0-9]+-[0-9]+/));) { const p = m[0]; E += p.length; s = s.slice(p.length);
    if (g) { const a = R.at(-1).split("-"), b = p.split("-"); for (let i = Number(a[1]) + 1; i < Number(b[1]); i++) R.push(`${a[0]}-${i}`); }
    R.push(p); g = /^ から [0-9]/.test(s);
    const d = s.match(/^( から |、| と |と)[0-9]/); if (!d) break;
    E += d[0].length - 1; s = s.slice(d[0].length - 1); }
  return R.length; }
const TB = new Map(), M = new Map(), key = (kd, nm, st) => `${kd}\u001f${nm}\u001f${st}`;
function cell(x, kd, nm, NR) { x = x.replace(/[((][^))]*[))]/g, "").replace(/^ +/, ""); const k = run(x); for (let i = 0; i < k; i++) TB.set(key(kd, nm, R[i]), NR); }
let fe = "", it = false, io = false, cur = "", NR = 0; const N = [], O = [], L = [], LS = [], LK = [], LN = [];
for (const s of lines) { NR++;
  if (!fe && s.startsWith("```")) { fe = s.match(/^`+/)[0]; continue; }
  if (fe) { if (s === fe) fe = ""; continue; }
  if (s === "### 受け渡す値") { it = true; continue; }
  if (s === "### 最終出力") { io = true; continue; }
  if (s.startsWith("#")) { it = false; io = false; cur = ""; }
  if (io && s.startsWith("| ") && !s.startsWith("| 名前 |") && !s.startsWith("|-")) { const c = s.split(/ *\| */); if (!N.includes(c[1])) O.push(c[1]); }
  if (it && s.startsWith("| ") && !s.startsWith("| 名前 |") && !s.startsWith("|-")) { const c = s.split(/ *\| */); N.push(c[1]); cell(c[2], "出力", c[1], NR); cell(c[3], "入力", c[1], NR); }
  if (/^#### ── step [0-9]+-[0-9]+ の情報 ──$/.test(s)) cur = s.trim().split(/[ \t]+/)[3];
  if (cur !== "" && /^- (入力|出力): /.test(s)) { L.push(s); LS.push(cur); LK.push(s.slice(2, 4)); LN.push(NR); }
}
const bl = (x) => Buffer.byteLength(x, "utf8");
const A = N.concat(O.filter((o) => !N.includes(o)));
for (let i = 0; i < A.length; i++) for (let j = i + 1; j < A.length; j++) if (bl(A[j]) > bl(A[i])) { const t = A[i]; A[i] = A[j]; A[j] = t; }
for (let x = 0; x < L.length; x++) { let m = L[x]; const s = LS[x], k = LK[x], o = k === "入力" ? "出力" : "入力", P = {};
  for (const nm of A) { if (nm === "") continue; for (let p; (p = m.indexOf(nm)) !== -1;) { if (N.includes(nm)) { M.set(key(k, nm, s), LN[x]); P[p + 1] = nm; } m = m.slice(0, p) + "\u0001".repeat(nm.length) + m.slice(p + nm.length); } }
  for (let q = 0, p; (p = L[x].slice(q).indexOf("step ")) !== -1;) { const st = q + p + 1; q = st + 4; const h = run(L[x].slice(q)); let nm = "";
    if (L[x].substr(q + E, 2) === " で") { let b = 0; const zi = L[x].slice(q + E).indexOf("step "), z = zi !== -1 ? q + E + zi + 1 : L[x].length + 1;
      for (const p of Object.keys(P).map(Number)) if (p > q && p < z && (!b || p < b)) b = p; if (b) nm = P[b]; }
    else if (L[x].substr(st - 3, 2) === "を ") for (const p of Object.keys(P).map(Number)) if (p + P[p].length === st - 2) nm = P[p];
    for (let j = 0; nm !== "" && j < h; j++) if (!TB.has(key(o, nm, R[j]))) row(LN[x], `step ${s} の${k}の文の「${nm}」の step ${R[j]} が、受け渡す値の表の${W[o]} step にない`); } }
for (const [kk, l] of TB) if (!M.has(kk)) { const a = kk.split("\u001f"); row(l, `受け渡す値の表の「${a[1]}」の${W[a[0]]} step ${a[2]} の${a[0]}の文に、この名前がない`); }
for (const [kk, l] of M) if (!TB.has(kk)) { const a = kk.split("\u001f"); row(l, `step ${a[2]} の${a[0]}の文に「${a[1]}」があるが、受け渡す値の表の${W[a[0]]} step に ${a[2]} がない`); }
process.exit(n > 0 ? 1 : 0);
