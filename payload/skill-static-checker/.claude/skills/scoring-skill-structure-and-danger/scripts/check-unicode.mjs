#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, resolve, relative } from "node:path";
const A = process.argv.slice(2), oi = A.indexOf("--out"), OUT = oi >= 0 ? A[oi + 1] : "", DIR = A.find((a, i) => oi < 0 || (i !== oi && i !== oi + 1));
if (!DIR || (oi >= 0 && !OUT) || A.length !== (oi >= 0 ? 3 : 1) || !existsSync(join(DIR, "SKILL.md"))) { console.error("使い方: node check-unicode.mjs <調べるスキルのフォルダ> [--out <指摘の JSON のパス>]"); process.exit(2); } process.on("uncaughtException", e => { console.error(`調べられない: ${e.message}`); process.exit(2); });
const SEV = { CRITICAL: "重大", HIGH: "重大", MEDIUM: "注意", LOW: "注意", INFO: "参考" }, F = [];
const walk = d => readdirSync(d, { withFileTypes: true }).flatMap(e => [".git", "node_modules", ".tools"].includes(e.name) ? [] : e.isDirectory() ? walk(join(d, e.name)) : e.isFile() ? [join(d, e.name)] : []);
const files = walk(DIR).filter(p => statSync(p).size <= 2e6).map(p => [relative(DIR, p).split("\\").join("/"), readFileSync(p)]).filter(([, b]) => !b.subarray(0, 8192).includes(0)).map(([p, b]) => [p, b.toString("utf8")]);
const CAT = { tags: "タグ文字", bidi: "向きを変える文字", deprecated: "古い制御文字", operators: "見えない演算子", zero: "幅のない文字" }, ORDER = ["tags", "bidi", "deprecated", "operators", "zero"];
const cat = c => c >= 0xe0000 && c <= 0xe007f ? "tags" : [0x061c, 0x200e, 0x200f, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069].includes(c) ? "bidi" : c >= 0x206a && c <= 0x206f ? "deprecated" : c >= 0x2061 && c <= 0x2064 ? "operators" : [0x034f, 0x180e, 0x200b, 0x200c, 0x200d, 0x2060, 0xfeff].includes(c) ? "zero" : "";
const hex = g => g.slice(0, 5).map(x => "U+" + x.c.toString(16).toUpperCase().padStart(4, "0")).join("、") + (g.length > 5 ? ` ほか ${g.length - 5} 字` : "");
const add = (src, item, p, n, message, fix) => F.push({ check: "check-unicode", item, kind: "危険", severity: SEV[src], source_severity: src, dimension: null, deduction: 0, file: p, line: n, message, fix });
for (const [p, t] of files) t.split("\n").forEach((s, i) => {
  const G = []; let col = 0, last = -2;
  for (const ch of s) { const c = ch.codePointAt(0), k = cat(c); if (k) { if (last === col - 1) G.at(-1).push({ c, k }); else G.push([{ c, k }]); last = col; } col++; }
  for (const g of G) {
    const ks = new Set(g.map(x => x.k)), main = ORDER.find(k => ks.has(k)), n = i + 1, label = `見えない文字(${CAT[main]})`, rm = "見えない文字を消す。";
    const dec = g.filter(x => x.k === "tags" && x.c >= 0xe0020 && x.c <= 0xe007e).map(x => String.fromCharCode(x.c - 0xe0000)).join("").trim();
    if (g.length === 1 && g[0].c === 0xfeff && i === 0 && s.codePointAt(0) === 0xfeff) add("INFO", "ファイルの先頭の BOM", p, n, "ファイルの先頭に BOM がある。害はない。", "要らなければ BOM を消す。");
    else if (dec) add("CRITICAL", label, p, n, `タグ文字が、見えない英字の文「${dec.slice(0, 80)}」を持つ。`, rm);
    else if (g.length >= 40) add("CRITICAL", label, p, n, `見えない文字が ${g.length} 字続く(${hex(g)})。`, rm);
    else if (ks.has("bidi")) add("HIGH", label, p, n, `文字の向きを変える文字がある(${hex(g)})。表示とコードの中身が食い違うおそれがある。`, rm);
    else if (g.length >= 10) add("HIGH", label, p, n, `見えない文字が ${g.length} 字続く(${hex(g)})。`, rm);
    else if (["zero", "deprecated", "operators"].includes(main) && (g.length >= 3 || main !== "zero")) add("MEDIUM", label, p, n, `見えない文字がある(${hex(g)})。`, rm);
    else add("LOW", label, p, n, `見えない文字がある(${hex(g)})。写したときに紛れたおそれがある。`, rm);
  }
});
try { const R = JSON.stringify({ script: "check-unicode", target: resolve(DIR), status: "済み", findings: F }, null, 2) + "\n"; if (OUT) writeFileSync(OUT, R); else process.stdout.write(R); } catch (e) { console.error(`指摘の JSON を書けない: ${e.message}`); process.exit(2); }
process.exitCode = F.length ? 1 : 0;
