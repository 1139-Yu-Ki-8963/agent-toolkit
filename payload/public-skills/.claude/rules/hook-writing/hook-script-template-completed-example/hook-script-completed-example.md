---
paths:
  - .claude/skills/**/*
  - .claude/rules/hook-writing/**/*
---

# hook のスクリプトの完成例

`hooks/post-tool-use-write-file.js` の全文である。

```javascript
// README: hooks/post-tool-use-write-file/README.md
"use strict";
const fs = require("fs");
const path = require("path");

const EVENT = "PostToolUse";
const PROMPT_DIR = path.join(__dirname, "post-tool-use-write-file");

function readPrompt(fileName) {
  return fs.readFileSync(path.join(PROMPT_DIR, fileName), "utf8");
}

function isMarkdown(filePath) {
  return typeof filePath === "string" && filePath.endsWith(".md");
}

function isRule(filePath) {
  return isMarkdown(filePath) && /\/rules\/.+\.md$/.test(filePath);
}

function remindPinkElephants(input) {
  const filePath = input.tool_input && input.tool_input.file_path;
  if (!isRule(filePath)) return [];
  return [{ kind: "prompt", source: "remindPinkElephants", text: readPrompt("remind-pink-elephants.md").replace("<ファイルのパス>", filePath) }];
}

function checkLinks(input, text) {
  const filePath = input.tool_input && input.tool_input.file_path;
  if (!isMarkdown(filePath) || text === null) return [];
  const dir = path.dirname(filePath);
  const broken = [];
  const linkPattern = /\[[^\]]*\]\(([^)\s]+)\)/g;
  let m;
  while ((m = linkPattern.exec(text)) !== null) {
    const target = m[1].split("#")[0];
    if (target === "" || /^[a-z]+:/i.test(target) || target.startsWith("/")) continue;
    if (!fs.existsSync(path.resolve(dir, decodeURI(target)))) broken.push(m[1]);
  }
  if (broken.length === 0) return [];
  return [{ kind: "violation", source: "checkLinks", text: "リンク先のファイルがない: " + broken.join(", ") }];
}

function remindTextWritingRule(input) {
  const filePath = input.tool_input && input.tool_input.file_path;
  if (!isMarkdown(filePath)) return [];
  return [{ kind: "prompt", source: "remindTextWritingRule", text: readPrompt("remind-text-writing-rule.md").replace("<ファイルのパス>", filePath) }];
}

const CHECKS = [remindPinkElephants, checkLinks, remindTextWritingRule];

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
  if (filePath && fs.existsSync(filePath)) {
    text = fs.readFileSync(filePath, "utf8");
  }

  const results = CHECKS.flatMap((check) => check(input, text));
  if (results.length === 0) process.exit(0);

  const message = summarize(results);
  const hasViolation = results.some((r) => r.kind === "violation");
  if (hasViolation) {
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
```
