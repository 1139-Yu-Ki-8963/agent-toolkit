#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, resolve, relative } from "node:path";
import { userInfo } from "node:os";
const A = process.argv.slice(2), oi = A.indexOf("--out"), OUT = oi >= 0 ? A[oi + 1] : "", DIR = A.find((a, i) => oi < 0 || (i !== oi && i !== oi + 1));
if (!DIR || (oi >= 0 && !OUT) || A.length !== (oi >= 0 ? 3 : 1) || !existsSync(join(DIR, "SKILL.md"))) { console.error("使い方: node check-secrets.mjs <調べるスキルのフォルダ> [--out <指摘の JSON のパス>]"); process.exit(2); } process.on("uncaughtException", e => { console.error(`調べられない: ${e.message}`); process.exit(2); });
const SEV = { CRITICAL: "重大", HIGH: "重大", MEDIUM: "注意", LOW: "注意", INFO: "参考" }, F = [];
const walk = d => readdirSync(d, { withFileTypes: true }).flatMap(e => [".git", "node_modules", ".tools"].includes(e.name) ? [] : e.isDirectory() ? walk(join(d, e.name)) : e.isFile() ? [join(d, e.name)] : []);
const files = walk(DIR).filter(p => statSync(p).size <= 2e6).map(p => [relative(DIR, p).split("\\").join("/"), readFileSync(p)]).filter(([, b]) => !b.subarray(0, 8192).includes(0)).map(([p, b]) => [p, b.toString("utf8")]);
const SECRET_EX = ["example", "test", "dummy", "placeholder", "your_", "insert_", "your-", "<your", "{your", "${", "$("], user = (process.env.USER || (() => { try { return userInfo().username; } catch { return ""; } })()).toLowerCase();
const P = [
  ["個人の情報", "個人の macOS のパス", "HIGH", /\/Users\/([^/\s]+)\//, ["/users/:", "/users/{", "get /users", "post /users", "put /users", "patch /users", "delete /users", "api/users"], "<ホームのフォルダ> のような山かっこの値にする。"],
  ["個人の情報", "個人の Windows のパス", "HIGH", /C:\\Users\\([^\\\s]+)/i, [], "%USERPROFILE% か <ホームのフォルダ> のような書き方にする。"],
  ["個人の情報", "個人の Linux のホームのパス", "HIGH", /\/home\/([^/\s]+)\//, [], "<ホームのフォルダ> のような山かっこの値にする。"],
  ["個人の情報", "ホームを表すチルダで始まるパス", "MEDIUM", /(?<![\w.~-])~\/[^\s`"'<>)）」、。]*/, [], "<ホームのフォルダ> のような山かっこの値か、スキルのフォルダからの相対パスにする。"],
  ["個人の情報", "実在しうるメールアドレス", "HIGH", /(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@(?!(?:[a-z0-9-]+\.)*(?:example\.(?:com|net|org)|test\.com|test|example|invalid|localhost)\.*(?![a-z0-9.-])|odata\.)[A-Za-z0-9.-]+\.[A-Za-z]{2,}/i, ["copyright", "license", "(c)", "authors", "://", "@odata."], "example.com のような例示用のドメインのアドレスにする。"],
  ["個人の情報", "米国の電話番号", "MEDIUM", /\b\d{3}[-.]\d{3}[-.]\d{4}\b/, ["pageid=", "http://", "https://", "?id=", "&id=", "id="], "電話番号を消すか、例示用の値にする。"],
  ["個人の情報", "国際の電話番号", "MEDIUM", /(?<![\w.])\+\d{1,3}[\s.-]?\(?\d{1,4}\)?[\s.-]?\d{1,4}[\s.-]?\d{1,9}/, ["http://", "https://", "pageid="], "電話番号を消すか、例示用の値にする。"],
  ["個人の情報", "日本の電話番号", "MEDIUM", /(?<![\d-])0\d{1,4}-\d{1,4}-\d{4}(?![\d-])/, ["http://", "https://"], "電話番号を消すか、例示用の値にする。"],
  ["個人の情報", "社会保障番号", "CRITICAL", /\b\d{3}-\d{2}-\d{4}\b/, [], "番号を消す。"],
  ["個人の情報", "公開の IP アドレス", "MEDIUM", /\b(?!10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168\.|127\.|169\.254\.|0\.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/, [], "192.168.0.1 のような私用の範囲のアドレスか、0.0.0.0 にする。"],
  ["秘密の値", "資格情報を持つデータベースの接続文字列", "CRITICAL", /(postgres|postgresql|mysql|mariadb|mongodb|redis):\/\/[^:\s]+:[^@\s]+@[^/\s]+/i, [], "接続文字列を環境変数から読む。"],
  ["秘密の値", "JDBC の接続文字列", "HIGH", /jdbc:[a-z]+:\/\/[^:\s]+:[0-9]+\/[a-z0-9_-]+/i, [], "接続文字列を環境変数から読む。"],
  ["秘密の値", "パスワードを持つ接続文字列", "CRITICAL", /(connection|conn)[-_]?string.*password=/i, [], "パスワードを環境変数から読む。"],
  ["秘密の値", "JWT のトークン", "HIGH", /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/, [], "トークンを消し、eyJ...REDACTED のような値にする。"],
  ["秘密の値", "コードに書いた秘密の値", "CRITICAL", /(secret|password|passwd|pwd|api[-_]?key|apikey|auth[-_]?token|bearer)\s*[=:]\s*['"][^'"]{16,}['"]/i, SECRET_EX, "秘密の値を環境変数か秘密の値の管理の仕組みから読む。"],
  ["秘密の値", "Slack の Webhook の URL", "HIGH", /https:\/\/hooks\.slack\.com\/services\/T[A-Z0-9]{8}\/B[A-Z0-9]{8}\/[A-Za-z0-9]{24}/, [], "URL を環境変数から読む。"],
  ["秘密の値", "Discord の Webhook の URL", "HIGH", /https:\/\/discord\.com\/api\/webhooks\/[0-9]{18}\/[A-Za-z0-9_-]{68}/, [], "URL を環境変数から読む。"],
  ["秘密の値", "AWS のアクセスキー", "CRITICAL", /\b(AKIA|ASIA)[A-Z0-9]{16}\b/, [], "キーを消し、IAM のロールか環境変数を使う。"],
  ["秘密の値", "AWS の ARN", "MEDIUM", /arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:[a-z0-9-/_]+/, [], "ARN を例示用の値にする。"],
  ["秘密の値", "GitHub のトークン", "CRITICAL", /\b(gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,})\b/, [], "トークンを消し、環境変数 GITHUB_TOKEN を使う。"],
  ["秘密の値", "Slack のトークン", "CRITICAL", /\bxox[abprs]-[A-Za-z0-9-]{10,}/, [], "トークンを消し、環境変数を使う。"],
  ["秘密の値", "AI の API のキー", "CRITICAL", /\bsk-(ant-)?[A-Za-z0-9_-]{20,}/, SECRET_EX, "キーを消し、環境変数を使う。"],
  ["秘密の値", "Google の API のキー", "CRITICAL", /\bAIza[0-9A-Za-z_-]{35}\b/, [], "キーを消し、環境変数を使う。"],
  ["秘密の値", "npm のトークン", "CRITICAL", /\bnpm_[A-Za-z0-9]{36}\b/, [], "トークンを消し、環境変数を使う。"],
  ["秘密の値", "PEM の形の秘密鍵", "CRITICAL", /-----BEGIN[A-Z ]*PRIVATE KEY-----/, [], "秘密鍵を消し、鍵のファイルのパスを指す。"],
  ["個人の情報", "クレジットカードの番号", "CRITICAL", /(?<![A-Za-z0-9.])[0-9]{4}[\s-]?[0-9]{4}[\s-]?[0-9]{4}[\s-]?[0-9]{4}(?![A-Za-z0-9])(?!_[A-Za-z0-9])/, ["agent-browser", "fill @", "example", "placeholder", "mock", "fake", "dummy", "test card", "test number", "for testing"], "番号を消すか、4111-1111-1111-1111 のような試験用の番号にする。"],
  ["個人の情報", "暗号資産のアドレス", "MEDIUM", /\b([13][a-km-zA-HJ-NP-Z1-9]{25,34}|0x[a-fA-F0-9]{40})\b/, [], "私的なアドレスなら消す。"],
  ["個人の情報", "MAC アドレス", "LOW", /\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b/, [], "例示用の値にする。"],
  ["個人の情報", "位置の座標", "MEDIUM", /[-+]?([1-8]?\d\.\d{4,}|90\.0+)[,\s]+[-+]?(180\.0+|((1[0-7]\d)|([1-9]?\d))\.\d{4,})/, ["%", "createcanvas", "viewport", "--", "width:", "height:", "version", "~", "range("], "位置の情報を消すか、0.0, 0.0 にする。"]];
const TEST_CARDS = new Set(["4111111111111111", "5500000000000004", "4242424242424242", "4000056655665556", "4012888888881881", "5555555555554444", "5105105105105100", "2223003122003222", "6011111111111117", "3530111333300000"]);
const luhn = d => [...d].reverse().reduce((s, c, i) => s + (i % 2 ? ((+c * 2) > 9 ? +c * 2 - 9 : +c * 2) : +c), 0) % 10 === 0;
const mask = (cat, v) => cat === "秘密の値" ? v.slice(0, 4) + "…(" + v.length + " 字)" : v.length > 60 ? v.slice(0, 60) + "…" : v;
for (const [p, t] of files) { const cr = t.split("\n").map((s, i) => [s, i + 1]).filter(([s]) => s.endsWith("\r"));
  if (cr.length) F.push({ check: "check-secrets", item: "個人の情報(行末の CR)", kind: "危険", severity: "注意", source_severity: "LOW", dimension: null, deduction: 0, file: p, line: cr[0][1], message: `行末に CR(復帰の文字)を持つ行が ${cr.length} 行あり、書いた人の環境を示す。`, fix: "改行を LF だけにする。" });
  t.split(/\r?\n/).forEach((s, i) => { const low = s.toLowerCase(); for (const [cat, label, src, re, ex, fix] of P) {
  const m = s.match(re);
  if (!m || ex.some(e => low.includes(e))) continue;
  if (label.includes("パス") && /^[<{$%*]/.test(m[1])) continue;
  if (label.includes("Linux") && m[1].toLowerCase() !== user) continue;
  if (label.includes("クレジット") && (!luhn(m[0].replace(/\D/g, "")) || TEST_CARDS.has(m[0].replace(/\D/g, "")))) continue;
  if (label === "位置の座標" && !/gps|緯度|経度|latitude|longitude|lat\/lng|geo:|location|address/i.test(s)) continue;
  F.push({ check: "check-secrets", item: `${cat}(${label})`, kind: "危険", severity: SEV[src], source_severity: src, dimension: null, deduction: 0, file: p, line: i + 1, message: `${label}「${mask(cat, m[0])}」がある。`, fix });
} }); }
try { const R = JSON.stringify({ script: "check-secrets", target: resolve(DIR), status: "済み", findings: F }, null, 2) + "\n"; if (OUT) writeFileSync(OUT, R); else process.stdout.write(R); } catch (e) { console.error(`指摘の JSON を書けない: ${e.message}`); process.exit(2); }
process.exitCode = F.length ? 1 : 0;
