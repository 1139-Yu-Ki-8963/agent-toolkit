#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
const A = process.argv.slice(2), oi = A.indexOf("--out"), OUT = oi >= 0 ? A[oi + 1] : "", DIR = A.find((a, i) => oi < 0 || (i !== oi && i !== oi + 1));
if (!DIR || (oi >= 0 && !OUT) || A.length !== (oi >= 0 ? 3 : 1) || !existsSync(join(DIR, "SKILL.md"))) { console.error("使い方: node find-duplicate-sections.mjs <調べるスキルのフォルダ> [--out <重複の候補の JSON のパス>]"); process.exit(2); } process.on("uncaughtException", e => { console.error(`調べられない: ${e.message}`); process.exit(2); });
const LINE = 0.6, MIN = 60, LIMIT = 30, TEXT = 2000, COMMON = "全スキル共通の決まり.md", INFO = /^── step .+ の情報 ──$/;
const rd = join(DIR, "references"), files = ["SKILL.md", ...(existsSync(rd) && statSync(rd).isDirectory() ? readdirSync(rd).filter(f => f.endsWith(".md") && f !== COMMON && statSync(join(rd, f)).isFile()).sort().map(f => "references/" + f) : [])];
const norm = t => t.normalize("NFKC").replace(/[\s\p{P}\p{S}]/gu, ""), secs = [];
for (const file of files) { let cur = null, fence = "", up = []; readFileSync(join(DIR, file), "utf8").split(/\r?\n/).forEach((s, i) => { const f = s.match(/^\s*(`{3,}|~{3,})/); if (fence) { if (f && f[1][0] === fence[0] && f[1].length >= fence.length) fence = ""; } else if (f) fence = f[1]; const h = !fence && !f && s.match(/^(#{1,6}) (.+?)\s*$/); if (h) { up = [...up.filter(x => x.lv < h[1].length), { lv: h[1].length, t: h[2] }]; if (h[1].length >= 2) { cur = { file, line: i + 1, heading: up.filter(x => x.lv >= 2).map(x => x.t).join(" > "), text: "" }; secs.push(cur); } else cur = null; } else if (cur) cur.text += s + "\n"; }); }
const S = secs.filter(s => !INFO.test(s.heading.split(" > ").pop()) && norm(s.text).length >= MIN).map(s => { const n = norm(s.text), g = new Map(); for (let i = 0; i + 3 <= n.length; i++) g.set(n.slice(i, i + 3), (g.get(n.slice(i, i + 3)) || 0) + 1); return { ...s, g }; });
const df = new Map(); S.forEach(s => s.g.forEach((_, k) => df.set(k, (df.get(k) || 0) + 1)));
S.forEach(s => { s.v = new Map(); let q = 0; s.g.forEach((c, k) => { const w = (1 + Math.log(c)) * Math.log((S.length + 1) / (df.get(k) + 1) + 1); s.v.set(k, w); q += w * w; }); s.n = Math.sqrt(q); });
const cos = (a, b) => { let d = 0; a.v.forEach((w, k) => { const u = b.v.get(k); if (u) d += w * u; }); return a.n && b.n ? d / (a.n * b.n) : 0; };
const P = []; for (let i = 0; i < S.length; i++) for (let j = i + 1; j < S.length; j++) { const c = cos(S[i], S[j]); if (c >= LINE) P.push([Math.round(c * 1000) / 1000, S[i], S[j]]); }
P.sort((x, y) => y[0] - x[0] || x[1].file.localeCompare(y[1].file) || x[1].line - y[1].line);
const part = s => ({ file: s.file, line: s.line, heading: s.heading, text: s.text.trim().slice(0, TEXT) }), pairs = P.slice(0, LIMIT).map(([similarity, a, b], i) => ({ id: `組${i + 1}`, similarity, a: part(a), b: part(b) }));
const status = P.length > LIMIT ? "調べきれなかった" : "済み";
try { const R = JSON.stringify({ script: "find-duplicate-sections", target: resolve(DIR), status, files, sections: S.length, line: LINE, limit: LIMIT, over_limit: Math.max(0, P.length - LIMIT), pairs }, null, 2) + "\n"; if (OUT) writeFileSync(OUT, R); else process.stdout.write(R); } catch (e) { console.error(`重複の候補の JSON を書けない: ${e.message}`); process.exit(2); }
if (OUT) console.log(`重複の候補: ${pairs.length} 件、状態: ${status}`);
process.exitCode = 0;
