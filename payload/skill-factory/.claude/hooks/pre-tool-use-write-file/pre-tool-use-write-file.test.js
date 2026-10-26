// README: hooks/pre-tool-use-write-file/README.md
"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const SCRIPT = path.join(__dirname, "..", "pre-tool-use-write-file.js");

function guardedHome() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "hook-test-"));
  fs.mkdirSync(path.join(home, "skills", "foo"), { recursive: true });
  fs.mkdirSync(path.join(home, "skills", "tests", "foo"), { recursive: true });
  fs.writeFileSync(path.join(home, "skills", "foo", "SKILL.md"), "# foo\n");
  fs.writeFileSync(path.join(home, "skills", "tests", "foo", "テスト計画書.md"), "# plan\n");
  return home;
}

function outputHome() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "hook-test-"));
  fs.mkdirSync(path.join(home, "output", "foo", "tests"), { recursive: true });
  fs.writeFileSync(path.join(home, "output", "foo", "SKILL.md"), "# foo\n");
  fs.writeFileSync(path.join(home, "output", "foo", "要件定義書.md"), "# req\n");
  fs.writeFileSync(path.join(home, "output", "foo", "tests", "テスト計画書.md"), "# plan\n");
  return home;
}

function run(home, filePath) {
  const input = { hook_event_name: "PreToolUse", transcript_path: "/dev/null", tool_input: { file_path: filePath } };
  const r = spawnSync(process.execPath, [SCRIPT], {
    input: JSON.stringify(input),
    encoding: "utf8",
    env: { ...process.env, SKILL_GUARD_HOME: home, SKILL_GUARD_PROJECT: home },
  });
  return { code: r.status, stdout: r.stdout, stderr: r.stderr };
}

test("blockUnguidedSkillWrite: 結果を返す", () => {
  const home = guardedHome();
  const r = run(home, path.join(home, "skills", "foo", "SKILL.md"));
  assert.equal(r.code, 2);
  assert.match(r.stderr, /blockUnguidedSkillWrite/);
});

test("blockUnguidedSkillWrite: 結果を返さない", () => {
  const home = guardedHome();
  const r = run(home, path.join(home, "docs", "x.md"));
  assert.equal(r.code, 0);
  assert.equal(r.stderr, "");
});

test("blockUnguidedSkillWrite: output のスキルで結果を返す", () => {
  const home = outputHome();
  const skill = run(home, path.join(home, "output", "foo", "SKILL.md"));
  assert.equal(skill.code, 2);
  assert.match(skill.stderr, /output\/foo\/SKILL\.md/);
  assert.equal(run(home, path.join(home, "output", "foo", "tests", "テスト計画書.md")).code, 2);
});

test("blockUnguidedSkillWrite: output の設計の文書とテストの記録で結果を返さない", () => {
  const home = outputHome();
  assert.equal(run(home, path.join(home, "output", "foo", "要件定義書.md")).code, 0);
  assert.equal(run(home, path.join(home, "output", "foo", "tests", "2026-10-26-1500", "判定の記録.md")).code, 0);
});
