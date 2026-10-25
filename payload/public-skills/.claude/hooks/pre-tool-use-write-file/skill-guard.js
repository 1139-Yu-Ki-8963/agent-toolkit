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

// 守るファイルの種類ごとに、書き換えてよいスキルの名前
const WRITERS = {
  skill: ["fixing-skill", "revising-skill-writing-rule"],
  plan: ["fixing-test-plan", "designing-skill-test-cases", "designing-skill-test-scenarios"],
};

function guardedSkillNames() {
  if (!fs.existsSync(TESTS_DIR)) return [];
  return fs
    .readdirSync(TESTS_DIR, { withFileTypes: true })
    .filter((e) => e.isDirectory() && fs.existsSync(path.join(TESTS_DIR, e.name, PLAN_NAME)))
    .map((e) => e.name)
    .filter((name) => fs.existsSync(path.join(SKILLS_DIR, name)));
}

function listFiles(dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...listFiles(full));
    else files.push(full);
  }
  return files;
}

// 守るファイルの絶対パスと種類の一覧
function guardedFiles() {
  const result = [];
  for (const name of guardedSkillNames()) {
    for (const f of listFiles(path.join(SKILLS_DIR, name))) result.push({ file: f, kind: "skill" });
    result.push({ file: path.join(TESTS_DIR, name, PLAN_NAME), kind: "plan" });
  }
  return result;
}

function kindOf(filePath) {
  if (typeof filePath !== "string") return null;
  const abs = path.resolve(filePath);
  for (const name of guardedSkillNames()) {
    if (abs === path.join(TESTS_DIR, name, PLAN_NAME)) return "plan";
    if (abs.startsWith(path.join(SKILLS_DIR, name) + path.sep)) return "skill";
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
  return path.relative(HOME, file);
}

module.exports = { WRITERS, guardedFiles, kindOf, allowed, hashOf, baselinePath, relative };
