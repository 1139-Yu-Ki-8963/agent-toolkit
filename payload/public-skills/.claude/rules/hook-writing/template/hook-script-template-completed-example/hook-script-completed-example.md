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

function isHookScript(filePath) {
  return typeof filePath === "string" && filePath.endsWith(".js") && /\/hooks\/.+\.js$/.test(filePath);
}

function checkHookRequires(input, text) {
  const filePath = input.tool_input && input.tool_input.file_path;
  if (!isHookScript(filePath) || text === null) return [];
  const hooksDir = filePath.replace(/(\/hooks\/).*$/, "$1");
  const outside = [];
  const requirePattern = /require\(\s*(?:"([^"]*)"|'([^']*)')\s*\)/g;
  let m;
  while ((m = requirePattern.exec(text)) !== null) {
    const target = m[1] !== undefined ? m[1] : m[2];
    if (!target.startsWith(".")) continue;
    const resolved = path.resolve(path.dirname(filePath), target);
    if (!(resolved + path.sep).startsWith(hooksDir)) outside.push(target);
  }
  if (outside.length === 0) return [];
  return [{ kind: "violation", source: "checkHookRequires", text: "hook が hooks/ の外のファイルを読み込んでいる: " + outside.join(", ") + "。規約 hook-writing-rule の規則「hooks/ の中のどこに置くか」により、hook だけが呼ぶファイルは hooks/ の下に置く。" }];
}

const RULES_DIR = path.join(__dirname, "..", "rules");
const ALWAYS_CHECKED_RULES = ["text-writing/text-writing-rule.md"];

function listRuleFiles(dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...listRuleFiles(full));
    else if (entry.name.endsWith(".md") && !full.includes("-completed-example")) files.push(full);
  }
  return files;
}

function readPaths(ruleFile) {
  const text = fs.readFileSync(ruleFile, "utf8");
  const m = text.match(/^---\n([\s\S]*?)\n---/);
  if (!m) return [];
  return [...m[1].matchAll(/^\s*-\s*"?([^"\n]+?)"?\s*$/gm)].map((x) => x[1]);
}

function globToRegExp(glob) {
  const escaped = glob.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  const body = escaped
    .replace(/\*\*\//g, "\u0001")
    .replace(/\*\*/g, "\u0002")
    .replace(/\*/g, "[^/]*")
    .replace(/\u0001/g, "(?:.*/)?")
    .replace(/\u0002/g, ".*");
  return new RegExp("(^|/)" + body + "$");
}

function matchingRules(filePath) {
  const target = filePath.split(path.sep).join("/");
  const matched = listRuleFiles(RULES_DIR).filter((rule) => readPaths(rule).some((glob) => globToRegExp(glob).test(target)));
  const always = ALWAYS_CHECKED_RULES.map((rel) => path.join(RULES_DIR, rel));
  return [...new Set([...always, ...matched])];
}

function requestRuleCheck(input) {
  const filePath = input.tool_input && input.tool_input.file_path;
  if (!isMarkdown(filePath)) return [];
  const rules = matchingRules(filePath).join("\n");
  const text = readPrompt("request-rule-check.md").replace("<ファイルのパス>", filePath).replace("<規約のパスの一覧>", rules);
  return [{ kind: "prompt", source: "requestRuleCheck", text }];
}

const CHECKS = [remindPinkElephants, checkLinks, checkHookRequires, requestRuleCheck];

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
