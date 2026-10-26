#!/usr/bin/env node
// skill-factory の hook を、正本(~/agent-home/hooks)から payload へ写すビルダー。
// 写すときに、正本の中の ~/agent-home/{hooks,rules,skills}/ を
// $CLAUDE_PROJECT_DIR/.claude/{hooks,rules,skills}/ に置き換え、CR を取り除く。
// 使い方: node scripts/build-skill-factory-hooks.mjs [出力先]
//   出力先を省くと payload/skill-factory/.claude/hooks に書く(--apply)。
//   出力先を渡すと、そこに書く(--check が一時フォルダを渡す)。
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SRC = path.join(os.homedir(), "agent-home", "hooks");
const DST = process.argv[2] ? path.resolve(process.argv[2]) : path.join(REPO_ROOT, "payload", "skill-factory", ".claude", "hooks");

const REPLACE = [
  ["~/agent-home/hooks/", "$CLAUDE_PROJECT_DIR/.claude/hooks/"],
  ["~/agent-home/rules/", "$CLAUDE_PROJECT_DIR/.claude/rules/"],
  ["~/agent-home/skills/", "$CLAUDE_PROJECT_DIR/.claude/skills/"],
];

function walk(dir, rel = "") {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name.startsWith(".") || e.name === "node_modules") continue;
    const r = path.join(rel, e.name);
    if (e.isDirectory()) out.push(...walk(path.join(dir, e.name), r));
    else if (e.isFile()) out.push(r);
  }
  return out;
}

if (!fs.existsSync(SRC)) {
  console.error(`正本がありません: ${SRC}`);
  process.exit(1);
}
const files = walk(SRC);
fs.rmSync(DST, { recursive: true, force: true });
for (const rel of files) {
  let text = fs.readFileSync(path.join(SRC, rel), "utf8").replace(/\r/g, "");
  for (const [from, to] of REPLACE) text = text.split(from).join(to);
  const dst = path.join(DST, rel);
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.writeFileSync(dst, text);
}
