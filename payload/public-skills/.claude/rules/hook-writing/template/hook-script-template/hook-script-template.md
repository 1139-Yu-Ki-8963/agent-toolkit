---
paths:
  - .claude/skills/**/*
  - .claude/rules/hook-writing/**/*
---

# hook のスクリプトの雛形

## 使う場面

`hooks/` の直下のスクリプトを書くとき。

## 省ける部分

雛形の本文のうち、`// 【` で始まる注釈の行は、書く人が入れる部分を示す。書く人は、その注釈の行を、注釈が示す中身に置き換える。発火点が Stop 以外のときは、`stop_hook_active` の判定の行を省く。

## 雛形の本文

```javascript
// README: hooks/<スクリプトの名前>/README.md
"use strict";
const fs = require("fs");
const path = require("path");

const EVENT = "<発火点の名前>";
const PROMPT_DIR = path.join(__dirname, "<スクリプトの名前>");

function readPrompt(fileName) {
  return fs.readFileSync(path.join(PROMPT_DIR, fileName), "utf8");
}

// 【検査の関数。1 つの検査につき 1 つの関数。引数は input(標準入力の JSON)と text(変えたファイルの全文。PostToolUse 以外では null)。
//   返り値は { kind: "violation" | "prompt", source: "<検査の名前>", text: "<AI に渡す文>" } の配列】

const CHECKS = [
  // 【検査の関数の名前を、動かす順に並べる】
];

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
  if (input.stop_hook_active === true) process.exit(0);

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
```
