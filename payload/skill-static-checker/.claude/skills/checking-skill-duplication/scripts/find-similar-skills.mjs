#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync, realpathSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
const A = process.argv.slice(2), oi = A.indexOf("--out"), ci = A.indexOf("--catalog"), OUT = oi >= 0 ? A[oi + 1] : "", CAT = ci >= 0 ? A[ci + 1] : "", X = [oi, ci].filter(i => i >= 0).flatMap(i => [i, i + 1]), DIR = A.find((a, i) => !X.includes(i));
if (!DIR || (oi >= 0 && !OUT) || (ci >= 0 && !CAT) || A.length !== 1 + (oi >= 0 ? 2 : 0) + (ci >= 0 ? 2 : 0) || !existsSync(join(DIR, "SKILL.md")) || (CAT && !(existsSync(CAT) && statSync(CAT).isDirectory()))) { console.error("使い方: node find-similar-skills.mjs <調べるスキルのフォルダ> [--catalog <比べるスキルの置き場>] [--out <似たスキルの JSON のパス>]"); process.exit(2); } process.on("uncaughtException", e => { console.error(`調べられない: ${e.message}`); process.exit(2); });
const LIMIT = 60, ROOT = resolve(CAT || dirname(resolve(DIR))), ME = realpathSync(DIR);
const meta = d => { const L = readFileSync(join(d, "SKILL.md"), "utf8").replace(/^\uFEFF/, "").split(/\r?\n/), e = L[0] === "---" ? L.indexOf("---", 1) : -1, H = L.slice(1, Math.max(e, 1)), fm = k => { const i = H.findIndex(s => s.startsWith(k + ":")), v = i < 0 ? "" : H[i].slice(k.length + 1).trim(); const b = []; for (const s of H.slice(i + 1)) { if (!/^\s/.test(s) && s.trim()) break; b.push(s.trim()); } if (/^[>|]/.test(v)) return /^[>|][1-9]?[+-]?[1-9]?$/.test(v) ? b.join(v[0] === ">" ? " " : "\n").trim() : ""; const w = [v, ...b].filter(Boolean).join(" "); if (/^["']/.test(w) && !/^"[^"]*"$|^'[^']*'$/.test(w)) return ""; return w.replace(/^"(.*)"$|^'(.*)'$/, "$1$2"); }; return { name: fm("name"), description: fm("description") }; };
const me = { folder: ME, ...meta(DIR) }, others = readdirSync(ROOT).sort().map(f => join(ROOT, f)).filter(p => existsSync(join(p, "SKILL.md")) && statSync(p).isDirectory() && realpathSync(p) !== ME).map(p => ({ folder: p, ...meta(p) }));
const norm = t => t.normalize("NFKC").replace(/[\s\p{P}\p{S}]/gu, ""), all = [me, ...others];
all.forEach(s => { const n = norm(s.name.replace(/-/g, " ") + s.description); s.g = new Map(); for (let i = 0; i + 3 <= n.length; i++) s.g.set(n.slice(i, i + 3), (s.g.get(n.slice(i, i + 3)) || 0) + 1); });
const df = new Map(); all.forEach(s => s.g.forEach((_, k) => df.set(k, (df.get(k) || 0) + 1)));
all.forEach(s => { s.v = new Map(); let q = 0; s.g.forEach((c, k) => { const w = (1 + Math.log(c)) * Math.log((all.length + 1) / (df.get(k) + 1) + 1); s.v.set(k, w); q += w * w; }); s.n = Math.sqrt(q); });
const cos = (a, b) => { let d = 0; a.v.forEach((w, k) => { const u = b.v.get(k); if (u) d += w * u; }); return a.n && b.n ? Math.round(d / (a.n * b.n) * 1000) / 1000 : 0; };
const ranked = others.map(s => ({ id: "", name: s.name, folder: s.folder, description: s.description, similarity: cos(me, s) })).sort((x, y) => y.similarity - x.similarity || x.name.localeCompare(y.name));
ranked.forEach((s, i) => { s.id = `スキル${i + 1}`; }); const bad = ranked.filter(s => !s.name || !s.description).map(s => s.folder);
const status = !me.description || ranked.length > LIMIT || bad.length ? "調べきれなかった" : ranked.length ? "済み" : "対象なし";
try { const R = JSON.stringify({ script: "find-similar-skills", target: ME, catalog: ROOT, status, unreadable: bad, name: me.name, description: me.description, limit: LIMIT, over_limit: Math.max(0, ranked.length - LIMIT), skills: ranked.slice(0, LIMIT) }, null, 2) + "\n"; if (OUT) writeFileSync(OUT, R); else process.stdout.write(R); } catch (e) { console.error(`似たスキルの JSON を書けない: ${e.message}`); process.exit(2); }
if (OUT) console.log(`比べるスキル: ${Math.min(ranked.length, LIMIT)} 本、状態: ${status}`);
process.exitCode = 0;
