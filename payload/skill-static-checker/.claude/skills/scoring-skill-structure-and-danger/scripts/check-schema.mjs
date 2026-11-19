#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, resolve, basename } from "node:path";
const A = process.argv.slice(2), oi = A.indexOf("--out"), OUT = oi >= 0 ? A[oi + 1] : "", DIR = A.find((a, i) => oi < 0 || (i !== oi && i !== oi + 1));
if (!DIR || (oi >= 0 && !OUT) || A.length !== (oi >= 0 ? 3 : 1) || !existsSync(join(DIR, "SKILL.md"))) { console.error("使い方: node check-schema.mjs <調べるスキルのフォルダ> [--out <指摘の JSON のパス>]"); process.exit(2); } process.on("uncaughtException", e => { console.error(`調べられない: ${e.message}`); process.exit(2); });
const F = [], SEV = { CRITICAL: "重大", HIGH: "重大", MEDIUM: "注意", LOW: "注意", INFO: "参考" }, M = "SKILL.md";
const add = (item, src, ded, line, message, fix) => F.push({ check: "check-schema", item, kind: "構造", severity: SEV[src], source_severity: src, dimension: "正しさ", deduction: ded, file: M, line, message, fix });
const raw = readFileSync(join(DIR, M));
if (raw[0] === 0xef && raw[1] === 0xbb && raw[2] === 0xbf) add("BOM", "MEDIUM", 10, 1, "SKILL.md が UTF-8 の BOM で始まる。", "SKILL.md を BOM のない UTF-8 で保存する。");
const L = raw.toString("utf8").replace(/^\uFEFF/, "").split(/\r?\n/), end = L[0] === "---" ? L.indexOf("---", 1) : -1;
if (end < 0) add("フロントマターの有無", "HIGH", 15, 1, "SKILL.md の 1 行目から始まり --- で閉じるフロントマターがない。", "1 行目に --- を置き、name と description を書いて、--- の行で閉じる。");
const V = {}, LN = {}, seen = new Set();
let top = "", blk = false;
for (let i = 1; i < end; i++) {
  const s = L[i], n = i + 1;
  if (!s.trim() || /^\s*#/.test(s)) continue;
  if (/^ *\t/.test(s)) { add("タブの字下げ", "HIGH", 15, n, "フロントマターの行がタブで字下げされている。", "字下げを空白にする。"); continue; }
  if (blk && /^\s/.test(s)) { V[top] += (V[top] ? " " : "") + s.trim(); continue; }
  blk = false;
  const m = s.match(/^( *)([^\s:#-][^:]*?)\s*:(?:\s+(.*)|\s*)$/);
  if (!m) { if (/^\s/.test(s) && top in V) V[top] += " " + s.trim(); continue; }
  const k = m[2].replace(/^["']|["']$/g, ""), key = m[1].length ? top + "." + k : k, v = (m[3] || "").trim();
  if (!m[1].length) top = k;
  if (seen.has(key)) add("同じキー", "HIGH", 15, n, `キー「${key}」が 2 回ある。`, "同じキーの行を 1 つにする。");
  if (/^(\d+(\.\d+)?|true|false|yes|no|on|off|null|~)$/i.test(k)) add("キーの型", "HIGH", 15, n, `キー「${k}」が、文字列でない値として読まれる。`, "キーを英字で始まる名前にする。");
  seen.add(key); LN[key] = n; V[key] = v.replace(/^"(.*)"$|^'(.*)'$/, "$1$2");
  if (!m[1].length && /^[|>][-+]?$/.test(v)) { V[key] = ""; blk = true; }
}
const name = V.name || "", desc = V.description || "", X = /<\/?[A-Za-z][A-Za-z0-9_-]*(?:\s[^<>]*)?\/?>|<\/?[A-Za-z][A-Za-z0-9_-]*\s[^<>]*$/;
if (end > 0) for (const k of ["name", "description"]) if (!V[k]) add("name と description の有無", "HIGH", 15, LN[k] || 1, `フロントマターに ${k} がないか、値が空である。`, `フロントマターに ${k} の行を書く。`);
if (name && !(/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/.test(name) && name.length <= 64)) add("name の形", "HIGH", 15, LN.name, `name「${name}」が、英小文字で始まり、英小文字と数字と、間に 1 つずつ置いたハイフンだけでできた 64 字以内の名前でない。`, "name を、英小文字、数字、ハイフンだけの 64 字以内の名前にし、末尾と連続のハイフンを除く。");
if (name.toLowerCase().split("-").some(w => w === "anthropic" || w === "claude")) add("name の予約語", "HIGH", 15, LN.name, `name「${name}」が、予約語 anthropic か claude を持つ。`, "name から anthropic と claude を除く。");
if (name && name !== basename(resolve(DIR))) add("name とフォルダの名前", "HIGH", 15, LN.name, `name「${name}」が、フォルダの名前「${basename(resolve(DIR))}」と違う。`, "name とフォルダの名前を同じにする。");
if ([...desc].length > 1024) add("description の字数", "HIGH", 15, LN.description, `description が ${[...desc].length} 字で、1,024 字を超える。`, "description を 1,024 字以内にする。");
const CTRL = /<(?:(?:system|developer|assistant|user|tool|context|instructions?|prompt|override|rules|policy)(?:[_-]?(?:prompt|message|call|use|result|instruction)s?)?|script)(?=[\s<>:])/i, PH = /<(?![^<>]*\/\s*>)([A-Za-z][^<>=\r\n]*)>/g, ARROW = /(?<!\S)(?:->|=>|>=)(?!\S)|(?<![^\s(\[])>=? ?\d+(?:\.\d+)?(?![^\s)\],])/g;
const isPh = b => { if (/\s$/.test(b) || /[;&`]|\$[({]/.test(b) || b.split(/\s+/).filter(w => /[\p{L}\p{N}]/u.test(w)).length > 4) return false; if (!b.includes("|")) return true; const c = b.split("|"); c[0] = c[0].trim().replace(/^(?:[^|:]+:|\S+\s+(?:e\.g\.|i\.e\.),?)\s+/i, ""); return c.every(x => /^(?:\S+|"[^"]*"|'[^']*')$/.test(x.trim())); };
const hides = m => { const ops = new Set([...m.matchAll(ARROW)].map(x => x.index + x[0].indexOf(">"))), op = []; let after = false; for (let i = 0; i < m.length; i++) { const c = m[i]; if (after && c !== ">") return true; after = false; if (c === "<") op.push(i); else if (c === ">") { if (op.length) op.pop(); else if (!ops.has(i)) return true; } else if (op.length && m.startsWith("[]", i)) { if (!/^[A-Za-z][A-Za-z0-9_-]*$/.test(m.slice(op.at(-1) + 1, i))) return true; after = true; i++; } } return after; };
const maskHint = h => { if (CTRL.test(h)) return h; const m = h.replace(PH, (all, b) => isPh(b) ? "[]" : all); return hides(m) ? h : m; };
const xk = Object.keys(V).filter(k => X.test(k === "argument-hint" ? maskHint(V[k]) : V[k])), xo = xk.filter(k => k !== "name" && k !== "description");
for (const k of xk.filter(k => k === "name" || k === "description")) add("XML のタグ", "HIGH", 15, LN[k], `キー「${k}」の値が XML のタグを持ち、AI への指示として読まれるおそれがある。`, "値から山かっこのタグを除く。");
if (xo.length) add("XML のタグ", "HIGH", 15, LN[xo[0]], `name と description のほかのキー(${xo.join("、")})の値が XML のタグを持ち、AI への指示として読まれるおそれがある。`, "値から山かっこのタグを除く。argument-hint の引数は、<file> のような短い書き方にする。");
const fb = ["alwaysApply", "globs"].filter(k => k in V);
if (fb.length) add("alwaysApply と globs", "HIGH", 15, LN[fb[0]], `フロントマターが、スキルでは使わないキー(${fb.join("、")})を持つ。`, `キー(${fb.join("、")})の行を消す。`);
if ("metadata.version" in V && !/^(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})$/.test(V["metadata.version"])) add("metadata.version の形", "HIGH", 15, LN["metadata.version"], `metadata.version「${V["metadata.version"]}」が「1.2.3」の形でない。`, "metadata.version を、点で区切った 3 つの整数にする。");
try { const R = JSON.stringify({ script: "check-schema", target: resolve(DIR), status: "済み", findings: F }, null, 2) + "\n"; if (OUT) writeFileSync(OUT, R); else process.stdout.write(R); } catch (e) { console.error(`指摘の JSON を書けない: ${e.message}`); process.exit(2); }
process.exitCode = F.length ? 1 : 0;
