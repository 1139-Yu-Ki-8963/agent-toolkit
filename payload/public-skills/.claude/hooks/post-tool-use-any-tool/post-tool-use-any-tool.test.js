// README: hooks/post-tool-use-any-tool/README.md
"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const SCRIPT = path.join(__dirname, "..", "post-tool-use-any-tool.js");

function guardedHome() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "hook-test-"));
  fs.mkdirSync(path.join(home, "skills", "foo"), { recursive: true });
  fs.mkdirSync(path.join(home, "skills", "tests", "foo"), { recursive: true });
  fs.writeFileSync(path.join(home, "skills", "foo", "SKILL.md"), "# foo\n");
  fs.writeFileSync(path.join(home, "skills", "tests", "foo", "テスト計画書.md"), "# plan\n");
  return home;
}

function run(home, sessionId) {
  const input = { hook_event_name: "PostToolUse", session_id: sessionId, transcript_path: "/dev/null", tool_name: "Read", tool_input: {} };
  const r = spawnSync(process.execPath, [SCRIPT], {
    input: JSON.stringify(input),
    encoding: "utf8",
    env: { ...process.env, SKILL_GUARD_HOME: home },
  });
  return { code: r.status, stdout: r.stdout, stderr: r.stderr };
}

function sessionId() {
  return "hook-test-" + process.pid + "-" + Date.now() + "-" + Math.random().toString(36).slice(2);
}

test("detectUnguidedSkillChange: 結果を返す", () => {
  const home = guardedHome();
  const id = sessionId();
  assert.equal(run(home, id).code, 0);
  fs.appendFileSync(path.join(home, "skills", "foo", "SKILL.md"), "changed\n");
  const r = run(home, id);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /detectUnguidedSkillChange/);
  assert.match(r.stderr, /skills\/foo\/SKILL\.md/);
});

test("detectUnguidedSkillChange: 結果を返さない", () => {
  const home = guardedHome();
  const id = sessionId();
  assert.equal(run(home, id).code, 0);
  const r = run(home, id);
  assert.equal(r.code, 0);
  assert.equal(r.stderr, "");
});
