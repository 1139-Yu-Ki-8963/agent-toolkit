// README: hooks/stop/README.md
"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const SCRIPT = path.join(__dirname, "..", "stop.js");
const TARGETS = ["server.mjs", "index.html", "段階ごとのスキルと規約.json", "はじめに.md", "デザイントークン.css"];

const sha = (text) => crypto.createHash("sha256").update(text).digest("hex");

function git(dir, ...args) {
  const r = spawnSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "core.hooksPath=/dev/null", ...args], { cwd: dir, encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
}

// 4 つのファイルとテストのプログラムをコミットした skill-factory の写しを作る
function factory() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "hook-stop-"));
  fs.mkdirSync(path.join(dir, "ui", "tests"), { recursive: true });
  for (const t of TARGETS) fs.writeFileSync(path.join(dir, "ui", t), "元の中身");
  fs.writeFileSync(path.join(dir, "ui", "tests", "run-auto.sh"), "");
  fs.writeFileSync(path.join(dir, "ui", "tests", "test-screen.mjs"), "元のテスト");
  git(dir, "init", "-q");
  git(dir, "add", ".");
  git(dir, "commit", "-q", "-m", "元");
  return dir;
}

function record(dir, stamp, result = "新しい不合格なし") {
  const lines = TARGETS.map((t) => `- SHA-256 ui/${t}: ${sha(fs.readFileSync(path.join(dir, "ui", t), "utf8"))}`);
  const folder = path.join(dir, "ui", "tests", stamp);
  fs.mkdirSync(folder, { recursive: true });
  fs.writeFileSync(path.join(folder, "判定の記録.md"), [...lines, `- 合否(既知の不合格を除く): ${result}`].join("\n") + "\n");
}

function run(dir, over = {}) {
  const transcript = path.join(dir, "transcript.jsonl");
  fs.writeFileSync(transcript, over.transcript === undefined ? `${dir}/ui/server.mjs\n` : over.transcript);
  const input = { hook_event_name: "Stop", transcript_path: transcript, stop_hook_active: false, ...over.input };
  const r = spawnSync(process.execPath, [SCRIPT], { input: JSON.stringify(input), encoding: "utf8", env: { ...process.env, CLAUDE_PROJECT_DIR: dir, HOME: dir } });
  return { code: r.status, stdout: r.stdout, stderr: r.stderr };
}

test("checkTestsRun: 結果を返す", () => {
  const dir = factory();
  let r = run(dir);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /checkTestsRun/);
  record(dir, "2026-01-01-000000");
  fs.writeFileSync(path.join(dir, "ui", "server.mjs"), "直した中身");
  fs.writeFileSync(path.join(dir, "ui", "tests", "test-screen.mjs"), "直したテスト");
  r = run(dir);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /checkTestsRun/);
  record(dir, "2026-01-01-000001", "不合格か判定できないものあり");
  r = run(dir);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /checkTestsRun/);
});

test("checkTestsRun: 結果を返さない", () => {
  const dir = factory();
  record(dir, "2026-01-01-000000", "不合格か判定できないものあり");
  record(dir, "2026-01-01-000001");
  const r = run(dir);
  assert.equal(r.code, 0);
  assert.equal(r.stderr, "");
});

test("checkTestsChanged: 結果を返す", () => {
  const dir = factory();
  fs.writeFileSync(path.join(dir, "ui", "index.html"), "直した中身");
  record(dir, "2026-01-01-000000");
  const r = run(dir);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /checkTestsChanged/);
  assert.doesNotMatch(r.stderr, /checkTestsRun/);
});

test("checkTestsChanged: 結果を返さない", () => {
  const dir = factory();
  fs.writeFileSync(path.join(dir, "ui", "index.html"), "直した中身");
  record(dir, "2026-01-01-000000");
  fs.writeFileSync(path.join(dir, "ui", "tests", "test-screen.mjs"), "直したテスト");
  assert.equal(run(dir).code, 0);
  // テストを変えないときは、今の SHA-256 と理由を書くと通る
  fs.writeFileSync(path.join(dir, "ui", "tests", "test-screen.mjs"), "元のテスト");
  assert.equal(run(dir).code, 2);
  fs.writeFileSync(path.join(dir, "ui", "tests", "テストを足さない理由.md"), `${sha("直した中身")}: 表示の文の変更で、振る舞いを変えない\n`);
  assert.equal(run(dir).code, 0);
});

test("stop_hook_active が true のときは検査をしない", () => {
  const dir = factory();
  fs.writeFileSync(path.join(dir, "ui", "server.mjs"), "直した中身");
  assert.equal(run(dir, { input: { stop_hook_active: true } }).code, 0);
});

test("会話の記録が skill-factory のパスを持たないときは検査をしない", () => {
  const dir = factory();
  fs.writeFileSync(path.join(dir, "ui", "server.mjs"), "直した中身");
  assert.equal(run(dir, { transcript: "ほかのプロジェクトの会話\n" }).code, 0);
});

test("標準入力が JSON でないときは終了コード 0", () => {
  const r = spawnSync(process.execPath, [SCRIPT], { input: "{", encoding: "utf8" });
  assert.equal(r.status, 0);
});
