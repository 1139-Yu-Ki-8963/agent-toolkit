#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, readdirSync, realpathSync } from "node:fs";
import { join, resolve, dirname, basename } from "node:path";
import { homedir } from "node:os";
const A = process.argv.slice(2), oi = A.indexOf("--out"), OUT = oi >= 0 ? A[oi + 1] : "", DIR = A.find((a, i) => oi < 0 || (i !== oi && i !== oi + 1));
if (!DIR || (oi >= 0 && !OUT) || A.length !== (oi >= 0 ? 3 : 1) || !existsSync(join(DIR, "SKILL.md"))) { console.error("使い方: node check-harness.mjs <調べるスキルのフォルダ> [--out <指摘の JSON のパス>]"); process.exit(2); } process.on("uncaughtException", e => { console.error(`調べられない: ${e.message}`); process.exit(2); });
const nameOf = d => { try { const m = readFileSync(join(d, "SKILL.md"), "utf8").match(/^---\r?\n[\s\S]*?^name:\s*["']?([^"'\r\n]+?)["']?\s*$/m); return m ? m[1] : basename(d); } catch { return ""; } };
const real = p => { try { return realpathSync(p); } catch { return ""; } }, me = real(DIR), name = nameOf(DIR), H = process.env.HOME || homedir();
const ROOTS = [".agents/skills", ".claude/skills", ".codex/skills", ".github/skills", ".opencode/skills", ".opencode/skill", ".hermes/skills", ".copilot/skills", ".openclaw/skills", ".config/opencode/skills"];
const folders = [{ where: "同じフォルダ", path: dirname(resolve(DIR)) }, ...ROOTS.map(r => ({ where: "ホームのフォルダの下の " + r, path: join(H, r) }))];
const seen = new Set([me]), F = [];
for (const { where, path } of folders) for (const d of existsSync(path) ? readdirSync(path) : []) {
  const p = join(path, d), rp = real(p);
  if (!rp || seen.has(rp) || !existsSync(join(p, "SKILL.md")) || nameOf(p) !== name) continue;
  seen.add(rp);
  F.push({ check: "check-harness", item: "同じ名前のスキル", kind: "助言", severity: "参考", source_severity: "INFO", dimension: null, deduction: 0, file: "SKILL.md", line: 0, message: `同じ name「${name}」のスキルが、${where}の ${d} にもある。AI の道具は、どちらか 1 つだけを読み込む。`, fix: "どちらかを消すか、name を変える。" });
}
try { const R = JSON.stringify({ script: "check-harness", target: resolve(DIR), status: "済み", findings: F }, null, 2) + "\n"; if (OUT) writeFileSync(OUT, R); else process.stdout.write(R); } catch (e) { console.error(`指摘の JSON を書けない: ${e.message}`); process.exit(2); }
process.exitCode = F.length ? 1 : 0;
