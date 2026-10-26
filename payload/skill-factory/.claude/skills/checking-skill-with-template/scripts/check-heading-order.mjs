#!/usr/bin/env node
import { readFileSync } from "node:fs";
const F = process.argv[2];
let text;
try { if (process.argv.length !== 3) throw new Error(); text = readFileSync(F, "utf8"); } catch { console.error(`使い方: ${process.argv[1]} <SKILL.md のパス>`); process.exit(2); }
const lines = text.split("\n"); if (lines.at(-1) === "") lines.pop();
let n = 0;
const row = (l, t, d) => { console.log(`| 雛形の本文 | ${t} | ${F}:${l} | ${d} |`); n++; };
const H = ["# <日本語名>", "## 全体像", "### 開始時の入力", "### 受け渡す値", "### 中間成果物", "### 最終出力", "### 流れ", "## 前提ツール", "## 使用するスクリプト", "## 使用するリファレンス"];
const X = { P: "### step <番号> <step の名前>", S: "#### ユーザーに見せる文面 か #### 手順", U: "#### 手順", T: "#### ── step <番号> の情報 ──", I: "### step <番号> <step の名前> か ## phase <番号> <名前>" };
let fm = false, fe = "", k = 0, st = "", cur = "", NR = 0;
for (const s of lines) { NR++;
  if (NR === 1 && s === "---") { fm = true; continue; }
  if (fm) { if (s === "---") fm = false; continue; }
  if (!fe && s.startsWith("```")) { fe = s.match(/^`+/)[0]; continue; }
  if (fe) { if (s === fe) fe = ""; continue; }
  if (!s.startsWith("#")) continue;
  if (k < H.length) { k++; if (k === 1 ? !/^# [^#]/.test(s) : s !== H[k - 1]) row(NR, H[k - 1], `「${s}」がある`); continue; }
  let y = "", ok = false; const f = s.trim().split(/[ \t]+/);
  if (/^## phase [0-9]+ /.test(s)) { y = "P"; ok = st === "I" || st === ""; }
  if (/^### step [0-9]+-[0-9]+ /.test(s)) { y = "S"; ok = st === "P" || st === "I"; cur = f[2]; }
  if (s === "#### ユーザーに見せる文面") { y = "U"; ok = st === "S"; }
  if (s === "#### 手順") { y = "T"; ok = st === "S" || st === "U"; }
  if (/^#### ── step [0-9]+-[0-9]+ の情報 ──$/.test(s)) { y = "I"; ok = st === "T" && f[3] === cur; }
  let w = st === "" ? "## phase 1 <名前>" : X[st]; if (st === "T") w = w.replace("<番号>", cur); if (!ok) row(NR, w, `「${s}」がある`); if (y) st = y;
}
if (k < H.length) row(NR, H[k], "見出しがない"); else if (st !== "I") row(NR, st === "" ? "## phase 1 <名前>" : X[st], "見出しがない");
process.exit(n > 0 ? 1 : 0);
