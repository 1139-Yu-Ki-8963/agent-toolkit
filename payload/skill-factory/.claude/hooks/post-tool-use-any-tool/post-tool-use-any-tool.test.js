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

function outputHome() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "hook-test-"));
  fs.mkdirSync(path.join(home, "output", "foo", "tests"), { recursive: true });
  fs.writeFileSync(path.join(home, "output", "foo", "SKILL.md"), "# foo\n");
  fs.writeFileSync(path.join(home, "output", "foo", "要件定義書.md"), "# req\n");
  fs.writeFileSync(path.join(home, "output", "foo", "tests", "テスト計画書.md"), "# plan\n");
  return home;
}

function run(home, sessionId) {
  const input = { hook_event_name: "PostToolUse", session_id: sessionId, transcript_path: "/dev/null", tool_name: "Read", tool_input: {} };
  const r = spawnSync(process.execPath, [SCRIPT], {
    input: JSON.stringify(input),
    encoding: "utf8",
    env: { ...process.env, SKILL_GUARD_HOME: home, SKILL_GUARD_PROJECT: home },
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

test("detectUnguidedSkillChange: output のスキルで結果を返す", () => {
  const home = outputHome();
  const id = sessionId();
  assert.equal(run(home, id).code, 0);
  fs.appendFileSync(path.join(home, "output", "foo", "SKILL.md"), "changed\n");
  const r = run(home, id);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /output\/foo\/SKILL\.md/);
});

test("detectUnguidedSkillChange: output の設計の文書が変わっても結果を返さない", () => {
  const home = outputHome();
  const id = sessionId();
  assert.equal(run(home, id).code, 0);
  fs.appendFileSync(path.join(home, "output", "foo", "要件定義書.md"), "changed\n");
  assert.equal(run(home, id).code, 0);
});

// 画面の状態のファイルを Write で書いた直後の入力を流す。照らし合わせの表は、このプロジェクトの ui/tests/lib/state-contract.mjs が持つ
const PROJECT = path.join(__dirname, "..", "..", "..");

function writeState(state) {
  const home = guardedHome();
  const file = path.join(home, "output", "w", "ui", "state.json");
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, typeof state === "string" ? state : JSON.stringify(state));
  const input = { hook_event_name: "PostToolUse", session_id: sessionId(), transcript_path: "/dev/null", tool_name: "Write", tool_input: { file_path: file } };
  const r = spawnSync(process.execPath, [SCRIPT], {
    input: JSON.stringify(input),
    encoding: "utf8",
    env: { ...process.env, SKILL_GUARD_HOME: home, SKILL_GUARD_PROJECT: home, CLAUDE_PROJECT_DIR: PROJECT },
  });
  return { code: r.status, stdout: r.stdout, stderr: r.stderr };
}

const fit = JSON.parse(fs.readFileSync(path.join(PROJECT, "ui", "example", "ui", "state.json"), "utf8"));

test("checkStateContract: 結果を返す", () => {
  // 画面 4 なのに questions が null(2026-11-06 に起きた「質問はありません」の不具合の形)
  const r = writeState({ ...fit, screen: "画面 4", questions: null });
  assert.equal(r.code, 2);
  assert.match(r.stderr, /checkStateContract/);
  assert.match(r.stderr, /questions/);
  const broken = writeState("{ not json");
  assert.equal(broken.code, 2);
  assert.match(broken.stderr, /JSON として読めない/);
});

test("checkStateContract: 結果を返さない", () => {
  const r = writeState(fit);
  assert.equal(r.code, 0, r.stderr);
});

// 2026-11-21 の本物の AI のテストで AI が書いた state.json の写し。rounds の最後の回の問い 2 から 5 が、questions.items の同じ問いの choices と results を持たない
const split = JSON.parse(fs.readFileSync(path.join(PROJECT, "ui", "tests", "fixtures", "最後の回の問いが問いの一覧と違う選択肢を持つ state.json"), "utf8"));

test("checkStateContract: 最後の回の問いが問いの一覧と違う選択肢を持つ組で結果を返す", () => {
  const r = writeState(split);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /checkStateContract/);
  assert.match(r.stderr, /番号 2 の問いの choices と違う/);
  // 最後の回の問いを questions.items の問いと同じにすると、結果を返さない
  const fixed = { ...split, rounds: [...split.rounds.slice(0, -1), { ...split.rounds.at(-1), items: split.questions.items.map((i) => ({ ...i, replaced: false })) }] };
  const ok = writeState(fixed);
  assert.equal(ok.code, 0, ok.stderr);
});

// 段階 2 から 8 の画面(インターフェース設計書の章 2 の 2 つ目の表)。段階 1 のキーを null にし、段階 2 から 8 で足すキーを持つ
const stage5 = {
  ...fit,
  stage: 5,
  currentSkill: { name: "foo", order: 1, total: 1, done: 0 },
  artifacts: fit.artifacts.map((a) => ({ ...a, status: a.stage < 5 ? "済み" : a.stage === 5 ? "下書き" : "未着手" })),
  decision: null,
  questions: null,
  rounds: null,
  screen: "指摘の一覧",
  findings: { total: 1, byKind: [{ name: "雛形の違反", count: 1 }], items: [{ file: "SKILL.md", line: 3, rule: "規則 1", text: "違反", fix: "直し方", held: false }], ending: null },
  checkRound: { round: 1, limit: 3 },
  panels: [{ kind: "文書", name: "SKILL.md", path: "skills/foo/SKILL.md", key: null, open: false, isNew: false }],
};

test("checkStateContract: 段階 2 から 8 の画面で結果を返す", () => {
  // 指摘の一覧なのに findings が null
  const r = writeState({ ...stage5, findings: null });
  assert.equal(r.code, 2);
  assert.match(r.stderr, /checkStateContract/);
  assert.match(r.stderr, /findings/);
  // 表にない screen の値
  const unknown = writeState({ ...stage5, screen: "照合と修正を終えた" });
  assert.equal(unknown.code, 2);
  assert.match(unknown.stderr, /章 2 の表にない/);
  // 段階 2 から 8 の画面の decision は聞き返しを持てない
  const askBack = writeState({ ...stage5, screen: "直しの承認", decision: { question: "直してよいですか", choices: ["直す"], replies: [], askBack: true }, fixRecord: { fixes: [], held: [], afterApproval: [] } });
  assert.equal(askBack.code, 2);
  assert.match(askBack.stderr, /聞き返しを持てない/);
  // panels の要素の形が違う
  const panels = writeState({ ...stage5, panels: [{ kind: "表", name: "a" }] });
  assert.equal(panels.code, 2);
  assert.match(panels.stderr, /panels\[0\]/);
});

test("checkStateContract: 段階 2 から 8 の画面で結果を返さない", () => {
  assert.equal(writeState(stage5).code, 0, writeState(stage5).stderr);
  // decision.choices の要素は、文字列とオブジェクトのどちらでもよい
  const approval = {
    ...stage5,
    screen: "直しの承認",
    decision: { question: "直してよいですか", choices: ["直す(推奨)", { label: "やめる", result: "スキルを中止する", recommend: false, recommendReason: null, confirm: true }], replies: [] },
    fixRecord: { fixes: [{ file: "SKILL.md", line: 3, before: "前", after: "後", reason: "規則 1", behaviorChanges: false }], held: [], afterApproval: ["照合し直す"] },
  };
  const r = writeState(approval);
  assert.equal(r.code, 0, r.stderr);
});
