#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, mkdtempSync, rmSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";
const A = process.argv.slice(2), oi = A.indexOf("--out"), OUT = oi >= 0 ? A[oi + 1] : "", DIR = A.find((a, i) => oi < 0 || (i !== oi && i !== oi + 1));
if (!DIR || (oi >= 0 && !OUT) || A.length !== (oi >= 0 ? 3 : 1) || !existsSync(join(DIR, "SKILL.md"))) { console.error("使い方: node check-dependencies.mjs <調べるスキルのフォルダ> [--out <指摘の JSON のパス>]"); process.exit(2); } process.on("uncaughtException", e => { console.error(`調べられない: ${e.message}`); process.exit(2); });
const SEV = { CRITICAL: "重大", HIGH: "重大", MEDIUM: "注意", LOW: "注意", INFO: "参考" }, NPM_SEV = { critical: "CRITICAL", high: "HIGH", moderate: "MEDIUM", low: "LOW", info: "INFO" }, F = [];
const add = (src, item, n, message, fix) => F.push({ check: "check-dependencies", item, kind: "危険", severity: SEV[src], source_severity: src, dimension: null, deduction: 0, file: "SKILL.md", line: n, message, fix });
const L = readFileSync(join(DIR, "SKILL.md"), "utf8").split(/\r?\n/), pi = L.findIndex(s => /^## 前提ツール\s*$/.test(s)), sec = pi < 0 ? [] : L.slice(pi + 1), end = sec.findIndex(s => /^## /.test(s));
const rows = (end < 0 ? sec : sec.slice(0, end)).map((s, i) => [s, pi + 2 + i]).filter(([s]) => /^\|/.test(s)).map(([s, n]) => [s.split("|").slice(1, -1).map(c => c.trim().replace(/^`|`$/g, "")), n]);
const h = rows.length ? rows[0][0] : [], ti = h.indexOf("ツール"), ci = h.indexOf("区分"), vi = h.indexOf("版");
const deps = ti < 0 || ci < 0 || vi < 0 ? [] : rows.slice(2).filter(([r]) => r[ci] === "スキルごとのツール").map(([r, n]) => ({ name: r[ti], version: r[vi], line: n }));
let status = "済み";
if (!deps.length) status = "対象なし";
else {
  const T = mkdtempSync(join(process.env.TMPDIR || tmpdir(), "check-dependencies-")), cli = [join(dirname(process.execPath), "../lib/node_modules/npm/bin/npm-cli.js"), join(dirname(process.execPath), "node_modules/npm/bin/npm-cli.js")].find(p => existsSync(p));
  const npm = args => cli ? spawnSync(process.execPath, [cli, ...args, "--cache", join(T, "cache"), "--fetch-retries=0", "--fetch-timeout=20000", "--no-fund", "--update-notifier=false"], { cwd: T, encoding: "utf8", timeout: 180000 }) : spawnSync("npm", [...args, "--cache", join(T, "cache"), "--fetch-retries=0", "--fetch-timeout=20000", "--no-fund", "--update-notifier=false"], { cwd: T, encoding: "utf8", timeout: 180000 });
  try {
    writeFileSync(join(T, "package.json"), JSON.stringify({ name: "scoring-skill-audit", version: "0.0.0", private: true, dependencies: Object.fromEntries(deps.map(d => [d.name, d.version])) }, null, 2));
    const ins = npm(["install", "--package-lock-only", "--ignore-scripts", "--no-audit"]), err = (ins.stderr || "") + (ins.error ? ins.error.message : "");
    const aud = ins.status === 0 ? npm(["audit", "--json"]) : null;
    let j = null; try { j = aud ? JSON.parse(aud.stdout) : null; } catch { j = null; }
    if (!j || j.error) { status = "調べられなかった"; const why = (err + (aud ? aud.stderr + JSON.stringify(j && j.error || "") : "")), net = /ENOTFOUND|ECONNREFUSED|EAI_AGAIN|ETIMEDOUT|ECONNRESET|ENETUNREACH|EHOSTUNREACH|EPROXY|E403|network|FetchError|request to/i.test(why); add("INFO", "部品の脆弱性を調べられなかった", deps[0].line, net ? "npm がネットワークにつながらず、部品の知られた脆弱性を調べられなかった。" : `npm の調べが失敗し、部品の知られた脆弱性を調べられなかった(${(why.split("\n").find(s => s.trim()) || "理由が出ていない").slice(0, 200)})。`, net ? "ネットワークにつながる場所で、もう一度調べる。" : "前提ツールの表のパッケージの名前と版を確かめる。"); }
    else for (const [name, v] of Object.entries(j.vulnerabilities || {})) { const titles = [...new Set((v.via || []).filter(x => typeof x === "object").map(x => x.title).filter(Boolean))], d = deps.find(x => x.name === name), src = NPM_SEV[v.severity] || "MEDIUM";
      add(src, "部品の知られた脆弱性", d ? d.line : deps[0].line, `部品「${name}」(版の範囲 ${v.range || "不明"})に、知られた脆弱性がある${titles.length ? `(${titles.slice(0, 3).join("、")})` : `(${(v.via || []).join("、")} から)`}。`, v.fixAvailable && typeof v.fixAvailable === "object" ? `「${v.fixAvailable.name}」を版 ${v.fixAvailable.version} にする。` : v.fixAvailable ? "直した版に上げる。" : "直した版が出るまで、ほかの部品にする。"); }
  } finally { rmSync(T, { recursive: true, force: true }); }
}
try { const R = JSON.stringify({ script: "check-dependencies", target: resolve(DIR), status, packages: deps.map(d => `${d.name}@${d.version}`), findings: F }, null, 2) + "\n"; if (OUT) writeFileSync(OUT, R); else process.stdout.write(R); } catch (e) { console.error(`指摘の JSON を書けない: ${e.message}`); process.exit(2); }
process.exitCode = F.length ? 1 : 0;
