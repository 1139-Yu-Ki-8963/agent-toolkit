#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
const P = process.argv.slice(2);
if (P.length !== 1 || !existsSync(P[0])) { console.error("使い方: node render-html.mjs <点数の JSON のパス>"); process.exit(2); }
let S;
try { S = JSON.parse(readFileSync(P[0], "utf8")); if (!S.structure || !S.danger || !Array.isArray(S.findings) || !S.report || !S.report.path || !/^\d{12}$/.test(S.stamp || "")) throw new Error("structure、danger、findings、report、stamp を持たない"); } catch (e) { console.error(`点数の JSON を読めない: ${e.message}`); process.exit(2); }
const file = S.report.path;
if (existsSync(file)) { console.error(`同じ名前のファイルがある: ${file}`); process.exit(2); }
const e = v => String(v ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;"), N = S.names || {}, nm = c => N[c] || c;
const ok = b => b ? `<span class="pass">合格</span>` : `<span class="fail">不合格</span>`, sev = s => `<span class="sev s${["重大", "注意", "参考"].indexOf(s)}">${e(s)}</span>`;
const row = f => `<tr><td>${sev(f.severity)}</td><td>${e(nm(f.check))}</td><td>${e(f.item)}</td><td class="path">${e(f.file)}</td><td class="num">${f.line ? e(f.line) : "なし"}</td><td>${e(f.message)}</td><td>${e(f.fix)}</td><td>${e(f.kind)}</td><td class="num">${f.kind === "構造" ? e(f.deduction) + "(" + e(f.dimension) + ")" : "なし"}</td></tr>`;
const table = (rows, empty) => rows.length ? `<div class="wrap"><table><thead><tr><th>重さ</th><th>検査</th><th>項目</th><th>ファイル</th><th>行</th><th>中身</th><th>直し方</th><th>区分</th><th>減点(分野)</th></tr></thead><tbody>${rows.map(row).join("")}</tbody></table></div>` : `<p>${empty}</p>`;
const st = S.structure, dg = S.danger, first = S.findings.filter(f => f.severity === "重大"), cnt = (c, ref) => `重大 ${c.重大} 件、注意 ${c.注意} 件${ref ? `、参考 ${c.参考} 件` : ""}`, card = c => { const g = s => S.findings.filter(f => f.check === c.script && f.severity === s).length; return `<div class="card"><div>${e(nm(c.script))}</div><div class="big">${e(c.findings)} 件</div><div>${cnt({ 重大: g("重大"), 注意: g("注意"), 参考: g("参考") }, ["check-harness", "check-unicode", "check-dependencies"].includes(c.script))}</div></div>`; };
const html = `<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${e(S.skill)} の構造と危険の静的チェック</title>
<style>:root{--bg:#fff;--fg:#1a1a1a;--mute:#5b5b5b;--line:#d9d9d9;--card:#f6f6f4;--ok:#1d6b3a;--ng:#b42318;--warn:#8a5a00;--info:#3b5b8a}@media (prefers-color-scheme:dark){:root{--bg:#161616;--fg:#ececec;--mute:#a8a8a8;--line:#3a3a3a;--card:#202020;--ok:#5cc489;--ng:#ff7b70;--warn:#e0b04a;--info:#8fb3e8}}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.7 "Hiragino Sans","Noto Sans JP","Yu Gothic",sans-serif}main{max-width:1200px;margin:0 auto;padding:24px 16px 64px}h1{font-size:1.5rem;margin:0 0 4px}h2{font-size:1.15rem;margin:32px 0 8px;border-bottom:1px solid var(--line);padding-bottom:4px}.mute{color:var(--mute)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin-top:16px}.card{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:12px 16px}.card .big{font-size:2rem;font-weight:700}.pass{color:var(--ok);font-weight:700}.fail{color:var(--ng);font-weight:700}.warn{color:var(--warn);font-weight:700}
.wrap{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:.88rem}th,td{border:1px solid var(--line);padding:6px 8px;text-align:left;vertical-align:top}th{background:var(--card);white-space:nowrap}.num{text-align:right;white-space:nowrap}.path{font-family:ui-monospace,Menlo,monospace;word-break:break-all}
.sev{font-weight:700;white-space:nowrap}.s0{color:var(--ng)}.s1{color:var(--warn)}.s2{color:var(--info)}code{font-family:ui-monospace,Menlo,monospace}</style></head>
<body><main>
<h1>${e(S.skill)} の構造と危険の静的チェック</h1>
<p class="mute">調べたスキルのフォルダ: <code>${e(S.target)}</code><br>報告の出力先のフォルダ: <code>${e(S.report.dir)}</code><br>作った日時: ${e(S.stamp.replace(/^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)$/, "$1-$2-$3 $4:$5"))}</p>
<div class="cards"><div class="card"><div>構造の点数と危険の合否</div><div class="big">${e(Number(st.score).toFixed(1))} 点</div><div>構造: ${ok(st.pass)}(合格ライン ${e(st.threshold)} 点)、危険: ${ok(dg.pass)}</div></div>
${S.checks.map(card).join("")}</div>
<h2>構造の点数の出し方</h2>
<p>4 つの分野の点数は、それぞれ 100 点から、その分野の構造の指摘の減点を引いた点数(0 点より下にしない)です。構造の点数は、分野の点数に重みをかけて足した点数です。構造は、丸める前の点数が ${e(st.threshold)} 点以上で、重さ「重大」の構造の指摘がないときに合格です。危険は点数にせず、重さ「重大」の危険の指摘が 1 件でもあれば不合格です。道具ごとの読み込みの助言は、点数と合否に入れません。</p>
<div class="wrap"><table><thead><tr><th>分野</th><th>重み</th><th>減点の合計</th><th>分野の点数</th><th>重みをかけた点</th></tr></thead><tbody>${st.dimensions.map(x => `<tr><td>${e(x.name)}</td><td class="num">${e(x.weight)}</td><td class="num">${e(x.deduction)}</td><td class="num">${e(x.score)}</td><td class="num">${e(x.weighted)}</td></tr>`).join("")}<tr><th colspan="4">構造の点数</th><th class="num">${e(Number(st.score).toFixed(1))}</th></tr></tbody></table></div>
<h2>最初に直す指摘(重さ「重大」)</h2>
${table(first, "重さ「重大」の指摘は、ありません。")}
<h2>指摘の一覧</h2>
${table(S.findings, "指摘は、ありません。")}
<h2>参考の数の値</h2>
<p>数の上限は、規約に入れていないので、検査せずに参考として載せます。</p>
<div class="wrap"><table><thead><tr><th>項目</th><th>値</th><th>参考の上限</th><th>上限を超えたか</th></tr></thead><tbody>${(S.metrics || []).map(m => `<tr><td>${e(m.label)}</td><td class="num">${e(m.value)} ${e(m.unit.replace("(下限)", ""))}</td><td class="num">${e(m.limit)} ${e(m.unit)}</td><td>${m.over ? `<span class="warn">${m.unit.includes("下限") ? "下回る" : "超える"}</span>` : "超えない"}</td></tr>`).join("")}</tbody></table></div>
<h2>検査ごとの状態</h2>
<div class="wrap"><table><thead><tr><th>検査</th><th>状態</th><th>指摘の数</th><th>補足</th></tr></thead><tbody>${S.checks.map(c => `<tr><td>${e(nm(c.script))}</td><td>${c.status === "調べられなかった" ? `<span class="warn">${e(c.status)}</span>` : e(c.status)}</td><td class="num">${e(c.findings)}</td><td>${c.packages ? "調べた部品: " + e(c.packages.join("、") || "なし") : c.license !== undefined ? "見分けたライセンス: " + e(c.license || "なし") : "なし"}</td></tr>`).join("")}</tbody></table></div>
</main></body></html>
`;
try { mkdirSync(dirname(file), { recursive: true }); writeFileSync(file, html); } catch (err) { console.error(`報告の HTML を書けない: ${err.message}`); process.exit(2); }
console.log(file.split("\\").join("/"));
process.exitCode = 0;
