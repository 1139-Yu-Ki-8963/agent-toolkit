// README: hooks/post-tool-use-write-file/README.md
"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const SCRIPT = path.join(__dirname, "..", "post-tool-use-write-file.js");

function run(input) {
  const r = spawnSync(process.execPath, [SCRIPT], { input: JSON.stringify(input), encoding: "utf8" });
  return { code: r.status, stdout: r.stdout, stderr: r.stderr };
}

function tmp() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "hook-test-"));
}

function write(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text);
  return file;
}

function post(filePath) {
  return { hook_event_name: "PostToolUse", tool_input: { file_path: filePath } };
}

test("remindPinkElephants: 結果を返す", () => {
  const f = write(path.join(tmp(), "rules", "x", "x-rule.md"), "# x\n");
  const r = run(post(f));
  assert.equal(r.code, 0);
  assert.match(r.stdout, /remindPinkElephants/);
});

test("remindPinkElephants: 結果を返さない", () => {
  const f = write(path.join(tmp(), "docs", "x.md"), "# x\n");
  const r = run(post(f));
  assert.equal(r.code, 0);
  assert.doesNotMatch(r.stdout + r.stderr, /remindPinkElephants/);
});

test("checkLinks: 結果を返す", () => {
  const f = write(path.join(tmp(), "docs", "x.md"), "[a](missing.md)\n");
  const r = run(post(f));
  assert.equal(r.code, 2);
  assert.match(r.stderr, /checkLinks/);
});

test("checkLinks: 結果を返さない", () => {
  const dir = tmp();
  write(path.join(dir, "docs", "exists.md"), "# e\n");
  const f = write(path.join(dir, "docs", "x.md"), "[a](exists.md)\n");
  const r = run(post(f));
  assert.equal(r.code, 0);
  assert.doesNotMatch(r.stdout + r.stderr, /checkLinks/);
});

test("checkHookRequires: 結果を返す", () => {
  const f = write(path.join(tmp(), "hooks", "bad.js"), 'const g = require("../tools/g.js");\n');
  const r = run(post(f));
  assert.equal(r.code, 2);
  assert.match(r.stderr, /checkHookRequires/);
});

test("checkHookRequires: 結果を返さない", () => {
  const f = write(path.join(tmp(), "hooks", "good.js"), 'const g = require("./good/g.js");\nconst fs = require("fs");\n');
  const r = run(post(f));
  assert.equal(r.code, 0);
  assert.doesNotMatch(r.stdout + r.stderr, /checkHookRequires/);
});

const README_WITH_TESTS =
  "# x\n\n## 検査\n\n| 検査の名前 | 確かめること | 対象のファイルの条件 | 根拠の規約と規則の観点 | 呼ぶもの | 返す kind | テスト |\n|---|---|---|---|---|---|---|\n| checkA | a | すべて | なし | なし | `violation` | 「checkA: 結果を返す」と「checkA: 結果を返さない」 |\n";

test("checkHookTests: 結果を返す", () => {
  const dir = tmp();
  write(path.join(dir, "hooks", "x", "README.md"), README_WITH_TESTS);
  const f = write(path.join(dir, "hooks", "x.js"), "// x\n");
  const r = run(post(f));
  assert.equal(r.code, 2);
  assert.match(r.stderr, /checkHookTests/);
});

test("checkHookTests: 結果を返さない", () => {
  const dir = tmp();
  write(path.join(dir, "hooks", "x", "README.md"), README_WITH_TESTS);
  write(path.join(dir, "hooks", "x", "x.test.js"), 'test("checkA: 結果を返す");\ntest("checkA: 結果を返さない");\n');
  const f = write(path.join(dir, "hooks", "x.js"), "// x\n");
  const r = run(post(f));
  assert.equal(r.code, 0);
  assert.doesNotMatch(r.stdout + r.stderr, /checkHookTests/);
});

test("requestRuleCheck: 結果を返す", () => {
  const f = write(path.join(tmp(), "docs", "x.md"), "# x\n");
  const r = run(post(f));
  assert.equal(r.code, 0);
  assert.match(r.stdout, /requestRuleCheck/);
});

test("requestRuleCheck: 結果を返さない", () => {
  const f = write(path.join(tmp(), "docs", "x.txt"), "x\n");
  const r = run(post(f));
  assert.equal(r.code, 0);
  assert.equal(r.stdout, "");
});
