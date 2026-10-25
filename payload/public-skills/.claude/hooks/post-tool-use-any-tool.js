// README: hooks/post-tool-use-any-tool/README.md
"use strict";
const fs = require("fs");
const path = require("path");
const guard = require("./pre-tool-use-write-file/skill-guard.js");

const EVENT = "PostToolUse";
const PROMPT_DIR = path.join(__dirname, "post-tool-use-any-tool");

function readPrompt(fileName) {
  return fs.readFileSync(path.join(PROMPT_DIR, fileName), "utf8");
}

function detectUnguidedSkillChange(input) {
  const basePath = guard.baselinePath(input);
  const current = {};
  const kinds = {};
  for (const { file, kind } of guard.guardedFiles()) {
    current[file] = guard.hashOf(file);
    kinds[file] = kind;
  }
  let base = null;
  try {
    base = JSON.parse(fs.readFileSync(basePath, "utf8"));
  } catch (e) {
    base = null;
  }
  if (base === null) {
    fs.writeFileSync(basePath, JSON.stringify({ hashes: current, kinds }));
    return [];
  }
  const files = new Set([...Object.keys(base.hashes), ...Object.keys(current)]);
  const next = { hashes: { ...base.hashes }, kinds: { ...base.kinds, ...kinds } };
  const unguided = [];
  for (const file of files) {
    const before = base.hashes[file] || "なし";
    const after = current[file] || "なし";
    if (before === after) continue;
    const kind = next.kinds[file] || "skill";
    if (guard.allowed(input, kind)) {
      if (after === "なし") delete next.hashes[file];
      else next.hashes[file] = after;
    } else {
      unguided.push(guard.relative(file));
    }
  }
  fs.writeFileSync(basePath, JSON.stringify(next));
  if (unguided.length === 0) return [];
  return [
    {
      kind: "violation",
      source: "detectUnguidedSkillChange",
      text:
        "決まったスキルの手順を通さずに、テスト計画書を持つスキルのファイルが変わった: " +
        unguided.join("、") +
        "。変えたツールの操作を取り消し、ファイルを元の中身に戻してください。",
    },
  ];
}

const CHECKS = [detectUnguidedSkillChange];

function summarize(results) {
  const lines = [];
  for (const kind of ["violation", "prompt"]) {
    const items = results.filter((r) => r.kind === kind);
    if (items.length === 0) continue;
    lines.push(kind === "violation" ? "違反" : "点検の依頼");
    for (const r of items) {
      lines.push(r.source);
      lines.push(r.text);
    }
  }
  return lines.join("\n");
}

function main(raw) {
  let input;
  try {
    input = JSON.parse(raw);
  } catch (e) {
    process.exit(0);
  }
  if (input.hook_event_name !== EVENT) process.exit(0);

  let text = null;
  const filePath = input.tool_input && input.tool_input.file_path;
  if (EVENT === "PostToolUse" && filePath && fs.existsSync(filePath)) {
    text = fs.readFileSync(filePath, "utf8");
  }

  const results = CHECKS.flatMap((check) => check(input, text));
  if (results.length === 0) process.exit(0);

  const message = summarize(results);
  const hasViolation = results.some((r) => r.kind === "violation");
  if (EVENT === "Stop" || hasViolation) {
    process.stderr.write(message + "\n");
    process.exit(2);
  }
  process.stdout.write(
    JSON.stringify({ hookSpecificOutput: { hookEventName: EVENT, additionalContext: message } }) + "\n"
  );
  process.exit(0);
}

let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => (raw += chunk));
process.stdin.on("end", () => main(raw));
