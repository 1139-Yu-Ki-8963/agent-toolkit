#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, resolve, relative, extname } from "node:path";
const A = process.argv.slice(2), oi = A.indexOf("--out"), OUT = oi >= 0 ? A[oi + 1] : "", DIR = A.find((a, i) => oi < 0 || (i !== oi && i !== oi + 1));
if (!DIR || (oi >= 0 && !OUT) || A.length !== (oi >= 0 ? 3 : 1) || !existsSync(join(DIR, "SKILL.md"))) { console.error("使い方: node check-license.mjs <調べるスキルのフォルダ> [--out <指摘の JSON のパス>]"); process.exit(2); } process.on("uncaughtException", e => { console.error(`調べられない: ${e.message}`); process.exit(2); });
const SEV = { CRITICAL: "重大", HIGH: "重大", MEDIUM: "注意", LOW: "注意", INFO: "参考" }, F = [];
const add = (src, item, p, n, message, fix) => F.push({ check: "check-license", item, kind: "危険", severity: SEV[src], source_severity: src, dimension: null, deduction: 0, file: p, line: n, message, fix });
const norm = s => s.trim().toLowerCase().replace(/[ _]/g, "-").replace(/^the-/, "").replace(/-licen[cs]e$/, "").replace(/\+$/, "-or-later");
const OK = new Set(["Apache-2.0", "Apache-1.1", "Apache-1.0", "MIT", "MIT-0", "BSD-2-Clause", "BSD-3-Clause", "BSD-3-Clause-Clear", "0BSD", "ISC", "Unlicense", "WTFPL", "Zlib", "X11", "JSON", "CC0-1.0", "CC-BY-4.0", "CC-BY-3.0", "PSF-2.0", "Python-2.0"].map(norm));
const NG = new Set(["GPL-2.0", "GPL-2.0-only", "GPL-2.0-or-later", "GPL-3.0", "GPL-3.0-only", "GPL-3.0-or-later", "AGPL-3.0", "AGPL-3.0-only", "AGPL-3.0-or-later", "LGPL-2.0", "LGPL-2.1", "LGPL-3.0", "MPL-2.0", "EPL-1.0", "EPL-2.0", "CC-BY-NC-4.0", "CC-BY-NC-3.0", "CC-BY-NC-SA-4.0", "CC-BY-ND-4.0", "CC-BY-NC-ND-4.0", "Proprietary", "Commercial", "All-Rights-Reserved", "Confidential"].map(norm));
const EXC = new Set(["llvm-exception", "swift-exception"]);
const PAT = [["Apache-2.0", ["Apache License", "Version 2.0"], []], ["MIT", ["MIT License|Permission is hereby granted, free of charge", "without restriction"], []], ["BSD-3-Clause", ["BSD", "Redistribution and use", "Neither the name"], []], ["BSD-2-Clause", ["BSD", "Redistribution and use"], ["Neither the name"]], ["ISC", ["ISC License", "Permission to use, copy, modify"], []], ["Unlicense", ["This is free and unencumbered software", "public domain"], []], ["CC0-1.0", ["CC0|Creative Commons", "public domain"], []], ["AGPL-3.0", ["GNU AFFERO GENERAL PUBLIC LICENSE", "Version 3"], []], ["LGPL-3.0", ["GNU LESSER GENERAL PUBLIC LICENSE", "Version 3"], []], ["GPL-3.0", ["GNU GENERAL PUBLIC LICENSE", "Version 3"], []], ["GPL-2.0", ["GNU GENERAL PUBLIC LICENSE", "Version 2"], []], ["MPL-2.0", ["Mozilla Public License", "Version 2.0"], []]];
const PROP = /All rights reserved|Proprietary|Confidential|Trade secret|Not for distribution|Internal use only|Do not copy|Commercial license required|Licensed for evaluation only|Contact .* for licensing/i;
const judge = expr => { const parts = expr.replace(/[()]/g, " ").split(/\s+(?:OR|AND)\s+/i).map(s => s.trim()).filter(Boolean), isOr = /\sOR\s/i.test(expr) && !/\sAND\s/i.test(expr);
  const st = parts.map(s => { const [id, ex] = s.split(/\s+WITH\s+/i).map(norm); return NG.has(id) ? "ng" : OK.has(id) && (!ex || EXC.has(ex)) ? "ok" : "unknown"; });
  return isOr ? (st.includes("ok") ? "ok" : st.every(x => x === "ng") ? "ng" : "unknown") : (st.includes("ng") ? "ng" : st.length && st.every(x => x === "ok") ? "ok" : "unknown"); };
const L = readFileSync(join(DIR, "SKILL.md"), "utf8").replace(/^\uFEFF/, "").split(/\r?\n/), fe = L[0] === "---" ? L.indexOf("---", 1) : -1, li = L.slice(0, Math.max(fe, 0)).findIndex(s => s.startsWith("license:"));
const fm = li >= 0 ? L[li].slice(8).trim().replace(/^"(.*)"$|^'(.*)'$/, "$1$2") : "", NAMES = ["LICENSE", "LICENSE.txt", "LICENSE.md", "LICENSE.rst", "LICENCE", "LICENCE.txt", "COPYING", "COPYING.txt", "NOTICE", "NOTICE.txt"];
const lf = NAMES.find(n => existsSync(join(DIR, n))), lt = lf ? readFileSync(join(DIR, lf), "utf8") : "", det = lf ? (PAT.find(([, req, exc]) => req.every(r => new RegExp(r, "i").test(lt)) && !exc.some(r => new RegExp(r, "i").test(lt))) || [""])[0] : "";
const fromFm = fm && !NAMES.some(n => fm.includes(n)) ? fm : "";
if (lf && !det && PROP.test(lt)) add("HIGH", "許可しないライセンス", lf, 1, `${lf} が、知られたライセンスの文を持たず、配ることを禁じる文を持つ。`, "許可の一覧にあるライセンスにする。");
else if (lf && !det && !fromFm) add("MEDIUM", "知らないライセンス", lf, 1, `${lf} の文から、ライセンスを見分けられない。`, "フロントマターに SPDX の識別子を書く。");
for (const [src, where, n, id] of [["フロントマター", "SKILL.md", li + 1, fromFm], [lf, lf, 1, det]]) { if (!id) continue; const r = judge(id);
  if (r === "ng") add("HIGH", "許可しないライセンス", where, n, `${src} のライセンス「${id}」は、許可の一覧になく、制限のあるライセンスの一覧にある。`, "許可の一覧にあるライセンス(MIT、Apache-2.0 など)にする。");
  if (r === "unknown") add("MEDIUM", "許可の一覧にないライセンス", where, n, `${src} のライセンス「${id}」が、許可の一覧にない。`, "許可の一覧にあるライセンスにするか、人が中身を確かめる。"); }
if (fromFm && det && norm(fromFm) !== norm(det)) add("MEDIUM", "ライセンスの食い違い", "SKILL.md", li + 1, `フロントマターのライセンス「${fromFm}」と、${lf} の文から見分けたライセンス「${det}」が違う。`, "どちらかを直して揃える。");
const walk = d => readdirSync(d, { withFileTypes: true }).flatMap(e => [".git", "node_modules", ".tools"].includes(e.name) ? [] : e.isDirectory() ? walk(join(d, e.name)) : e.isFile() ? [join(d, e.name)] : []);
const EXT = [".py", ".sh", ".js", ".mjs", ".cjs", ".ts", ".yaml", ".yml", ".md", ".txt", ".json"];
for (const p of walk(DIR).filter(p => EXT.includes(extname(p)) && statSync(p).size <= 2e6)) readFileSync(p, "utf8").split(/\r?\n/).slice(0, 50).forEach((s, i) => { const m = s.match(/SPDX-License-Identifier:\s*([^\n*]+?)\s*(\*\/|-->)?$/); if (m && judge(m[1]) === "ng") add("HIGH", "許可しないライセンス", relative(DIR, p).split("\\").join("/"), i + 1, `ファイルの SPDX の見出しのライセンス「${m[1]}」は、制限のあるライセンスの一覧にある。`, "許可の一覧にあるライセンスのファイルにするか、ファイルを除く。"); });
try { const R = JSON.stringify({ script: "check-license", target: resolve(DIR), status: "済み", license: fromFm || det || "", findings: F }, null, 2) + "\n"; if (OUT) writeFileSync(OUT, R); else process.stdout.write(R); } catch (e) { console.error(`指摘の JSON を書けない: ${e.message}`); process.exit(2); }
process.exitCode = F.length ? 1 : 0;
