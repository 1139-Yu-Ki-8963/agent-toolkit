// README: hooks/stop/README.md
"use strict";
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const EVENT = "Stop";
const TARGETS = ["ui/server.mjs", "ui/index.html", "ui/段階ごとのスキルと規約.json", "ui/はじめに.md", "ui/デザイントークン.css"];
const REASON_FILE = "ui/tests/テストを足さない理由.md";

function findFactory(input) {
  const candidates = [process.env.CLAUDE_PROJECT_DIR, path.join(os.homedir(), "Projects", "skill-factory")].filter(Boolean);
  const dir = candidates.find((d) => fs.existsSync(path.join(d, "ui", "tests", "run-auto.sh")));
  if (!dir) return null;
  let transcript = "";
  try {
    transcript = fs.readFileSync(input.transcript_path, "utf8");
  } catch (e) {
    return null;
  }
  return transcript.includes(dir) ? dir : null;
}

function currentHash(dir, target) {
  const file = path.join(dir, target);
  return fs.existsSync(file) ? crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex") : "";
}

function latestRecord(dir) {
  const tests = path.join(dir, "ui", "tests");
  const folders = fs.readdirSync(tests).filter((name) => /^\d{4}-\d\d-\d\d-\d+$/.test(name) && fs.existsSync(path.join(tests, name, "判定の記録.md"))).sort();
  return folders.length ? fs.readFileSync(path.join(tests, folders[folders.length - 1], "判定の記録.md"), "utf8") : null;
}

function checkTestsRun(input) {
  const dir = findFactory(input);
  if (!dir) return [];
  const record = latestRecord(dir);
  const stale = TARGETS.filter((t) => !record || !record.includes(`- SHA-256 ${t}: ${currentHash(dir, t)}`));
  const failed = record && !record.includes("合否(既知の不合格を除く): 新しい不合格なし");
  if (stale.length === 0 && !failed) return [];
  const why = stale.length ? `次のファイルを変えたあとに流していない: ${stale.join("、")}` : "最新の判定の記録が不合格か判定できないものを持つ";
  return [{ kind: "violation", source: "checkTestsRun", text: `${why}。${dir} で bash ui/tests/run-auto.sh を流し、すべて合格してから回答を終える。` }];
}

function changedFiles(dir, paths) {
  const r = spawnSync("git", ["status", "--porcelain", "--no-renames", "-z", "--untracked-files=all", "--", ...paths], { cwd: dir, encoding: "utf8" });
  if (r.status !== 0) return null;
  return r.stdout.split("\0").filter(Boolean).map((line) => line.slice(3));
}

function checkTestsChanged(input) {
  const dir = findFactory(input);
  if (!dir) return [];
  const code = changedFiles(dir, TARGETS);
  if (!code || code.length === 0) return [];
  const tests = changedFiles(dir, ["ui/tests/*.mjs", "ui/tests/*.sh", "ui/tests/lib"]);
  if (tests && tests.length > 0) return [];
  const reasonFile = path.join(dir, REASON_FILE);
  const reasons = fs.existsSync(reasonFile) ? fs.readFileSync(reasonFile, "utf8") : "";
  const unexplained = code.filter((f) => !reasons.includes(currentHash(dir, f)));
  if (unexplained.length === 0) return [];
  return [{ kind: "violation", source: "checkTestsChanged", text: `次のファイルを変えたのに、ui/tests/ のテストのプログラムが直前のコミットと同じ: ${unexplained.join("、")}。変えた振る舞いを確かめるテストを足す。振る舞いを変えない変更のときは、${REASON_FILE} に、そのファイルの SHA-256 と理由を 1 行で書く。` }];
}

const CHECKS = [checkTestsRun, checkTestsChanged];

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

  const results = CHECKS.flatMap((check) => check(input));
  if (results.length === 0) process.exit(0);

  process.stderr.write(summarize(results) + "\n");
  process.exit(2);
}

let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => (raw += chunk));
process.stdin.on("end", () => main(raw));
