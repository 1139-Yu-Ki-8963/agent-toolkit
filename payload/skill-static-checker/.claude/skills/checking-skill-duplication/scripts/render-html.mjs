#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
const P = process.argv.slice(2);
if (P.length !== 1 || !existsSync(P[0])) { console.error("使い方: node render-html.mjs <結果の JSON のパス>"); process.exit(2); }
let S;
try { S = JSON.parse(readFileSync(P[0], "utf8")); if (!S.verdict || !Array.isArray(S.findings) || !Array.isArray(S.checks) || !S.judged || !S.report || !S.report.path || !/^\d{12}$/.test(S.stamp || "")) throw new Error("verdict、findings、checks、judged、report、stamp を持たない"); } catch (e) { console.error(`結果の JSON を読めない: ${e.message}`); process.exit(2); }
const file = S.report.path;
if (existsSync(file)) { console.error(`同じ名前のファイルがある: ${file}`); process.exit(2); }
const e = v => String(v ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;"), cl = { 合格: "pass", 不合格: "fail", 調べきれなかった: "warn" };
const sev = s => `<span class="sev s${["重大", "注意", "参考"].indexOf(s)}">${e(s)}</span>`, cats = c => e((c || []).map(x => x || "判定がない").join("、")), why = r => (r || []).map((x, i) => `判定者 ${i + 1}: ${e(x || "判定がない")}`).join("<br>"), cnt = n => `重大 ${S.findings.filter(f => f.check === n && f.severity === "重大").length} 件、注意 ${S.findings.filter(f => f.check === n && f.severity === "注意").length} 件`;
const note = c => (c.name === "スキルどうしの重なり" ? [`比べたスキル ${c.candidates} 本`, `上限を超えて判定しなかったスキル ${c.over_limit || 0} 本`, ...((c.unreadable || []).length ? [`読めないスキル: ${c.unreadable.join("、")}`] : []), ...(c.description_unreadable ? ["調べるスキルの description を読めない"] : [])] : [`候補 ${c.candidates} 件`, `上限を超えて判定しなかった候補 ${c.over_limit || 0} 件`]).join("、");
const row = f => `<tr><td>${sev(f.severity)}</td><td>${e(f.check)}</td><td>${e(f.item)}</td><td class="path">${e(f.file)}</td><td class="num">${f.line ? e(f.line) : "なし"}</td><td>${e(f.message)}</td><td>${e(f.fix)}</td><td class="path">${e(f.other)}</td><td class="num">${e(f.similarity)}</td><td>${why(f.reasons)}</td></tr>`;
const table = (rows, empty) => rows.length ? `<div class="wrap"><table><thead><tr><th>重さ</th><th>検査</th><th>項目</th><th>ファイル</th><th>行</th><th>中身</th><th>直し方</th><th>相手</th><th>文字の近さ</th><th>判定の理由</th></tr></thead><tbody>${rows.map(row).join("")}</tbody></table></div>` : `<p>${empty}</p>`;
const html = `<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${e(S.skill)} の重複の検査</title>
<style>:root{--bg:#fff;--fg:#1a1a1a;--mute:#5b5b5b;--line:#d9d9d9;--card:#f6f6f4;--ok:#1d6b3a;--ng:#b42318;--warn:#8a5a00;--info:#3b5b8a}@media (prefers-color-scheme:dark){:root{--bg:#161616;--fg:#ececec;--mute:#a8a8a8;--line:#3a3a3a;--card:#202020;--ok:#5cc489;--ng:#ff7b70;--warn:#e0b04a;--info:#8fb3e8}}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.7 "Hiragino Sans","Noto Sans JP","Yu Gothic",sans-serif}main{max-width:1200px;margin:0 auto;padding:24px 16px 64px}h1{font-size:1.5rem;margin:0 0 4px}h2{font-size:1.15rem;margin:32px 0 8px;border-bottom:1px solid var(--line);padding-bottom:4px}.mute{color:var(--mute)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin-top:16px}.card{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:12px 16px}.card .big{font-size:2rem;font-weight:700}.pass{color:var(--ok);font-weight:700}.fail{color:var(--ng);font-weight:700}.warn{color:var(--warn);font-weight:700}
.wrap{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:.88rem}th,td{border:1px solid var(--line);padding:6px 8px;text-align:left;vertical-align:top}th{background:var(--card);white-space:nowrap}.num{text-align:right;white-space:nowrap}.path{font-family:ui-monospace,Menlo,monospace;word-break:break-all}
.sev{font-weight:700;white-space:nowrap}.s0{color:var(--ng)}.s1{color:var(--warn)}.s2{color:var(--info)}code{font-family:ui-monospace,Menlo,monospace}</style></head>
<body><main>
<h1>${e(S.skill)} の重複の検査</h1>
<p class="mute">調べたスキルのフォルダ: <code>${e(S.target)}</code><br>比べたスキルの置き場: <code>${e(S.catalog)}</code><br>作った日時: ${e(S.stamp.replace(/^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)$/, "$1-$2-$3 $4:$5"))}</p>
<div class="cards"><div class="card"><div>重複の検査の合否</div><div class="big"><span class="${cl[S.verdict] || "warn"}">${e(S.verdict)}</span></div><div>重大 ${e(S.counts.重大)} 件、注意 ${e(S.counts.注意)} 件</div></div>
${S.checks.map(c => `<div class="card"><div>${e(c.name)}</div><div class="big">${e(c.findings)} 件</div><div>${cnt(c.name)}</div></div>`).join("")}</div>
<h2>合否の決め方</h2>
<p>判定者 2 人が、候補を 1 件ずつ、別々に仕分けます。2 人とも「重複」か「役目が同じ」とした候補は重大、1 人だけが「重複」とした候補と、どちらかが「役目が同じ」か「役目が一部重なる」とした候補は注意です。重大が 1 件でもあれば不合格です。重大がなく、調べきれなかった検査があれば、調べきれなかったとします。調べきれなかったことは、重複がない証拠になりません。</p>
<h2>最初に直す指摘(重さ「重大」)</h2>
${table(S.findings.filter(f => f.severity === "重大"), "重さ「重大」の指摘は、ありません。")}
<h2>指摘の一覧</h2>
${table(S.findings, "指摘は、ありません。")}
<h2>1 本の中の重複の候補と判定</h2>
${S.judged.sections.length ? `<div class="wrap"><table><thead><tr><th>候補</th><th>文字の近さ</th><th>節 1</th><th>節 2</th><th>判定</th><th>判定の理由</th></tr></thead><tbody>${S.judged.sections.map(x => `<tr><td>${e(x.id)}</td><td class="num">${e(x.similarity)}</td><td class="path">${e(x.a)}</td><td class="path">${e(x.b)}</td><td>${cats(x.categories)}</td><td>${why(x.reasons)}</td></tr>`).join("")}</tbody></table></div>` : `<p>候補は、ありません。</p>`}
<h2>スキルどうしの重なりの候補と判定</h2>
${S.judged.skills.length ? `<div class="wrap"><table><thead><tr><th>スキル</th><th>文字の近さ</th><th>判定</th><th>判定の理由</th></tr></thead><tbody>${S.judged.skills.map(x => `<tr><td>${e(x.id)}: ${e(x.name)}</td><td class="num">${e(x.similarity)}</td><td>${cats(x.categories)}</td><td>${why(x.reasons)}</td></tr>`).join("")}</tbody></table></div>` : `<p>比べるスキルは、ありません。</p>`}
<h2>検査ごとの状態</h2>
<div class="wrap"><table><thead><tr><th>検査</th><th>状態</th><th>指摘の数</th><th>補足</th></tr></thead><tbody>${S.checks.map(c => `<tr><td>${e(c.name)}</td><td>${e(c.status)}</td><td class="num">${e(c.findings)}</td><td>${e(note(c))}</td></tr>`).join("")}</tbody></table></div>
<p class="mute">判定がない候補: ${e((S.unjudged || []).join("、") || "なし")}<br>形と違う判定: ${e((S.judge_errors || []).join("、") || "なし")}</p>
</main></body></html>
`;
try { mkdirSync(dirname(file), { recursive: true }); writeFileSync(file, html); } catch (err) { console.error(`報告の HTML を書けない: ${err.message}`); process.exit(2); }
console.log(file.split("\\").join("/"));
process.exitCode = 0;
