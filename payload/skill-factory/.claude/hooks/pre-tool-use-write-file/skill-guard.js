// hooks/pre-tool-use-write-file.js と hooks/post-tool-use-any-tool.js が共有する、守るファイルと手順の跡の判定。説明は 2 本の README にある。
"use strict";
const fs = require("fs");
const path = require("path");
const os = require("os");
const crypto = require("crypto");

const HOME = process.env.SKILL_GUARD_HOME || path.join(__dirname, "..", "..");
const SKILLS_DIR = path.join(HOME, "skills");
const TESTS_DIR = path.join(SKILLS_DIR, "tests");
const PLAN_NAME = "テスト計画書.md";
// skill-factory の作業フォルダの output/<スキルの名前>/ に置く、作ったスキルとそのテスト
const PROJECT = process.env.SKILL_GUARD_PROJECT || process.env.CLAUDE_PROJECT_DIR || process.cwd();
const OUTPUT_DIR = path.join(PROJECT, "output");
// output/<スキルの名前>/ の直下で、スキルのファイルとして守らないもの(テストの記録、確認と承認の画面のファイル、設計の文書)
const OUTPUT_NOT_SKILL = ["tests", "ui", "要件定義書.md", "分割設計書.md", "構成の案.md", "依頼の一覧.md"];

// 守るファイルの種類ごとに、書き換えてよいスキルの名前
const WRITERS = {
  skill: ["fixing-skill", "revising-skill-writing-rule"],
  plan: ["fixing-test-plan", "designing-skill-test-cases", "designing-skill-test-scenarios"],
};

// テスト計画書を持つスキルごとの、スキルのフォルダと、テスト計画書のパスと、スキルのファイルとして守らない直下の名前
function guardedSkills() {
  const result = [];
  if (fs.existsSync(TESTS_DIR)) {
    for (const e of fs.readdirSync(TESTS_DIR, { withFileTypes: true })) {
      const plan = path.join(TESTS_DIR, e.name, PLAN_NAME);
      const dir = path.join(SKILLS_DIR, e.name);
      if (e.isDirectory() && fs.existsSync(plan) && fs.existsSync(dir)) result.push({ dir, plan, notSkill: [] });
    }
  }
  if (fs.existsSync(OUTPUT_DIR)) {
    for (const e of fs.readdirSync(OUTPUT_DIR, { withFileTypes: true })) {
      const dir = path.join(OUTPUT_DIR, e.name);
      const plan = path.join(dir, "tests", PLAN_NAME);
      if (e.isDirectory() && fs.existsSync(plan)) result.push({ dir, plan, notSkill: OUTPUT_NOT_SKILL });
    }
  }
  return result;
}

function listFiles(dir, notSkill) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    if (notSkill && notSkill.includes(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...listFiles(full));
    else files.push(full);
  }
  return files;
}

// 守るファイルの絶対パスと種類の一覧
function guardedFiles() {
  const result = [];
  for (const g of guardedSkills()) {
    for (const f of listFiles(g.dir, g.notSkill)) result.push({ file: f, kind: "skill" });
    result.push({ file: g.plan, kind: "plan" });
  }
  return result;
}

function kindOf(filePath) {
  if (typeof filePath !== "string") return null;
  const abs = path.resolve(filePath);
  for (const g of guardedSkills()) {
    if (abs === g.plan) return "plan";
    if (!abs.startsWith(g.dir + path.sep)) continue;
    const top = path.relative(g.dir, abs).split(path.sep)[0];
    if (g.notSkill.includes(top) || top.startsWith(".")) continue;
    return "skill";
  }
  return null;
}

function readOrEmpty(file) {
  try {
    return fs.readFileSync(file, "utf8");
  } catch (e) {
    return "";
  }
}

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// 会話の記録に、そのスキルを使った跡があるか
// 親の会話: Skill のツールの呼び出しか、スラッシュコマンドでの呼び出し
// サブエージェント: その子自身の会話の記録で、そのスキルの SKILL.md を読んだ跡
function usedSkill(input, skillName) {
  const s = escapeRe(skillName);
  const main = readOrEmpty(input.transcript_path || "");
  if (new RegExp('"name":"Skill","input":\\{"skill":"(?:[\\w-]+:)?' + s + '"').test(main)) return true;
  if (new RegExp("<command-name>/?" + s + "</command-name>").test(main)) return true;
  if (input.agent_id && input.transcript_path) {
    const dir = path.join(path.dirname(input.transcript_path), path.basename(input.transcript_path, ".jsonl"), "subagents");
    const sub = readOrEmpty(path.join(dir, "agent-" + input.agent_id + ".jsonl"));
    if (new RegExp('"name":"Read","input":\\{"file_path":"[^"]*/skills/' + s + '/SKILL\\.md"').test(sub)) return true;
  }
  return false;
}

function allowed(input, kind) {
  return WRITERS[kind].some((name) => usedSkill(input, name));
}

function hashOf(file) {
  try {
    return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
  } catch (e) {
    return "なし";
  }
}

function baselinePath(input) {
  return path.join(os.tmpdir(), "skill-guard-" + (input.session_id || "no-session") + ".json");
}

function relative(file) {
  return file.startsWith(OUTPUT_DIR + path.sep) ? path.relative(PROJECT, file) : path.relative(HOME, file);
}

module.exports = { WRITERS, guardedFiles, kindOf, allowed, hashOf, baselinePath, relative };
