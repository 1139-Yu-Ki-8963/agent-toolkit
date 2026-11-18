#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, basename } from "node:path";
const A = process.argv.slice(2), oi = A.indexOf("--out"), OUT = oi >= 0 ? A[oi + 1] : "", DIR = A.find((a, i) => oi < 0 || (i !== oi && i !== oi + 1));
if (!DIR || (oi >= 0 && !OUT) || A.length !== (oi >= 0 ? 3 : 1) || !existsSync(DIR) || !statSync(DIR).isDirectory()) { console.error("使い方: node score.mjs <指摘の JSON のフォルダ> [--out <点数の JSON のパス>]"); process.exit(2); }
let R;
try { R = readdirSync(DIR).filter(f => f.endsWith(".json")).sort().map(f => JSON.parse(readFileSync(join(DIR, f), "utf8"))); } catch (e) { console.error(`指摘の JSON を読めない: ${e.message}`); process.exit(2); }
if (!R.length || R.some(r => typeof r.script !== "string" || !Array.isArray(r.findings))) { console.error("指摘の JSON が 1 つもないか、script と findings を持たない JSON がある。"); process.exit(2); }
const W = { 正しさ: 0.35, 見つけやすさ: 0.25, 信頼性: 0.25, 効率: 0.15 }, PASS = 70, KO = ["危険", "構造", "助言"], SO = ["重大", "注意", "参考"];
const all = R.flatMap(r => r.findings).sort((a, b) => KO.indexOf(a.kind) - KO.indexOf(b.kind) || SO.indexOf(a.severity) - SO.indexOf(b.severity) || String(a.file).localeCompare(String(b.file)) || (a.line || 0) - (b.line || 0));
const dims = Object.entries(W).map(([name, weight]) => { const ded = all.filter(f => f.kind === "構造" && f.dimension === name).reduce((s, f) => s + (Number(f.deduction) || 0), 0), score = Math.max(0, 100 - ded); return { name, weight, deduction: ded, score, weighted: Math.round(score * weight * 10) / 10 }; });
const total = Math.round(dims.reduce((s, d) => s + d.score * d.weight, 0) * 10) / 10, danger = all.filter(f => f.kind === "危険"), count = k => Object.fromEntries(SO.map(s => [s, all.filter(f => f.kind === k && f.severity === s).length]));
const target = R.map(r => r.target).find(Boolean) || "", out = { skill: basename(target), target, structure: { score: total, threshold: PASS, pass: total >= PASS, dimensions: dims, counts: count("構造") }, danger: { pass: !danger.some(f => f.severity === "重大"), counts: count("危険") }, advice: { counts: count("助言") }, checks: R.map(r => ({ script: r.script, status: r.status || "済み", findings: r.findings.length, ...(r.packages ? { packages: r.packages } : {}), ...(r.license !== undefined ? { license: r.license } : {}) })), metrics: R.flatMap(r => r.metrics || []), findings: all };
try { const S = JSON.stringify(out, null, 2) + "\n"; if (OUT) writeFileSync(OUT, S); else process.stdout.write(S); } catch (e) { console.error(`点数の JSON を書けない: ${e.message}`); process.exit(2); }
process.exitCode = all.length ? 1 : 0;
