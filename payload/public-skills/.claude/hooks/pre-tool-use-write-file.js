// README: hooks/pre-tool-use-write-file/README.md
"use strict";
const fs = require("fs");
const path = require("path");
const guard = require("../tools/skill-guard/skill-guard.js");

const EVENT = "PreToolUse";
const PROMPT_DIR = path.join(__dirname, "pre-tool-use-write-file");

function readPrompt(fileName) {
  return fs.readFileSync(path.join(PROMPT_DIR, fileName), "utf8");
}

function blockUnguidedSkillWrite(input) {
  const ti = input.tool_input || {};
  const filePath = ti.file_path || ti.notebook_path;
  const kind = guard.kindOf(filePath);
  if (kind === null) return [];
  if (guard.allowed(input, kind)) return [];
  return [
    {
      kind: "violation",
      source: "blockUnguidedSkillWrite",
      text:
        guard.relative(path.resolve(filePath)) +
        " は、テスト計画書を持つスキルのファイルです。このファイルは、次のスキルの手順の中でだけ書き換えられます: " +
        guard.WRITERS[kind].join("、") +
        "。書き換えは止めました。テストの不合格から直すときは、そのスキルを呼んでください。",
    },
  ];
}

const CHECKS = [blockUnguidedSkillWrite];

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
