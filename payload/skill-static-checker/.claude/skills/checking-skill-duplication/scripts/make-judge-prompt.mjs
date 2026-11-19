#!/usr/bin/env node
import { readFileSync, existsSync, statSync } from "node:fs";
import { join, dirname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
const A = process.argv.slice(2), DIR = A[0] || "", REF = join(dirname(fileURLToPath(import.meta.url)), "..", "references", "判定者への指示文.md");
if (A.length !== 1 || !existsSync(DIR) || !statSync(DIR).isDirectory()) { console.error("使い方: node make-judge-prompt.mjs <一時フォルダのパス>"); process.exit(2); }
const slash = p => resolve(p).split(sep).join("/"), dup = slash(join(DIR, "duplicate-sections.json")), sim = slash(join(DIR, "similar-skills.json"));
let C, K, L;
try { C = JSON.parse(readFileSync(dup, "utf8")); K = JSON.parse(readFileSync(sim, "utf8")); L = readFileSync(REF, "utf8").split(/\r?\n/); if (!C.target || !K.catalog) throw new Error("target か catalog を持たない"); } catch (e) { console.error(`候補の JSON か指示文のリファレンスを読めない: ${e.message}`); process.exit(2); }
const h = L.findIndex(s => s.trim() === "### 指示文"), o = L.findIndex((s, i) => i > h && /^```text\s*$/.test(s)), c = L.findIndex((s, i) => i > o && /^```\s*$/.test(s));
const V = { "<調べるスキルのフォルダ>": slash(C.target), "<比べるスキルの置き場>": slash(K.catalog), "<重複の候補の JSON のパス>": dup, "<似たスキルの JSON のパス>": sim }, body = h < 0 || o < 0 || c < 0 ? "" : L.slice(o + 1, c).join("\n");
if (!body || Object.keys(V).some(k => !body.includes(k))) { console.error("指示文のリファレンスの「指示文」のコードブロックが、4 つの空欄を持たない"); process.exit(2); }
const f = L.findIndex(s => s.trim() === "### サブエージェントが返す書式"), e = L.findIndex((s, i) => i > f && s.startsWith("返り値の文が")), fmt = f < 0 || e < 0 ? "" : L.slice(f + 1, e).join("\n").trim();
if (!fmt.includes("```json")) { console.error("指示文のリファレンスの「サブエージェントが返す書式」の節が、json のコードブロックを持たない"); process.exit(2); }
process.stdout.write(Object.entries(V).reduce((t, [k, v]) => t.split(k).join(v), body) + "\n\nサブエージェントが返す書式:\n\n" + fmt + "\n");
process.exitCode = 0;
