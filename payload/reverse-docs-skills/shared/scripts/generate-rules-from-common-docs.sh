#!/usr/bin/env bash
set -euo pipefail

# 構造化された共通規約4文書から、対象リポジトリ向けruleと所有indexを決定的に生成する。
# 対象リポジトリは --apply 指定時だけ更新する。既定はdry-run。

node - "$@" <<'NODE'
const fs = require("fs");
const os = require("os");
const path = require("path");
const crypto = require("crypto");

const GENERATED_BY = "generate-rules-from-common-docs.sh";
const INDEX_REL = ".claude/rules/generated/index.json";
const SOURCE_FILES = [
  "共通規約/コーディング規約.md",
  "共通規約/命名規約.md",
  "共通規約/ディレクトリ構成規約.md",
  "共通規約/コンポーネント設計規約.md",
];

function fail(message) {
  throw new Error(message);
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function bytewise(a, b) {
  return Buffer.compare(Buffer.from(a), Buffer.from(b));
}

function normalizeDocument(text) {
  return text.replace(/\r\n?/g, "\n").replace(/\n+$/g, "") + "\n";
}

function scalar(cell) {
  const value = cell.trim();
  return /^`[^`]*`$/.test(value) ? value.slice(1, -1) : value;
}

function parseRows(sourcePath, text) {
  const normalized = normalizeDocument(text);
  const lines = normalized.split("\n");
  const heading = lines.findIndex((line) => line.trim() === "## AI設定資産への変換");
  if (heading < 0) return { normalized, rows: null };
  const rows = [];
  let inTable = false;
  for (let i = heading + 1; i < lines.length; i += 1) {
    const line = lines[i];
    if (/^##\s+/.test(line)) break;
    if (!line.startsWith("|")) {
      if (inTable && line.trim() !== "") break;
      continue;
    }
    const cells = line.slice(1, line.endsWith("|") ? -1 : undefined).split("|").map((v) => v.trim());
    if (cells.every((v) => /^:?-+:?$/.test(v))) {
      inTable = true;
      continue;
    }
    if (cells.join("|") === "規約キー|対象パス|強制区分|規約要点|違反時手順") {
      inTable = true;
      continue;
    }
    if (!inTable) continue;
    if (cells.length !== 5) fail(`${sourcePath}:${i + 1}: 構造化行は5列である必要があります`);
    const [key, targetPath, enforcement, summary, remediation] = cells.map(scalar);
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(key)) fail(`${sourcePath}:${i + 1}: 不正な規約キー: ${key}`);
    if (!targetPath) fail(`${sourcePath}:${i + 1}: 対象パスが空です`);
    if (!["advisory", "block"].includes(enforcement)) fail(`${sourcePath}:${i + 1}: 不正な強制区分: ${enforcement}`);
    if (!summary || !remediation) fail(`${sourcePath}:${i + 1}: 規約要点または違反時手順が空です`);
    rows.push({ enforcement, key, remediation, summary, targetPath, sourcePath });
  }
  if (rows.length === 0) fail(`${sourcePath}: 構造化行がありません`);
  return { normalized, rows };
}

function yaml(value) {
  return JSON.stringify(String(value));
}

function ruleContent(entry) {
  return [
    "---",
    `generatedBy: ${GENERATED_BY}`,
    `ruleKey: ${yaml(entry.key)}`,
    `sourcePath: ${yaml(entry.sourcePath)}`,
    `sourceSha256: ${entry.sourceSha256}`,
    `targetPath: ${yaml(entry.targetPath)}`,
    `declaredEnforcement: ${entry.declaredEnforcement}`,
    "mechanicalEnforcement: false",
    "---",
    "",
    `# ${entry.summary}`,
    "",
    "## 適用対象",
    "",
    `\`${entry.targetPath}\``,
    "",
    "## 規約要点",
    "",
    entry.summary,
    "",
    "## 違反時手順",
    "",
    entry.remediation,
    "",
  ].join("\n");
}

function buildModel(outputDir) {
  const allRows = [];
  const sourceDocumentSha256 = {};
  for (const sourcePath of SOURCE_FILES) {
    const absolute = path.join(outputDir, ...sourcePath.split("/"));
    if (!fs.existsSync(absolute) || !fs.statSync(absolute).isFile()) fail(`入力文書がありません: ${absolute}`);
    const parsed = parseRows(sourcePath, fs.readFileSync(absolute, "utf8"));
    sourceDocumentSha256[sourcePath] = sha256(Buffer.from(parsed.normalized, "utf8"));
    // 「## AI設定資産への変換」見出しが無い文書は自由記述のみとみなし、rule.md化せずpath参照のみ扱う（rowsがnull）。
    if (parsed.rows) allRows.push(...parsed.rows);
  }
  const seen = new Set();
  for (const row of allRows) {
    if (seen.has(row.key)) fail(`規約キーが重複しています: ${row.key}`);
    seen.add(row.key);
  }
  const entries = allRows.map((row) => {
    const canonical = {
      enforcement: row.enforcement,
      key: row.key,
      remediation: row.remediation,
      summary: row.summary,
      targetPath: row.targetPath,
    };
    return {
      key: row.key,
      rulePath: `.claude/rules/generated/${row.key}/rule.md`,
      sourcePath: row.sourcePath,
      sourceSha256: sha256(Buffer.from(JSON.stringify(canonical), "utf8")),
      targetPath: row.targetPath,
      declaredEnforcement: row.enforcement,
      mechanicalEnforcement: false,
      summary: row.summary,
      remediation: row.remediation,
    };
  }).sort((a, b) => bytewise(a.key, b.key));
  const sortedHashes = {};
  Object.keys(sourceDocumentSha256).sort(bytewise).forEach((key) => {
    sortedHashes[key] = sourceDocumentSha256[key];
  });
  return { generatedBy: GENERATED_BY, schemaVersion: 1, sourceDocumentSha256: sortedHashes, entries };
}

function readIndex(targetRepo) {
  const absolute = path.join(targetRepo, ...INDEX_REL.split("/"));
  if (!fs.existsSync(absolute)) return null;
  let index;
  try {
    index = JSON.parse(fs.readFileSync(absolute, "utf8"));
  } catch (error) {
    fail(`既存indexがJSONとして不正です: ${error.message}`);
  }
  if (index.generatedBy !== GENERATED_BY) fail("既存indexのgeneratedBy markerが不正です");
  if (index.schemaVersion !== 1) fail("既存indexのschemaVersionが不正です");
  if (!index.sourceDocumentSha256 || typeof index.sourceDocumentSha256 !== "object" || Array.isArray(index.sourceDocumentSha256)) {
    fail("既存indexのsourceDocumentSha256が不正です");
  }
  for (const [sourcePath, hash] of Object.entries(index.sourceDocumentSha256)) {
    if (!SOURCE_FILES.includes(sourcePath) || !/^[0-9a-f]{64}$/.test(hash)) fail(`既存indexの文書hashが不正です: ${sourcePath}`);
  }
  if (!Array.isArray(index.entries)) fail("既存indexのentriesが不正です");
  const keys = new Set();
  for (const entry of index.entries) {
    if (!entry || typeof entry !== "object" || typeof entry.key !== "string" || keys.has(entry.key)) {
      fail("既存indexに不正または重複したentryがあります");
    }
    keys.add(entry.key);
    const expectedPath = `.claude/rules/generated/${entry.key}/rule.md`;
    if (entry.rulePath !== expectedPath) fail(`既存indexのrulePathが所有契約と矛盾します: ${entry.key}`);
    if (!SOURCE_FILES.includes(entry.sourcePath) ||
        !/^[0-9a-f]{64}$/.test(entry.sourceSha256) ||
        !["advisory", "block"].includes(entry.declaredEnforcement) ||
        entry.mechanicalEnforcement !== false ||
        typeof entry.targetPath !== "string" ||
        typeof entry.summary !== "string" ||
        typeof entry.remediation !== "string") {
      fail(`既存indexのentry schemaが不正です: ${entry.key}`);
    }
    const absoluteRule = path.join(targetRepo, ...entry.rulePath.split("/"));
    if (!fs.existsSync(absoluteRule) || !fs.statSync(absoluteRule).isFile()) fail(`既存indexの所有ruleがありません: ${entry.rulePath}`);
    const content = fs.readFileSync(absoluteRule, "utf8");
    if (!content.startsWith("---\n") ||
        !content.includes(`\ngeneratedBy: ${GENERATED_BY}\n`) ||
        !content.includes(`\nruleKey: ${yaml(entry.key)}\n`) ||
        !content.includes(`\nsourceSha256: ${entry.sourceSha256}\n`) ||
        !content.includes(`\ndeclaredEnforcement: ${entry.declaredEnforcement}\n`) ||
        !content.includes("\nmechanicalEnforcement: false\n")) {
      fail(`既存indexと所有ruleのmarkerが矛盾します: ${entry.rulePath}`);
    }
  }
  return index;
}

function copyTree(source, destination) {
  if (!fs.existsSync(source)) {
    fs.mkdirSync(destination, { recursive: true });
    return;
  }
  fs.cpSync(source, destination, { recursive: true, force: false, errorOnExist: false, verbatimSymlinks: true });
}

function createExpectedTree(outputDir, targetRepo, stagingParent) {
  const model = buildModel(outputDir);
  const previous = readIndex(targetRepo);
  const currentRoot = path.join(targetRepo, ".claude", "rules", "generated");
  fs.mkdirSync(stagingParent, { recursive: true });
  const staging = fs.mkdtempSync(path.join(stagingParent, ".generated-rules.staging."));
  try {
    copyTree(currentRoot, staging);
    const previouslyOwned = new Set();
    if (previous) {
      for (const entry of previous.entries) {
        previouslyOwned.add(entry.rulePath);
        const ownedRule = path.join(staging, entry.key, "rule.md");
        fs.rmSync(ownedRule, { force: true });
        const ownedDirectory = path.dirname(ownedRule);
        if (fs.existsSync(ownedDirectory) && fs.readdirSync(ownedDirectory).length === 0) fs.rmdirSync(ownedDirectory);
      }
      fs.rmSync(path.join(staging, "index.json"), { force: true });
    }
    for (const entry of model.entries) {
      const file = path.join(staging, entry.key, "rule.md");
      if (fs.existsSync(file) && !previouslyOwned.has(entry.rulePath)) {
        fail(`生成外fileと出力pathが衝突します: ${entry.rulePath}`);
      }
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, ruleContent(entry), "utf8");
    }
    fs.writeFileSync(path.join(staging, "index.json"), JSON.stringify(model, null, 2) + "\n", "utf8");
    return { model, staging, currentRoot };
  } catch (error) {
    fs.rmSync(staging, { recursive: true, force: true });
    throw error;
  }
}

function records(root) {
  const result = [];
  function visit(relative) {
    const absolute = relative ? path.join(root, relative) : root;
    if (!fs.existsSync(absolute)) return;
    const stat = fs.lstatSync(absolute);
    if (stat.isSymbolicLink()) {
      result.push(`${relative}\tlink\t${fs.readlinkSync(absolute)}`);
    } else if (stat.isDirectory()) {
      for (const name of fs.readdirSync(absolute).sort(bytewise)) visit(relative ? `${relative}/${name}` : name);
    } else if (stat.isFile()) {
      result.push(`${relative}\tfile\t${(stat.mode & 0o777).toString(8)}\t${sha256(fs.readFileSync(absolute))}`);
    }
  }
  visit("");
  return result;
}

function sameTree(a, b) {
  return JSON.stringify(records(a)) === JSON.stringify(records(b));
}

function applyTree(staging, currentRoot) {
  const parent = path.dirname(currentRoot);
  const backup = path.join(parent, `.generated-rules.backup.${process.pid}.${Date.now()}`);
  let movedCurrent = false;
  try {
    if (fs.existsSync(currentRoot)) {
      fs.renameSync(currentRoot, backup);
      movedCurrent = true;
    }
    fs.renameSync(staging, currentRoot);
    if (movedCurrent) fs.rmSync(backup, { recursive: true, force: true });
  } catch (error) {
    if (fs.existsSync(currentRoot)) fs.rmSync(currentRoot, { recursive: true, force: true });
    if (movedCurrent && fs.existsSync(backup)) fs.renameSync(backup, currentRoot);
    throw error;
  }
}

function execute(outputDir, targetRepo, mode) {
  if (!fs.existsSync(outputDir) || !fs.statSync(outputDir).isDirectory()) fail(`output_dirがありません: ${outputDir}`);
  if (!fs.existsSync(targetRepo) || !fs.statSync(targetRepo).isDirectory()) fail(`target_repoがありません: ${targetRepo}`);
  const resolvedTarget = path.resolve(targetRepo);
  const currentRoot = path.join(resolvedTarget, ".claude", "rules", "generated");
  const stagingParent = mode === "apply" ? path.dirname(currentRoot) : os.tmpdir();
  if (mode === "apply") fs.mkdirSync(stagingParent, { recursive: true });
  const expected = createExpectedTree(path.resolve(outputDir), resolvedTarget, stagingParent);
  try {
    if (mode === "check") {
      if (!sameTree(expected.staging, expected.currentRoot)) fail("generated rule treeが共通規約文書と一致しません");
      console.log(`CHECK PASS: ${expected.model.entries.length} rules`);
      return;
    }
    if (mode === "apply") {
      applyTree(expected.staging, expected.currentRoot);
      console.log(`APPLY PASS: ${expected.model.entries.length} rules`);
      return;
    }
    console.log(`DRY-RUN PASS: ${expected.model.entries.length} rules（target_repoは未変更）`);
  } finally {
    if (fs.existsSync(expected.staging)) fs.rmSync(expected.staging, { recursive: true, force: true });
  }
}

function fixtureDocs(root, duplicate = false) {
  const dir = path.join(root, "共通規約");
  fs.mkdirSync(dir, { recursive: true });
  const definitions = [
    ["コーディング規約.md", "coding-format"],
    ["命名規約.md", duplicate ? "coding-format" : "naming-files"],
    ["ディレクトリ構成規約.md", "directory-root-layout"],
    ["コンポーネント設計規約.md", "component-props"],
  ];
  for (const [name, key] of definitions) {
    fs.writeFileSync(path.join(dir, name), `# ${name}\n\n## AI設定資産への変換\n\n| 規約キー | 対象パス | 強制区分 | 規約要点 | 違反時手順 |\n|---|---|---|---|---|\n| \`${key}\` | \`**/*\` | \`${key === "component-props" ? "block" : "advisory"}\` | ${key}を守る | ${key}を修正する |\n`, "utf8");
  }
}

function selfTest() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "generate-common-rules-self-test."));
  try {
    const output = path.join(temp, "output");
    const target = path.join(temp, "target");
    fs.mkdirSync(target, { recursive: true });
    fixtureDocs(output);
    const before = records(target);
    execute(output, target, "dry-run");
    if (JSON.stringify(before) !== JSON.stringify(records(target))) fail("dry-runがtarget_repoを変更しました");
    if (fs.readdirSync(target).length !== 0) fail("dry-runが空directoryをtarget_repoへ作成しました");
    execute(output, target, "apply");
    execute(output, target, "check");
    const protectedFile = path.join(target, ".claude", "rules", "generated", "coding-format", "owner-note.txt");
    fs.writeFileSync(protectedFile, "not owned\n", "utf8");
    const first = records(target);
    execute(output, target, "apply");
    if (JSON.stringify(first) !== JSON.stringify(records(target))) fail("再applyがbyte同一ではありません");
    if (fs.readFileSync(protectedFile, "utf8") !== "not owned\n") fail("生成外fileを保護できませんでした");
    const index = JSON.parse(fs.readFileSync(path.join(target, INDEX_REL), "utf8"));
    if (index.entries.length !== 4 || index.entries.some((e) => e.mechanicalEnforcement !== false)) fail("index schemaが期待と不一致です");

    const duplicate = path.join(temp, "duplicate");
    fixtureDocs(duplicate, true);
    let rejected = false;
    try { execute(duplicate, target, "dry-run"); } catch { rejected = true; }
    if (!rejected) fail("文書間の規約キー重複を拒否しませんでした");

    const indexPath = path.join(target, INDEX_REL);
    const valid = fs.readFileSync(indexPath, "utf8");
    for (const mutate of [
      (value) => ({ ...value, generatedBy: "other-generator" }),
      (value) => ({ ...value, schemaVersion: 2 }),
    ]) {
      fs.writeFileSync(indexPath, JSON.stringify(mutate(JSON.parse(valid)), null, 2) + "\n");
      rejected = false;
      try { execute(output, target, "check"); } catch { rejected = true; }
      if (!rejected) fail("不正indexを拒否しませんでした");
      fs.writeFileSync(indexPath, valid);
    }
    console.log("self-test 全項目 PASS");
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

function parseArgs(argv) {
  if (argv.length === 1 && argv[0] === "--self-test") return { selfTest: true };
  if (argv.length < 1) fail("Usage: generate-rules-from-common-docs.sh <output_dir> --target-repo <target_repo> [--apply|--check]");
  const outputDir = argv[0];
  let targetRepo = "";
  let apply = false;
  let check = false;
  for (let i = 1; i < argv.length; i += 1) {
    if (argv[i] === "--target-repo") {
      if (!argv[i + 1]) fail("--target-repoの値がありません");
      targetRepo = argv[++i];
    } else if (argv[i] === "--apply") {
      apply = true;
    } else if (argv[i] === "--check") {
      check = true;
    } else {
      fail(`不明な引数です: ${argv[i]}`);
    }
  }
  if (!targetRepo) fail("--target-repoは必須です");
  if (apply && check) fail("--applyと--checkは同時指定できません");
  return { outputDir, targetRepo, mode: apply ? "apply" : check ? "check" : "dry-run" };
}

try {
  const args = parseArgs(process.argv.slice(2));
  if (args.selfTest) selfTest();
  else execute(args.outputDir, args.targetRepo, args.mode);
} catch (error) {
  console.error(`ERROR: ${error.message}`);
  process.exitCode = 1;
}
NODE
