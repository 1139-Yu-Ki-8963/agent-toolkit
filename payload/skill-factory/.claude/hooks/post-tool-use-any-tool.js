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

// 画面の状態のファイル(`<作業のフォルダ>/ui/state.json`)を Write か Edit で書いた直後に、
// 値の組を画面の状態のファイルのインターフェース設計書の章 2 の表と照らし合わせる。表は ui/tests/lib/state-contract.mjs が持つ
function checkStateContract(input, text) {
  const name = input.tool_name;
  const filePath = input.tool_input && input.tool_input.file_path;
  if (name !== "Write" && name !== "Edit") return [];
  if (!filePath || !/[\\/]ui[\\/]state\.json$/.test(filePath) || text === null) return [];
  let state;
  try {
    state = JSON.parse(text);
  } catch (e) {
    return [{ kind: "violation", source: "checkStateContract", text: filePath + " を JSON として読めない。同じ返事の中で書き直してください。" }];
  }
  const projectDir = process.env.CLAUDE_PROJECT_DIR || path.join(__dirname, "..", "..");
  const lib = path.join(projectDir, "ui", "tests", "lib", "state-contract.mjs");
  if (!fs.existsSync(lib)) return [];
  const { stateContractGaps } = require(lib);
  const gaps = stateContractGaps(state);
  if (gaps.length === 0) return [];
  return [
    {
      kind: "violation",
      source: "checkStateContract",
      text:
        filePath +
        " の値の組が、画面の状態のファイルのインターフェース設計書の章 2 の表に合わない: " +
        gaps.join("、") +
        "。同じ返事の中で state.json を書き直してください。",
    },
  ];
}

const CHECKS = [detectUnguidedSkillChange, checkStateContract];

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
