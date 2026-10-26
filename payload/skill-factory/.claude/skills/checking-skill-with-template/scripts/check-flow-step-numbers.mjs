#!/usr/bin/env node
import { readFileSync } from "node:fs";
const F = process.argv[2];
let text;
try { if (process.argv.length !== 3) throw new Error(); text = readFileSync(F, "utf8"); } catch { console.error(`使い方: ${process.argv[1]} <SKILL.md のパス>`); process.exit(2); }
const lines = text.split("\n"); if (lines.at(-1) === "") lines.pop();
let n = 0;
const row = (l, t, d) => { console.log(`| この雛形で作るスキルが守ること | ${t} | ${F}:${l} | ${d} |`); n++; };
const A = "phase は 1 から、各 phase の step は 1 から空きなく並ぶ。", B = "流れの表、行き先、中止の文面の中の番号は、見出しの番号と一致する。";
let fe = "", fl = false, np, NR = 0; const fp = [], fr = [], fn = [], hl = {}, ns = {};
for (const s of lines) { NR++;
  if (!fe && s.startsWith("```")) { fe = s.match(/^`+/)[0]; continue; }
  if (fe) { if (s === fe) fe = ""; continue; }
  if (s === "### 流れ") { fl = true; continue; }
  if (s.startsWith("#")) fl = false;
  if (fl && /^\| [0-9]+ \|/.test(s)) { const c = s.split(/ *\| */); fp.push(c[1]); fr.push(c[3]); fn.push(NR); continue; }
  if (s.startsWith("## phase ")) { const p = s.trim().split(/[ \t]+/)[2]; if (Number(p) !== Number(np ?? 0) + 1) row(NR, A, `phase ${p} の前の phase が ${np ?? ""}`); np = p; hl[np] = NR; continue; }
  if (s.startsWith("### step ")) { const t = s.trim().split(/[ \t]+/)[2], sp = t.split("-"), k = ns[np] ?? 0; if (sp[0] !== String(np) || Number(sp[1]) !== k + 1) row(NR, A, `見出しの step ${t} が、並びでは step ${np ?? ""}-${k + 1} の位置にある`); ns[np] = Number(sp[1]); }
}
if (!fp.length) row(NR, B, "流れの表の行がない");
const ok = {};
for (let i = 0; i < fp.length; i++) { const p = fp[i]; ok[p] = 1; const w = (ns[p] ?? 0) > 1 ? `${p}-1 から ${p}-${ns[p]}` : `${p}-1`;
  if (!(p in hl)) row(fn[i], B, `phase ${p} の見出しがない`); else if (fr[i] !== w) row(fn[i], B, `流れの表の step は ${fr[i]}、見出しの step は ${w}`); }
for (const p in hl) if (!(p in ok)) row(hl[p], B, `phase ${p} の行が流れの表にない`);
process.exit(n > 0 ? 1 : 0);
