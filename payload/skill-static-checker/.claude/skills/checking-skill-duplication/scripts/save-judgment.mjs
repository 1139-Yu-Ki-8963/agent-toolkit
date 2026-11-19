#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";
const A = process.argv.slice(2), DIR = A[0] || "";
if (A.length !== 1 || !existsSync(DIR) || !statSync(DIR).isDirectory()) { console.error("使い方: node save-judgment.mjs <一時フォルダのパス>"); process.exit(2); }
const item = x => x && typeof x === "object" && !Array.isArray(x) && ["id", "category", "reason"].every(k => typeof x[k] === "string"), list = a => Array.isArray(a) && a.every(item);
const parse = t => { const m = [...t.matchAll(/^[ \t]*```json[ \t]*\r?\n([\s\S]*?)^[ \t]*```[ \t]*\r?$/gm)]; if (m.length !== 1) return { error: m.length ? "json のコードブロックが 2 つ以上ある" : "json のコードブロックがない" }; let j; try { j = JSON.parse(m[0][1]); } catch (e) { return { error: `json のコードブロックを JSON として読めない(${e.message})` }; } if (!j || typeof j !== "object" || !list(j.sections) || !list(j.skills)) return { error: "sections と skills が、id、category、reason の文字列を持つ項目の配列でない" }; const pick = a => a.map(({ id, category, reason }) => ({ id, category, reason })); return { sections: pick(j.sections), skills: pick(j.skills) }; };
let bad = 0;
for (const n of [1, 2]) { let r; try { r = parse(readFileSync(join(DIR, `judge-${n}.txt`), "utf8")); writeFileSync(join(DIR, `judge-${n}.json`), JSON.stringify(r, null, 2) + "\n"); } catch (e) { console.error(`judge-${n}.txt を読めないか、judge-${n}.json を書けない: ${e.message}`); process.exit(2); } if (r.error) bad = 1; console.log(`judge-${n}.json: ${r.error ? `形と違う(${r.error})` : "形のとおり"}`); }
process.exitCode = bad;
