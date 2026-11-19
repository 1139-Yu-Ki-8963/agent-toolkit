#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, resolve, isAbsolute } from "node:path";
const A = process.argv.slice(2), ci = A.indexOf("--check"), oi = A.indexOf("--out"), CHECK = ci >= 0 ? A[ci + 1] : "", OUT = oi >= 0 ? A[oi + 1] : "", X = new Set([...(ci >= 0 ? [ci, ci + 1] : []), ...(oi >= 0 ? [oi, oi + 1] : [])]), P = A.filter((a, i) => !X.has(i));
const T = { "日本語の章の中身": { script: "ai-structure", kind: "構造", items: { "「目的:」の行の中身": ["LOW", "見つけやすさ", 5], "「## 使い方の例」の章の中身": ["LOW", "正しさ", 5], "ほかのスキルの文を写したままの章": ["LOW", "正しさ", 5] } }, "AI を乗っ取る書き方": { script: "ai-danger", kind: "危険", items: { "AI を乗っ取る書き方(前の指示を消す)": ["HIGH"], "AI を乗っ取る書き方(隠す)": ["HIGH"], "AI を乗っ取る書き方(外部へ送る)": ["HIGH"], "AI を乗っ取る書き方(秘密の値を読む)": ["HIGH"], "AI を乗っ取る書き方(守りを外す)": ["HIGH"], "AI を乗っ取る書き方(疑わしい)": ["MEDIUM"] } } };
if (!T[CHECK] || (oi >= 0 && !OUT) || P.length !== 2 || !existsSync(join(P[0], "SKILL.md"))) { console.error(`使い方: node save-ai-findings.mjs --check <${Object.keys(T).join("|")}> <調べるスキルのフォルダ> <AI が書いた判定の JSON のパス> [--out <指摘の JSON のパス>]`); process.exit(2); }
const C = T[CHECK], DIR = P[0], SEV = { HIGH: "重大", MEDIUM: "注意", LOW: "注意" }, KEYS = ["item", "file", "line", "message", "fix"];
let J;
try { J = JSON.parse(readFileSync(P[1], "utf8")); } catch (e) { console.error(`AI が書いた判定の JSON を読めない: ${e.message}`); process.exit(2); }
const bad = (r, i) => typeof r !== "object" || r === null || Array.isArray(r) ? `${i + 1} 件目が、項目を持つ形でない` : Object.keys(r).sort().join() !== [...KEYS].sort().join() ? `${i + 1} 件目の項目が「${KEYS.join("、")}」の 5 つでない` : !C.items[r.item] ? `${i + 1} 件目の項目の名前「${r.item}」が、検査「${CHECK}」の項目にない` : typeof r.file !== "string" || !r.file || isAbsolute(r.file) || r.file.split(/[\\/]/).includes("..") || !existsSync(join(DIR, r.file)) ? `${i + 1} 件目のファイル「${r.file}」が、調べるスキルのフォルダの中にあるファイルの相対パスでない` : !Number.isInteger(r.line) || r.line < 0 ? `${i + 1} 件目の行「${r.line}」が、0 以上の整数でない` : [r.message, r.fix].some(v => typeof v !== "string" || !v.trim()) ? `${i + 1} 件目の中身か直し方が、空でない文字列でない` : "";
const why = Array.isArray(J) ? J.map(bad).find(Boolean) : "JSON が配列でない";
if (why) { console.error(`AI が書いた判定の JSON の形が違う: ${why}。`); process.exit(2); }
const F = J.map(r => { const [src, dim = null, ded = 0] = C.items[r.item]; return { check: C.script, item: r.item, kind: C.kind, severity: SEV[src], source_severity: src, dimension: dim, deduction: ded, file: r.file, line: r.line, message: r.message, fix: r.fix }; });
try { const R = JSON.stringify({ script: C.script, target: resolve(DIR), status: "済み", findings: F }, null, 2) + "\n"; if (OUT) writeFileSync(OUT, R); else process.stdout.write(R); } catch (e) { console.error(`指摘の JSON を書けない: ${e.message}`); process.exit(2); }
process.exitCode = F.length ? 1 : 0;
