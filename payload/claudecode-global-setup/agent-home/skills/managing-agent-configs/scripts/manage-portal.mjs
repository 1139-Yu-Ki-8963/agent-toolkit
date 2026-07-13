#!/usr/bin/env node
// ポータルの生成・検証・配信を単一スクリプトに集約する。
// 実行例:
//   node skills/managing-agent-configs/scripts/manage-portal.mjs generate
//   node skills/managing-agent-configs/scripts/manage-portal.mjs check
//   node skills/managing-agent-configs/scripts/manage-portal.mjs verify [--only <key>,<key>]
//   node skills/managing-agent-configs/scripts/manage-portal.mjs serve

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import http from "node:http";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "../../..");
const PORTAL = path.join(REPO_ROOT, "ai-management-portal");
const HOME_DIR = os.homedir();

const SKILLS_DIR = path.join(REPO_ROOT, "skills");
const ROUTINES_DIR = path.join(REPO_ROOT, "routines");
const SKILL_CATEGORIES_FILE = path.join(PORTAL, "data", "skill-categories.js");
const MANIFEST_FILE = path.join(PORTAL, "data", "manifest.js");
const SKILLS_HTML = path.join(PORTAL, "catalog", "skills.html");
const INDEX_HTML = path.join(PORTAL, "index.html");
const RULES_DIR = path.join(HOME_DIR, ".claude", "rules");
const AGENTS_DIR = path.join(HOME_DIR, ".claude", "agents");
const DICTIONARY_CATEGORIES_FILE = path.join(PORTAL, "data", "dictionary-categories.js");
const DICTIONARIES_HTML = path.join(PORTAL, "catalog", "dictionaries.html");
const GLOBAL_PRH_FILE = path.join(HOME_DIR, ".claude", "rules", "always", "review-checklist", "text-dictionary", "prh.yml");
const PROJECTS_ROOT = path.join(HOME_DIR, "Projects");
const PUBLIC_SET_HTML = path.join(PORTAL, "catalog", "public-set.html");

// ── frontmatter パース ──────────────────────────────────────────

function readFrontmatter(filePath) {
  const text = fs.readFileSync(filePath, "utf8");
  const lines = text.split("\n");
  if (lines[0].trim() !== "---") return null;
  const end = lines.indexOf("---", 1);
  if (end === -1) return null;
  return lines.slice(1, end);
}

function parseSkillMd(filePath) {
  const fmLines = readFrontmatter(filePath);
  if (!fmLines) return null;

  let name = null;
  let descText = null;
  let i = 0;
  while (i < fmLines.length) {
    const line = fmLines[i];
    const m = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (m) {
      const key = m[1];
      const rest = m[2];
      if (key === "name") {
        name = rest.trim().replace(/^["']|["']$/g, "");
        i++;
        continue;
      }
      if (key === "description") {
        const inline = rest.trim();
        if (inline !== "" && !/^[|>][+-]?$/.test(inline)) {
          // 1行引用符付き形式: description: "本文。 TRIGGER when: ... SKIP: ..."
          descText = inline.replace(/^["']|["']$/g, "");
          i++;
          continue;
        }
        // ブロックスカラー形式: description: | の後に続く字下げ行を収集する
        const descLines = [];
        i++;
        while (i < fmLines.length && (fmLines[i].trim() === "" || /^\s+/.test(fmLines[i]))) {
          const trimmed = fmLines[i].trim();
          if (trimmed !== "") descLines.push(trimmed);
          i++;
        }
        descText = descLines.join(" ");
        continue;
      }
    }
    i++;
  }

  descText = descText || "";
  const triggerMatch = descText.match(/TRIGGER when:\s*/);
  let summary;
  let trigger;
  if (!triggerMatch) {
    summary = descText.trim();
    trigger = "";
  } else {
    summary = descText.slice(0, triggerMatch.index).trim();
    trigger = descText.slice(triggerMatch.index + triggerMatch[0].length).trim();
    const skipMatch = trigger.match(/\s*SKIP:\s*/);
    if (skipMatch) trigger = trigger.slice(0, skipMatch.index).trim();
  }
  // summary/trigger はタイトル・ラベルとして表示するため、文末の句点は不要
  summary = summary.replace(/。$/, "");
  trigger = trigger.replace(/。$/, "");

  return { name, summary, trigger };
}

// ── スキル走査 ──────────────────────────────────────────────────

function collectSkills() {
  const entries = fs
    .readdirSync(SKILLS_DIR, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => e.name)
    .sort();

  const skills = [];
  for (const dirName of entries) {
    const skillMd = path.join(SKILLS_DIR, dirName, "SKILL.md");
    if (!fs.existsSync(skillMd)) continue;
    const parsed = parseSkillMd(skillMd);
    if (!parsed) {
      console.error(`警告: ${dirName}/SKILL.md の frontmatter を解析できませんでした`);
      continue;
    }
    const id = parsed.name || dirName;
    // guide フィールド: references/<id>-guide.html が実在すれば true
    const guideFile = path.join(SKILLS_DIR, dirName, "references", `${id}-guide.html`);
    const guide = fs.existsSync(guideFile);
    if (!guide) {
      console.error(`警告: ${id} のガイド HTML が見つかりません（${dirName}/references/${id}-guide.html）`);
    }
    skills.push({
      id,
      dirName,
      summary: parsed.summary,
      trigger: parsed.trigger,
      guide,
    });
  }
  return skills;
}

async function loadSkillCategoryMap() {
  const mod = await import(pathToFileURL(SKILL_CATEGORIES_FILE).href);
  return mod.SKILL_CATEGORY;
}

function resolveCat(skillCategoryMap, id) {
  const entry = skillCategoryMap[id];
  if (entry === undefined) return { cat: "other", sub: undefined };
  if (typeof entry === "string") return { cat: entry, sub: undefined };
  return { cat: entry.cat, sub: entry.sub };
}

function warnUnmappedAndStale(skills, skillCategoryMap) {
  const warnings = [];
  const skillIds = new Set(skills.map((s) => s.id));

  for (const s of skills) {
    if (skillCategoryMap[s.id] === undefined) {
      warnings.push(`未登録: "${s.id}" が data/skill-categories.js の SKILL_CATEGORY に無い（cat: "other" にフォールバック）`);
    }
  }
  for (const key of Object.keys(skillCategoryMap)) {
    if (!skillIds.has(key)) {
      warnings.push(`削除済み疑い: "${key}" が data/skill-categories.js の SKILL_CATEGORY に残っているが、対応する skills/${key}/SKILL.md が見つからない`);
    }
  }
  return warnings;
}

// ── prh 辞書パース ──────────────────────────────────────────────
// YAML パーサは使わない。パターン行に含まれる `#`（例: /\bP[0-9]\b/ の直後の
// コメント等）を YAML パーサがコメント扱いして欠落させる罠があるため、
// 行ベースの専用パーサで抽出する。

function parsePrhFile(filePath, scope) {
  if (!fs.existsSync(filePath)) {
    console.error(`警告: 辞書ファイルが見つかりません（${filePath}）。scope=${scope} をスキップします。`);
    return [];
  }

  const lines = fs.readFileSync(filePath, "utf8").split("\n");
  const entries = [];

  let currentCategory = "other";
  let pendingNote = null;
  let pendingCaution = null;
  let lastField = null; // "note" | "caution" | null（継続行の連結先）
  let currentEntry = null;

  for (const rawLine of lines) {
    const line = rawLine;

    const catMatch = line.match(/^\s*#\s*═+\s*カテゴリ:\s*([a-z0-9-]+)/);
    if (catMatch) {
      currentCategory = catMatch[1];
      pendingNote = null;
      pendingCaution = null;
      lastField = null;
      continue;
    }

    const noteMatch = line.match(/^\s*#\s*推奨:\s*(.*)$/);
    if (noteMatch) {
      pendingNote = noteMatch[1].trim();
      lastField = "note";
      continue;
    }

    const usageMatch = line.match(/^\s*#\s*用途:\s*(.*)$/);
    if (usageMatch) {
      pendingNote = pendingNote ? `${pendingNote} ${usageMatch[1].trim()}` : usageMatch[1].trim();
      lastField = "note";
      continue;
    }

    const cautionMatch = line.match(/^\s*#\s*誤検知注意:\s*(.*)$/);
    if (cautionMatch) {
      pendingCaution = cautionMatch[1].trim();
      lastField = "caution";
      continue;
    }

    // 継続行: 無印インデントコメント（"# ═══" "推奨:" "用途:" "誤検知注意:" のいずれでもない # 行）
    const continuationMatch = line.match(/^\s*#\s{2,}(\S.*)$/);
    if (continuationMatch && lastField) {
      const text = continuationMatch[1].trim();
      if (lastField === "caution") {
        pendingCaution = pendingCaution ? `${pendingCaution} ${text}` : text;
      } else if (lastField === "note") {
        pendingNote = pendingNote ? `${pendingNote} ${text}` : text;
      }
      continue;
    }

    const entryMatch = line.match(/^\s*-\s*expected:\s*(.*)$/);
    if (entryMatch) {
      currentEntry = {
        expected: entryMatch[1].trim(),
        patterns: [],
        note: pendingNote,
        caution: pendingCaution,
        category: currentCategory,
        scope,
      };
      entries.push(currentEntry);
      pendingNote = null;
      pendingCaution = null;
      lastField = null;
      continue;
    }

    const patternMatch = line.match(/^\s{4,}-\s*(.+?)\s*$/);
    if (patternMatch && currentEntry && !entryMatch) {
      currentEntry.patterns.push(patternMatch[1]);
      continue;
    }
  }

  return entries;
}

function discoverProjectPrhFiles() {
  if (!fs.existsSync(PROJECTS_ROOT)) return [];
  return fs.readdirSync(PROJECTS_ROOT, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => ({
      scope: entry.name,
      file: path.join(PROJECTS_ROOT, entry.name, ".claude", "rules", "always", "review-checklist", "text-dictionary", "prh.yml"),
    }))
    .filter(({ file }) => fs.existsSync(file));
}

function collectDictionaries() {
  const global = parsePrhFile(GLOBAL_PRH_FILE, "global");
  const projectEntries = discoverProjectPrhFiles().flatMap(({ scope, file }) => parsePrhFile(file, scope));
  return [...global, ...projectEntries];
}

function countDictionaries() {
  return collectDictionaries().length;
}

// ── コード生成 ──────────────────────────────────────────────────

function buildSkillsArraySource(skills, skillCategoryMap) {
  const rows = skills.map((s) => {
    const { cat, sub } = resolveCat(skillCategoryMap, s.id);
    const fields = [
      `id: ${JSON.stringify(s.id)}`,
      `cat: ${JSON.stringify(cat)}`,
    ];
    if (sub) fields.push(`sub: ${JSON.stringify(sub)}`);
    fields.push(`summary: ${JSON.stringify(s.summary)}`);
    fields.push(`trigger: ${JSON.stringify(s.trigger)}`);
    if (s.guide) fields.push(`guide: true`);
    return `      { ${fields.join(", ")} },`;
  });
  return `    const SKILLS = [\n${rows.join("\n")}\n    ];`;
}

// `</script>` による HTML パーサの早期終了事故を防ぐため、JSON.stringify の
// 出力に含まれる可能性がある `</` を `<\/` にエスケープしてから埋め込む。
function safeJsonStringify(value) {
  return JSON.stringify(value).replace(/<\//g, "<\\/");
}

function buildDictionariesArraySource(entries) {
  const rows = entries.map((e) => {
    const fields = [
      `expected: ${safeJsonStringify(e.expected)}`,
      `patterns: ${safeJsonStringify(e.patterns)}`,
      `note: ${safeJsonStringify(e.note || "")}`,
      `caution: ${safeJsonStringify(e.caution || "")}`,
      `category: ${safeJsonStringify(e.category)}`,
      `scope: ${safeJsonStringify(e.scope)}`,
    ];
    return `      { ${fields.join(", ")} },`;
  });
  return `    const DICTIONARIES = [\n${rows.join("\n")}\n    ];`;
}

function replaceBetweenMarkers(text, startMarker, endMarker, replacement) {
  const startIdx = text.indexOf(startMarker);
  const endIdx = text.indexOf(endMarker);
  if (startIdx === -1 || endIdx === -1 || endIdx < startIdx) {
    throw new Error(`マーカーが見つかりません: ${startMarker} ... ${endMarker}`);
  }
  const before = text.slice(0, startIdx + startMarker.length);
  const after = text.slice(endIdx);
  return `${before}\n${replacement}\n    ${after}`;
}

function replaceInlineBetweenMarkers(text, startMarker, endMarker, replacement) {
  const startIdx = text.indexOf(startMarker);
  const endIdx = text.indexOf(endMarker);
  if (startIdx === -1 || endIdx === -1 || endIdx < startIdx) {
    throw new Error(`マーカーが見つかりません: ${startMarker} ... ${endMarker}`);
  }
  const before = text.slice(0, startIdx + startMarker.length);
  const after = text.slice(endIdx);
  return `${before}${replacement}${after}`;
}

// ── カウント集計 ──────────────────────────────────────────────────

function countSkills() {
  return fs
    .readdirSync(SKILLS_DIR, { withFileTypes: true })
    .filter((e) => e.isDirectory() && fs.existsSync(path.join(SKILLS_DIR, e.name, "SKILL.md")))
    .length;
}

function walkFiles(dir, predicate, acc = []) {
  if (!fs.existsSync(dir)) return acc;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkFiles(full, predicate, acc);
    } else if (predicate(full)) {
      acc.push(full);
    }
  }
  return acc;
}

function countHooks() {
  // rule.md と同一ディレクトリに存在する .sh のみを正規 hook としてカウントする。
  // rules-bash-runner.sh のような runner 本体・lib-*.sh ヘルパー・*.test.sh は
  // hook 本体ではないため除外する。
  const ruleDirs = walkFiles(RULES_DIR, (f) => path.basename(f) === "rule.md").map((f) =>
    path.dirname(f)
  );
  let count = 0;
  for (const dir of ruleDirs) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (
        entry.isFile() &&
        entry.name.endsWith(".sh") &&
        !entry.name.endsWith(".test.sh") &&
        !entry.name.startsWith("lib-")
      ) {
        count += 1;
      }
    }
  }
  return count;
}

function countRules() {
  // ~/.claude/rules/ は <scope>/<topic>/<name>/rule.md の3階層ネスト構造。
  // 任意の深さで rule.md を再帰的に数える（walkFiles は既に再帰探索を実装済み）。
  return walkFiles(RULES_DIR, (f) => path.basename(f) === "rule.md").length;
}

function countSubagents() {
  if (!fs.existsSync(AGENTS_DIR)) return 0;
  return fs
    .readdirSync(AGENTS_DIR, { withFileTypes: true })
    .filter(
      (e) =>
        e.isDirectory() &&
        fs.readdirSync(path.join(AGENTS_DIR, e.name)).some((f) => f.endsWith(".md"))
    ).length;
}

function countRoutines() {
  return walkFiles(ROUTINES_DIR, (f) => f.endsWith("ルーティン設計書.md")).length;
}

function countPublicSet() {
  if (!fs.existsSync(PUBLIC_SET_HTML)) return 0;
  const html = fs.readFileSync(PUBLIC_SET_HTML, "utf8");
  const genStart = html.indexOf("const ITEMS = [");
  const genEnd = html.indexOf("\n    ];", genStart);
  if (genStart === -1 || genEnd === -1) return 0;
  const block = html.slice(genStart, genEnd);
  return (block.match(/\{ id:/g) || []).length;
}

// UTC ではなくローカル日付を使う（UTC とローカルのズレによるドリフト誤検出を防ぐ）
function localToday() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

async function countTools() {
  const mod = await import(pathToFileURL(MANIFEST_FILE).href + "?t=" + Date.now());
  const groups = mod.VISUAL_TOOL_GROUPS;
  const toolsGroup = groups.find((g) => g.id === "tools");
  if (!toolsGroup) return 0;
  const directTools = (toolsGroup.tools || []).length;
  const sectionTools = (toolsGroup.sections || []).reduce((acc, s) => acc + (s.toolIds || []).length, 0);
  return directTools + sectionTools;
}

// ── generate サブコマンド ──────────────────────────────────────

async function cmdGenerate(checkMode = false) {
  const skills = collectSkills();
  const skillCategoryMap = await loadSkillCategoryMap();
  const warnings = warnUnmappedAndStale(skills, skillCategoryMap);
  for (const w of warnings) console.error(`警告: ${w}`);

  // catalog/skills.html の GEN:SKILLS ブロックを再生成
  const skillsHtmlBefore = fs.readFileSync(SKILLS_HTML, "utf8");
  const skillsArraySource = buildSkillsArraySource(skills, skillCategoryMap);
  const skillsHtmlAfter = replaceBetweenMarkers(
    skillsHtmlBefore,
    "// <!-- GEN:SKILLS -->",
    "// <!-- /GEN:SKILLS -->",
    skillsArraySource
  );

  // catalog/dictionaries.html の GEN:DICTIONARIES ブロックを再生成
  const dictionaries = collectDictionaries();
  const dictionariesHtmlBefore = fs.readFileSync(DICTIONARIES_HTML, "utf8");
  const dictionariesArraySource = buildDictionariesArraySource(dictionaries);
  const dictionariesHtmlAfter = replaceBetweenMarkers(
    dictionariesHtmlBefore,
    "// <!-- GEN:DICTIONARIES -->",
    "// <!-- /GEN:DICTIONARIES -->",
    dictionariesArraySource
  );

  // index.html の規模サマリ + PM:UPDATED を再生成
  const counts = {
    skills: countSkills(),
    hooks: countHooks(),
    rules: countRules(),
    subagents: countSubagents(),
    routines: countRoutines(),
    tools: await countTools(),
    dictionaries: countDictionaries(),
    "public-set": countPublicSet(),
  };

  let indexHtmlAfter = fs.readFileSync(INDEX_HTML, "utf8");
  for (const [key, value] of Object.entries(counts)) {
    // routines と tools のマーカーが存在する場合のみ置換
    const startMarker = `<!-- GEN:COUNT:${key} -->`;
    const endMarker = `<!-- /GEN:COUNT:${key} -->`;
    if (indexHtmlAfter.includes(startMarker)) {
      indexHtmlAfter = replaceInlineBetweenMarkers(indexHtmlAfter, startMarker, endMarker, String(value));
    }
  }
  const today = localToday();
  indexHtmlAfter = indexHtmlAfter.replace(
    /<!-- PM:UPDATED -->.*?<!-- \/PM:UPDATED -->/,
    `<!-- PM:UPDATED -->${today}<!-- /PM:UPDATED -->`
  );

  const indexHtmlBefore = fs.readFileSync(INDEX_HTML, "utf8");
  const changed =
    skillsHtmlAfter !== skillsHtmlBefore ||
    dictionariesHtmlAfter !== dictionariesHtmlBefore ||
    indexHtmlAfter !== indexHtmlBefore;

  if (checkMode) {
    if (changed) {
      // 差分箇所を出力
      if (skillsHtmlAfter !== skillsHtmlBefore) {
        console.error("差分あり: catalog/skills.html が skills/ 実体と同期していません。");
        showDiff(skillsHtmlBefore, skillsHtmlAfter, "catalog/skills.html");
      }
      if (dictionariesHtmlAfter !== dictionariesHtmlBefore) {
        console.error("差分あり: catalog/dictionaries.html が prh.yml 実体と同期していません。");
        showDiff(dictionariesHtmlBefore, dictionariesHtmlAfter, "catalog/dictionaries.html");
      }
      if (indexHtmlAfter !== indexHtmlBefore) {
        console.error("差分あり: index.html が実体と同期していません。");
        showDiff(indexHtmlBefore, indexHtmlAfter, "index.html");
      }
      console.error("node skills/managing-agent-configs/scripts/manage-portal.mjs generate を実行してください。");
      process.exit(1);
    }
    console.error("差分なし: skills.html / dictionaries.html / index.html は同期済みです。");
    process.exit(0);
  }

  const changedFiles = [];
  if (skillsHtmlAfter !== skillsHtmlBefore) {
    fs.writeFileSync(SKILLS_HTML, skillsHtmlAfter);
    changedFiles.push("catalog/skills.html");
  }
  if (dictionariesHtmlAfter !== dictionariesHtmlBefore) {
    fs.writeFileSync(DICTIONARIES_HTML, dictionariesHtmlAfter);
    changedFiles.push("catalog/dictionaries.html");
  }
  if (indexHtmlAfter !== indexHtmlBefore) {
    fs.writeFileSync(INDEX_HTML, indexHtmlAfter);
    changedFiles.push("index.html");
  }

  const msg = `生成完了: skills=${counts.skills} hooks=${counts.hooks} rules=${counts.rules} subagents=${counts.subagents} routines=${counts.routines} tools=${counts.tools} dictionaries=${counts.dictionaries}`;
  console.error(msg);
  if (changedFiles.length > 0) {
    console.error(`更新ファイル: ${changedFiles.join(", ")}`);
  } else {
    console.error("変更なし（既に同期済み）");
  }
}

function showDiff(before, after, label) {
  const beforeLines = before.split("\n");
  const afterLines = after.split("\n");
  const maxLen = Math.max(beforeLines.length, afterLines.length);
  let diffCount = 0;
  for (let i = 0; i < maxLen && diffCount < 20; i++) {
    if (beforeLines[i] !== afterLines[i]) {
      console.error(`  ${label}:${i + 1}: - ${(beforeLines[i] || "").slice(0, 120)}`);
      console.error(`  ${label}:${i + 1}: + ${(afterLines[i] || "").slice(0, 120)}`);
      diffCount++;
    }
  }
  if (diffCount === 20) console.error("  ... (差分が多いため省略)");
}

// ── verify サブコマンド ──────────────────────────────────────────

// 意図的な架空例など、実在しなくても FAIL 対象外とするパス（初期値は空）
const EXAMPLE_PATH_ALLOWLIST = [];

const MANAGING_AGENT_CONFIGS_DIR = path.join(SKILLS_DIR, "managing-agent-configs");

function checkReferencePathsExist() {
  const problems = [];

  const targets = [path.join(MANAGING_AGENT_CONFIGS_DIR, "SKILL.md")];
  const refsDir = path.join(MANAGING_AGENT_CONFIGS_DIR, "references");
  targets.push(...walkFiles(refsDir, (f) => f.endsWith(".md")));

  // バッククォート内のパストークンを抽出（拡張子付きに限定して誤抽出を抑制）
  const pathPattern = /`((?:~\/|skills\/|tools\/|routines\/|ai-management-portal\/)[^\s`]+\.(?:md|sh|mjs|html|yml|json|txt))`/g;

  for (const file of targets) {
    const content = fs.readFileSync(file, "utf8");
    const lines = content.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      let m;
      pathPattern.lastIndex = 0;
      while ((m = pathPattern.exec(line)) !== null) {
        const token = m[1];

        // プレースホルダを含むパスは対象外
        if (/<[^>]+>/.test(token)) continue;
        // グロブパターン（例: skills/*/SKILL.md）は参照ではなくパターンのため対象外
        if (token.includes("*")) continue;
        // 除外リスト
        if (EXAMPLE_PATH_ALLOWLIST.includes(token)) continue;

        let resolved;
        if (token.startsWith("~/")) {
          resolved = path.join(HOME_DIR, token.slice(2));
        } else {
          resolved = path.join(REPO_ROOT, token);
        }

        if (!fs.existsSync(resolved)) {
          const rel = path.relative(REPO_ROOT, file);
          problems.push(`${rel}:${i + 1} → ${token}`);
        }
      }
    }
  }

  return {
    key: "参照-実在",
    status: problems.length > 0 ? "FAIL" : "PASS",
    problems,
  };
}

async function cmdVerify(onlyKeys) {
  const results = [];

  // カタログ-ドリフト
  if (!onlyKeys || onlyKeys.includes("catalog-ドリフト")) {
    results.push(await checkCatalogDrift());
  }

  // guide-カバレッジ
  if (!onlyKeys || onlyKeys.includes("guide-カバレッジ")) {
    results.push(checkGuideCoverage());
  }

  // 参照-実在
  if (!onlyKeys || onlyKeys.includes("参照-実在")) {
    results.push(checkReferencePathsExist());
  }

  // 数値-一致
  if (!onlyKeys || onlyKeys.includes("数値-一致")) {
    results.push(await checkCountsMatch());
  }

  // リンク-実在
  if (!onlyKeys || onlyKeys.includes("リンク-実在")) {
    results.push(checkLinksExist());
  }

  // guide-テンプレ準拠
  if (!onlyKeys || onlyKeys.includes("guide-テンプレ準拠")) {
    results.push(checkGuideTemplate());
  }

  // カテゴリ-整合
  if (!onlyKeys || onlyKeys.includes("カテゴリ-整合")) {
    results.push(await checkCategoryConsistency());
  }

  // エイリアス-解決
  if (!onlyKeys || onlyKeys.includes("エイリアス-解決")) {
    results.push(checkAliasResolution());
  }

  // 辞書-整合
  if (!onlyKeys || onlyKeys.includes("辞書-整合")) {
    results.push(await checkDictionaryConsistency());
  }

  // 出力
  let failCount = 0;
  let warnCount = 0;
  let passCount = 0;
  for (const r of results) {
    const icon = r.status === "FAIL" ? "[FAIL]" : r.status === "WARN" ? "[WARN]" : "[PASS]";
    if (r.status === "FAIL") {
      failCount++;
      console.error(`${icon} ${r.key} — ${r.problems.length} 件`);
      for (const p of r.problems) console.error(`  ${p}`);
    } else if (r.status === "WARN") {
      warnCount++;
      console.error(`${icon} ${r.key} — ${r.problems.length} 件`);
      for (const p of r.problems) console.error(`  ${p}`);
    } else {
      passCount++;
      console.error(`${icon} ${r.key}`);
    }
  }

  console.error(`\nまとめ: FAIL ${failCount} / WARN ${warnCount} / PASS ${passCount}`);
  if (failCount > 0) process.exit(1);
}

async function checkCatalogDrift() {
  // generate --check 相当を内部実行
  const skills = collectSkills();
  const skillCategoryMap = await loadSkillCategoryMap();
  const skillsHtmlBefore = fs.readFileSync(SKILLS_HTML, "utf8");
  const skillsArraySource = buildSkillsArraySource(skills, skillCategoryMap);
  const skillsHtmlAfter = replaceBetweenMarkers(
    skillsHtmlBefore,
    "// <!-- GEN:SKILLS -->",
    "// <!-- /GEN:SKILLS -->",
    skillsArraySource
  );

  const dictionaries = collectDictionaries();
  const dictionariesHtmlBefore = fs.readFileSync(DICTIONARIES_HTML, "utf8");
  const dictionariesArraySource = buildDictionariesArraySource(dictionaries);
  const dictionariesHtmlAfter = replaceBetweenMarkers(
    dictionariesHtmlBefore,
    "// <!-- GEN:DICTIONARIES -->",
    "// <!-- /GEN:DICTIONARIES -->",
    dictionariesArraySource
  );

  const counts = {
    skills: countSkills(),
    hooks: countHooks(),
    rules: countRules(),
    subagents: countSubagents(),
    routines: countRoutines(),
    tools: await countTools(),
    dictionaries: countDictionaries(),
    "public-set": countPublicSet(),
  };

  let indexHtmlAfter = fs.readFileSync(INDEX_HTML, "utf8");
  for (const [key, value] of Object.entries(counts)) {
    const startMarker = `<!-- GEN:COUNT:${key} -->`;
    const endMarker = `<!-- /GEN:COUNT:${key} -->`;
    if (indexHtmlAfter.includes(startMarker)) {
      indexHtmlAfter = replaceInlineBetweenMarkers(indexHtmlAfter, startMarker, endMarker, String(value));
    }
  }
  const today = localToday();
  indexHtmlAfter = indexHtmlAfter.replace(
    /<!-- PM:UPDATED -->.*?<!-- \/PM:UPDATED -->/,
    `<!-- PM:UPDATED -->${today}<!-- /PM:UPDATED -->`
  );

  const indexHtmlBefore = fs.readFileSync(INDEX_HTML, "utf8");
  const problems = [];
  if (skillsHtmlAfter !== skillsHtmlBefore) problems.push("catalog/skills.html がドリフトしています");
  if (dictionariesHtmlAfter !== dictionariesHtmlBefore) problems.push("catalog/dictionaries.html がドリフトしています");
  if (indexHtmlAfter !== indexHtmlBefore) problems.push("index.html がドリフトしています");

  return {
    key: "catalog-ドリフト",
    status: problems.length > 0 ? "FAIL" : "PASS",
    problems,
  };
}

function checkGuideCoverage() {
  const problems = [];
  const entries = fs
    .readdirSync(SKILLS_DIR, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => e.name)
    .sort();

  for (const dirName of entries) {
    const skillMd = path.join(SKILLS_DIR, dirName, "SKILL.md");
    if (!fs.existsSync(skillMd)) continue;
    const parsed = parseSkillMd(skillMd);
    const id = (parsed && parsed.name) || dirName;

    // id フォーマット検証
    if (!/^[a-z0-9-]+$/.test(id)) {
      problems.push(`${id}: id が ^[a-z0-9-]+$ に合致しない`);
    }

    const refsDir = path.join(SKILLS_DIR, dirName, "references");
    const guideFile = path.join(refsDir, `${id}-guide.html`);
    if (!fs.existsSync(guideFile)) {
      problems.push(`${id}: references/${id}-guide.html が存在しない`);
    }

    // 孤児検出: references/ 内の *-guide.html でファイル名 ≠ <親dir>-guide.html
    if (fs.existsSync(refsDir)) {
      const refFiles = fs.readdirSync(refsDir).filter((f) => f.endsWith("-guide.html"));
      for (const rf of refFiles) {
        if (rf !== `${id}-guide.html`) {
          problems.push(`${dirName}/references/${rf}: 孤児ガイド（期待ファイル名: ${id}-guide.html）`);
        }
      }
    }
  }

  return {
    key: "guide-カバレッジ",
    status: problems.length > 0 ? "FAIL" : "PASS",
    problems,
  };
}

async function checkCountsMatch() {
  const problems = [];

  // skills 3点一致
  const skillsActual = countSkills();

  // GEN:SKILLS ブロック内エントリ数
  const skillsHtml = fs.readFileSync(SKILLS_HTML, "utf8");
  const genStart = skillsHtml.indexOf("// <!-- GEN:SKILLS -->");
  const genEnd = skillsHtml.indexOf("// <!-- /GEN:SKILLS -->");
  const genBlock = genStart !== -1 && genEnd !== -1 ? skillsHtml.slice(genStart, genEnd) : "";
  const genEntries = (genBlock.match(/\{ id:/g) || []).length;

  if (skillsActual !== genEntries) {
    problems.push(`skills 実体数(${skillsActual}) ≠ GEN:SKILLS ブロック内エントリ数(${genEntries})`);
  }

  // GEN:COUNT は index.html から取得
  const indexHtml = fs.readFileSync(INDEX_HTML, "utf8");
  const skillsCountMatch = indexHtml.match(/<!-- GEN:COUNT:skills -->(.*?)<!-- \/GEN:COUNT:skills -->/);
  const indexGenCount = skillsCountMatch ? parseInt(skillsCountMatch[1], 10) : NaN;
  if (skillsActual !== indexGenCount) {
    problems.push(`skills 実体数(${skillsActual}) ≠ index.html GEN:COUNT:skills(${indexGenCount})`);
  }

  // routines カウント
  const routinesActual = countRoutines();
  const routinesMatch = indexHtml.match(/<!-- GEN:COUNT:routines -->(.*?)<!-- \/GEN:COUNT:routines -->/);
  if (routinesMatch) {
    const routinesGen = parseInt(routinesMatch[1], 10);
    if (routinesActual !== routinesGen) {
      problems.push(`routines 実体数(${routinesActual}) ≠ GEN:COUNT:routines(${routinesGen})`);
    }
  }

  // hooks カウント
  const hooksActual = countHooks();
  const hooksMatch = indexHtml.match(/<!-- GEN:COUNT:hooks -->(.*?)<!-- \/GEN:COUNT:hooks -->/);
  if (hooksMatch) {
    const hooksGen = parseInt(hooksMatch[1], 10);
    if (hooksActual !== hooksGen) {
      problems.push(`hooks 実体数(${hooksActual}) ≠ GEN:COUNT:hooks(${hooksGen})`);
    }
  }

  // rules カウント
  const rulesActual = countRules();
  const rulesMatch = indexHtml.match(/<!-- GEN:COUNT:rules -->(.*?)<!-- \/GEN:COUNT:rules -->/);
  if (rulesMatch) {
    const rulesGen = parseInt(rulesMatch[1], 10);
    if (rulesActual !== rulesGen) {
      problems.push(`rules 実体数(${rulesActual}) ≠ GEN:COUNT:rules(${rulesGen})`);
    }
  }

  // tools カウント
  const toolsActual = await countTools();
  const toolsMatch = indexHtml.match(/<!-- GEN:COUNT:tools -->(.*?)<!-- \/GEN:COUNT:tools -->/);
  if (toolsMatch) {
    const toolsGen = parseInt(toolsMatch[1], 10);
    if (toolsActual !== toolsGen) {
      problems.push(`tools 実体数(${toolsActual}) ≠ GEN:COUNT:tools(${toolsGen})`);
    }
  }

  // dictionaries カウント
  const dictionariesActual = countDictionaries();
  const dictionariesMatch = indexHtml.match(/<!-- GEN:COUNT:dictionaries -->(.*?)<!-- \/GEN:COUNT:dictionaries -->/);
  if (dictionariesMatch) {
    const dictionariesGen = parseInt(dictionariesMatch[1], 10);
    if (dictionariesActual !== dictionariesGen) {
      problems.push(`dictionaries 実体数(${dictionariesActual}) ≠ GEN:COUNT:dictionaries(${dictionariesGen})`);
    }
  }

  // public-set カウント
  const publicSetActual = countPublicSet();
  const publicSetMatch = indexHtml.match(/<!-- GEN:COUNT:public-set -->(.*?)<!-- \/GEN:COUNT:public-set -->/);
  if (publicSetMatch) {
    const publicSetGen = parseInt(publicSetMatch[1], 10);
    if (publicSetActual !== publicSetGen) {
      problems.push(`public-set 実体数(${publicSetActual}) ≠ GEN:COUNT:public-set(${publicSetGen})`);
    }
  }

  return {
    key: "数値-一致",
    status: problems.length > 0 ? "FAIL" : "PASS",
    problems,
  };
}

function checkLinksExist() {
  const problems = [];

  // PORTAL 配下 *.html（templates/ 除外）+ REPO_ROOT/routines/index.html
  const htmlFiles = walkFiles(PORTAL, (f) => f.endsWith(".html") && !f.includes("/templates/"));
  const routinesIndex = path.join(REPO_ROOT, "routines", "index.html");
  if (fs.existsSync(routinesIndex)) htmlFiles.push(routinesIndex);

  const skipPrefixes = ["#", "http:", "https:", "mailto:", "data:", "javascript:"];

  for (const htmlFile of htmlFiles) {
    const rawContent = fs.readFileSync(htmlFile, "utf8");
    const dir = path.dirname(htmlFile);

    // <script> ブロック内は JS 文字列が混在するため除去してから走査する
    const content = rawContent.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "");

    // href と src を抽出
    const attrs = [...content.matchAll(/(?:href|src)="([^"]+)"/g)].map((m) => m[1]);
    for (let attr of attrs) {
      // スキップ対象
      if (skipPrefixes.some((p) => attr.startsWith(p))) continue;
      // query/fragment 除去
      attr = attr.split("?")[0].split("#")[0];
      if (!attr) continue;

      const resolved = path.resolve(dir, attr);
      let exists = false;
      if (attr.endsWith("/")) {
        exists = fs.existsSync(resolved) && fs.statSync(resolved).isDirectory();
      } else {
        exists = fs.existsSync(resolved);
      }
      if (!exists) {
        const rel = path.relative(REPO_ROOT, htmlFile);
        problems.push(`${rel}: リンク切れ → ${attr}`);
      }
    }
  }

  return {
    key: "リンク-実在",
    status: problems.length > 0 ? "FAIL" : "PASS",
    problems,
  };
}

function normalizeStyle(s) {
  return s
    .split("\n")
    .map((l) => l.trimEnd())
    .join("\n")
    .replace(/^\n+|\n+$/g, "");
}

function extractStyle(html) {
  // HTML コメントを除去してから <style> タグを抽出する（コメント内の <style> テキストを誤検知しない）
  const stripped = html.replace(/<!--[\s\S]*?-->/g, "");
  const m = stripped.match(/<style\b[^>]*>([\s\S]*?)<\/style>/);
  return m ? normalizeStyle(m[1]) : null;
}

// 出力セクション標準化の対象外（既に §4 で「出力フォーマット」を保持しており
// 位置変更・改稿を行わない過渡的な例外。conventions.md §6 参照）
const OUTPUT_SECTION_EXEMPT = new Set([]);

function checkGuideTemplate() {
  const FAILS = [];
  const WARNS = [];

  const templateFile = path.join(SKILLS_DIR, "managing-agent-configs", "references", "skills", "template-guide.html");
  const templateExists = fs.existsSync(templateFile);
  let templateStyle = null;
  if (templateExists) {
    const tmplContent = fs.readFileSync(templateFile, "utf8");
    templateStyle = extractStyle(tmplContent);
  }

  const entries = fs
    .readdirSync(SKILLS_DIR, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => e.name)
    .sort();

  for (const dirName of entries) {
    const skillMd = path.join(SKILLS_DIR, dirName, "SKILL.md");
    if (!fs.existsSync(skillMd)) continue;
    const parsed = parseSkillMd(skillMd);
    const id = (parsed && parsed.name) || dirName;
    const guideFile = path.join(SKILLS_DIR, dirName, "references", `${id}-guide.html`);
    if (!fs.existsSync(guideFile)) continue;

    const content = fs.readFileSync(guideFile, "utf8");

    // FAIL 条件チェック
    // 1. <title>
    if (!content.includes(`<title>${id} スキルガイド</title>`)) {
      FAILS.push(`${id}: <title> が "${id} スキルガイド" でない`);
    }

    // 2. .skill-name の中身
    const skillNameMatch = content.match(/class="skill-name"[^>]*>([\s\S]*?)<\//);
    if (skillNameMatch && skillNameMatch[1].trim() !== id) {
      FAILS.push(`${id}: .skill-name の中身(${skillNameMatch[1].trim()}) が id と不一致`);
    }

    // 3. nav class="toc" 不在
    if (!content.includes('class="toc"') && !content.includes("class='toc'")) {
      FAILS.push(`${id}: nav class="toc" が不在`);
    }

    // 4. <section id="sN"> の連番チェック
    const sectionIds = [...content.matchAll(/<section\s+id="(s\d+)"/g)].map((m) => m[1]);
    const isOutputExempt = OUTPUT_SECTION_EXEMPT.has(id);
    const expectedSectionCount = isOutputExempt ? 9 : 10;
    // TOC li 数は <nav class="toc"> 〜 </nav> 内の href="#sN" アンカー数で数える
    const tocNavMatch = content.match(/<nav\s[^>]*class="toc"[^>]*>([\s\S]*?)<\/nav>/);
    const tocAnchors = tocNavMatch
      ? [...tocNavMatch[1].matchAll(/href="#s\d+"/g)].length
      : 0;
    if (sectionIds.length > 0) {
      for (let i = 0; i < sectionIds.length; i++) {
        if (sectionIds[i] !== `s${i + 1}`) {
          FAILS.push(`${id}: section id が s${i + 1} でなく ${sectionIds[i]}`);
        }
      }
      // section id 列と TOC アンカー列の不一致は FAIL
      if (tocAnchors > 0 && sectionIds.length !== tocAnchors) {
        FAILS.push(`${id}: section 数(${sectionIds.length}) と TOC アンカー数(${tocAnchors}) が不一致`);
      }
    }

    // 5. .def に「こんな人向け」「こんな場面で使う」欠落
    const defMatch = content.match(/class="def"[\s\S]*?<\/[^>]+>/);
    if (defMatch) {
      if (!content.includes("こんな人向け") && !content.includes("人向け")) {
        FAILS.push(`${id}: .def に「こんな人向け」が欠落`);
      }
      if (!content.includes("こんな場面で使う") && !content.includes("場面で使う")) {
        FAILS.push(`${id}: .def に「こんな場面で使う」が欠落`);
      }
    }

    // 6. meta-table に 4 行の必須項目
    const metaRequired = ["対応 OS", "検証状況", "依存", "関連資料"];
    for (const req of metaRequired) {
      if (!content.includes(req)) {
        FAILS.push(`${id}: meta-table に「${req}」が欠落`);
      }
    }

    // 7. 外部リソース参照（SVG の xmlns= は除外）
    const externalPatterns = [/<link /, /<img /, /<script src=/, /url\(http/];
    for (const pat of externalPatterns) {
      if (pat.test(content)) {
        // <link rel= の中で xmlns= は除外
        if (pat === /<link / && !/<link\s[^>]*href=/.test(content)) continue;
        FAILS.push(`${id}: 外部リソース参照あり（${pat}）`);
      }
    }

    // WARN 条件
    // セクション数 ≠ 期待値（§2出力を持たない対象外スキルのみ 9、それ以外は 10）
    if (sectionIds.length !== expectedSectionCount && sectionIds.length > 0) {
      WARNS.push(`${id}: セクション数(${sectionIds.length}) ≠ ${expectedSectionCount}`);
    }

    // §2 が「出力」であるかの機械検査（対象外リストは除外）
    if (!isOutputExempt && sectionIds.length > 0) {
      const s2Match = content.match(/<section id="s2">\s*<h2><span class="sec-num">§2<\/span>([^<]*)<\/h2>/);
      if (!s2Match || !s2Match[1].includes("出力")) {
        WARNS.push(`${id}: §2 が「出力」でない（${s2Match ? s2Match[1] : "s2 セクション不在"}）`);
      }
    }

    // <a href="http
    if (/<a\s[^>]*href="http/.test(content)) {
      WARNS.push(`${id}: 外部リンク（<a href="http）あり`);
    }

    // style ブロックのテンプレ比較（テンプレ未配置の間はスキップ）
    if (templateStyle) {
      const guideStyle = extractStyle(content);
      if (guideStyle && guideStyle !== templateStyle) {
        // 最初に食い違う行を特定してデバッグ可能にする
        const tLines = templateStyle.split("\n");
        const gLines = guideStyle.split("\n");
        let diffLine = -1;
        for (let i = 0; i < Math.max(tLines.length, gLines.length); i++) {
          if (tLines[i] !== gLines[i]) { diffLine = i + 1; break; }
        }
        const detail = diffLine !== -1
          ? ` (最初の差異: 行${diffLine} テンプレ=${JSON.stringify(tLines[diffLine - 1])} ガイド=${JSON.stringify(gLines[diffLine - 1])})`
          : "";
        WARNS.push(`${id}: style ブロックがテンプレと不一致${detail}`);
      }
    }
  }

  const allProblems = FAILS.map((f) => `[FAIL] ${f}`).concat(WARNS.map((w) => `[WARN] ${w}`));
  const status = FAILS.length > 0 ? "FAIL" : WARNS.length > 0 ? "WARN" : "PASS";

  return {
    key: "guide-テンプレ準拠",
    status,
    problems: allProblems,
  };
}

async function checkCategoryConsistency() {
  const problems = [];
  const skillCategoryMap = await loadSkillCategoryMap();

  const entries = fs
    .readdirSync(SKILLS_DIR, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => e.name)
    .sort();

  const actualIds = new Set();
  for (const dirName of entries) {
    const skillMd = path.join(SKILLS_DIR, dirName, "SKILL.md");
    if (!fs.existsSync(skillMd)) continue;
    const parsed = parseSkillMd(skillMd);
    const id = (parsed && parsed.name) || dirName;
    actualIds.add(id);
  }

  for (const id of actualIds) {
    if (skillCategoryMap[id] === undefined) {
      problems.push(`未登録スキル: "${id}" が SKILL_CATEGORY に無い`);
    }
  }
  for (const key of Object.keys(skillCategoryMap)) {
    if (!actualIds.has(key)) {
      problems.push(`残骸キー: "${key}" が SKILL_CATEGORY に残っているが skills/${key}/SKILL.md が存在しない`);
    }
  }

  return {
    key: "カテゴリ-整合",
    status: problems.length > 0 ? "FAIL" : "PASS",
    problems,
  };
}

function checkAliasResolution() {
  const problems = [];
  const aliasFile = path.join(REPO_ROOT, "sessions", ".skill-log", "skill-aliases.yml");

  if (!fs.existsSync(aliasFile)) {
    return { key: "エイリアス-解決", status: "WARN", problems: ["skill-aliases.yml が見つかりません"] };
  }

  const content = fs.readFileSync(aliasFile, "utf8");
  const lines = content.split("\n");

  // aliases: ブロックを抽出（^  <key>: <value> 行）
  let inAliases = false;
  const aliases = {};
  for (const line of lines) {
    if (line.trim() === "aliases:") { inAliases = true; continue; }
    if (inAliases) {
      // ブロック終端（unresolved: 等のトップレベルキー）
      if (/^[a-z]/.test(line) && line.includes(":")) { inAliases = false; continue; }
      // ^  <key>: <value> 形式
      const m = line.match(/^  ([^:#\s][^:]*?):\s+([^#\s]+)/);
      if (m) {
        const key = m[1].trim();
        const val = m[2].replace(/#.*$/, "").trim();
        if (key && val) aliases[key] = val;
      }
    }
  }

  // 右辺が skills/<right>/SKILL.md へ解決できるか（他エイリアス経由の遷移も含む）
  function resolve(val, visited = new Set()) {
    if (visited.has(val)) return null; // 循環
    visited.add(val);
    const skillMd = path.join(SKILLS_DIR, val, "SKILL.md");
    if (fs.existsSync(skillMd)) return val;
    // 他エイリアス経由
    if (aliases[val]) return resolve(aliases[val], visited);
    return null;
  }

  for (const [key, val] of Object.entries(aliases)) {
    // 循環チェック
    const visited = new Set([key]);
    function resolveWithCycleCheck(v, vis) {
      if (vis.has(v)) return "CYCLE";
      vis.add(v);
      const skillMd = path.join(SKILLS_DIR, v, "SKILL.md");
      if (fs.existsSync(skillMd)) return v;
      if (aliases[v]) return resolveWithCycleCheck(aliases[v], vis);
      return null;
    }
    const result = resolveWithCycleCheck(val, visited);
    if (result === "CYCLE") {
      problems.push(`${key}: エイリアス循環を検出`);
    } else if (result === null) {
      problems.push(`${key} → ${val}: skills/${val}/SKILL.md が解決できない`);
    }
  }

  return {
    key: "エイリアス-解決",
    status: problems.length > 0 ? "FAIL" : "PASS",
    problems,
  };
}

async function checkDictionaryConsistency() {
  const problems = [];
  const warnings = [];

  const mod = await import(pathToFileURL(DICTIONARY_CATEGORIES_FILE).href + "?t=" + Date.now());
  const categoryIds = new Set(mod.CATEGORIES.map((c) => c.id));

  const entries = collectDictionaries();
  const usedCategoryIds = new Set();
  let otherCount = 0;

  for (const e of entries) {
    if (e.category === "other") {
      otherCount++;
      continue;
    }
    usedCategoryIds.add(e.category);
    if (!categoryIds.has(e.category)) {
      problems.push(`未登録カテゴリ: "${e.category}"（expected: "${e.expected}"）が data/dictionary-categories.js の CATEGORIES に無い`);
    }
  }

  for (const id of categoryIds) {
    if (!usedCategoryIds.has(id)) {
      warnings.push(`未使用カテゴリ: "${id}" を参照する辞書エントリが prh.yml に無い`);
    }
  }

  if (otherCount > 0) {
    problems.push(`category が "other"（カテゴリヘッダ未検出）のエントリが ${otherCount} 件ある`);
  }

  const allProblems = problems.map((p) => `[FAIL] ${p}`).concat(warnings.map((w) => `[WARN] ${w}`));
  const status = problems.length > 0 ? "FAIL" : warnings.length > 0 ? "WARN" : "PASS";

  return {
    key: "辞書-整合",
    status,
    problems: allProblems,
  };
}

// ── serve サブコマンド ───────────────────────────────────────────

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".ico": "image/x-icon",
  ".yml": "text/yaml; charset=utf-8",
  ".md": "text/markdown; charset=utf-8",
};

function cmdServe() {
  const PORT = parseInt(process.env.PORT || "9000", 10);
  const DOCROOT = REPO_ROOT;

  const server = http.createServer((req, res) => {
    let urlPath = req.url.split("?")[0].split("#")[0];
    // パストラバーサル防止
    const safePath = path.normalize(urlPath).replace(/^(\.\.[/\\])+/, "");
    const filePath = path.join(DOCROOT, safePath);
    const realFilePath = path.resolve(filePath);
    if (!realFilePath.startsWith(DOCROOT + path.sep) && realFilePath !== DOCROOT) {
      res.writeHead(403, { "Content-Type": "text/plain" });
      res.end("403 Forbidden");
      return;
    }

    let targetPath = realFilePath;
    // ディレクトリの場合は index.html を試みる
    if (fs.existsSync(targetPath) && fs.statSync(targetPath).isDirectory()) {
      targetPath = path.join(targetPath, "index.html");
    }

    if (!fs.existsSync(targetPath)) {
      res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("404 Not Found");
      return;
    }

    const ext = path.extname(targetPath).toLowerCase();
    const mime = MIME_TYPES[ext] || "application/octet-stream";
    const content = fs.readFileSync(targetPath);
    res.writeHead(200, { "Content-Type": mime });
    res.end(content);
  });

  server.listen(PORT, () => {
    console.error(`ポータル配信中: http://localhost:${PORT}/ai-management-portal/`);
    console.error(`docroot: ${DOCROOT}`);
    console.error("停止: Ctrl+C");
  });
}

// ── エントリポイント ────────────────────────────────────────────

const subcommand = process.argv[2];

switch (subcommand) {
  case "generate":
    await cmdGenerate(false);
    break;
  case "check":
    await cmdGenerate(true);
    break;
  case "verify": {
    const onlyIdx = process.argv.indexOf("--only");
    const onlyKeys = onlyIdx !== -1 ? process.argv[onlyIdx + 1].split(",") : null;
    await cmdVerify(onlyKeys);
    break;
  }
  case "serve":
    cmdServe();
    break;
  default:
    console.error("使い方: manage-portal.mjs <generate|check|verify|serve> [--only <key>,<key>]");
    process.exit(1);
}
