#!/usr/bin/env node
// ai-management-portal のページファミリー・並び順規約チェッカー。
// 正本: ./rule.md
//
// 機械チェックする範囲（構造的に判定しやすいもの）:
//   1. claude/tooling.html 早見表: 7 行の並び順が正本順序と一致するか + 表記が正本文字列と完全一致するか
//   2. claude/tooling.html 早見表: 全リンクが同一ディレクトリ系統（design/ か catalog/ のどちらか一方）を指しているか
//   3. data/manifest.js design カテゴリ: config 層エントリの並び順が正本順序のサブシーケンスとして成立するか
//   4. data/manifest.js registry カテゴリ: catalog 付き5項目の並び順が正本順序のサブシーケンスとして成立するか
//   5. index.html 規模サマリカード: catalog 付き5項目の並び順が正本順序のサブシーケンスとして成立するか
//   6. 全 HTML の #/category/<id> リンクが data/manifest.js のカテゴリ id として実在するか（リンク切れ検知）
//
// 機械チェックしない範囲（文脈依存で誤検知しやすいため rule.md のチェックリストで人間/Claudeが判断する）:
//   - manifest.js の title / description 内の日本語表記ゆれ（例: "Skill 設計ガイド" の単数/複数）
//   - index.html の metric-label の厳密表記一致（"hook" のような短縮ラベルは文脈依存）

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORTAL_ROOT = path.resolve(__dirname, "..", "..", "..", "ai-management-portal");

const CANON_ORDER = ["CLAUDE.md", "Rules", "Skills", "Subagents", "Hooks", "Output styles", "Statusline"];

const DESIGN_ID_MAP = {
  "claude-md-design": "CLAUDE.md",
  "rules-design": "Rules",
  "skill-design": "Skills",
  "subagent-design": "Subagents",
  "hooks-design": "Hooks",
  "output-style-design": "Output styles",
  "statusline-design": "Statusline",
};

const REGISTRY_ID_MAP = {
  "rules-catalog": "Rules",
  "skills-catalog": "Skills",
  "subagents-catalog": "Subagents",
  "hooks-catalog": "Hooks",
  "output-styles-catalog": "Output styles",
};

const violations = [];

function readIfExists(p) {
  return fs.existsSync(p) ? fs.readFileSync(p, "utf8") : null;
}

// actualNames（正本順序に属するものだけを抽出済みの配列）が CANON_ORDER の部分列として
// 成立しているか（＝相対順序が保たれているか）を検証する。
function checkSubsequenceOrder(label, actualNames) {
  const positions = actualNames.map((n) => CANON_ORDER.indexOf(n));
  for (let i = 1; i < positions.length; i++) {
    if (positions[i] <= positions[i - 1]) {
      violations.push(
        `[${label}] 並び順が正本順序（${CANON_ORDER.join(" → ")}）に違反: 実際の並び = ${actualNames.join(" → ")}`
      );
      return;
    }
  }
}

// --- 1 & 2: claude/tooling.html ---
function checkToolingHtml() {
  const file = path.join(PORTAL_ROOT, "claude", "tooling.html");
  const text = readIfExists(file);
  if (text === null) return;

  const tableMatch = text.match(/<table class="design-table">[\s\S]*?<\/table>/);
  if (!tableMatch) {
    violations.push(`[claude/tooling.html] 早見表（table.design-table）が見つからない`);
    return;
  }
  const tableHtml = tableMatch[0];
  const rowMatches = [...tableHtml.matchAll(/<tr>([\s\S]*?)<\/tr>/g)].slice(1); // 先頭は thead

  const names = [];
  const hrefPrefixes = new Set();

  for (const [, rowHtml] of rowMatches) {
    const tds = [...rowHtml.matchAll(/<td>([\s\S]*?)<\/td>/g)];
    if (tds.length === 0) continue;
    const nameCell = tds[0][1].replace(/<[^>]+>/g, "").trim();
    names.push(nameCell);

    const hrefMatch = rowHtml.match(/href="([^"]+)"/);
    if (hrefMatch) {
      const href = hrefMatch[1];
      const dir = href.split("/")[1] ?? href; // "../design/xxx.html" -> "design"
      hrefPrefixes.add(dir);
    }
  }

  if (names.length !== CANON_ORDER.length || names.some((n, i) => n !== CANON_ORDER[i])) {
    violations.push(
      `[claude/tooling.html] 早見表の並び順・表記が正本と不一致: 期待 = ${CANON_ORDER.join(" → ")} / 実際 = ${names.join(" → ")}`
    );
  }

  if (hrefPrefixes.size > 1) {
    violations.push(
      `[claude/tooling.html] 早見表のリンク先ディレクトリが混在: ${[...hrefPrefixes].join(", ")}（design/ か catalog/ のどちらかに統一する）`
    );
  }
}

// --- 3 & 4: data/manifest.js ---
function checkManifestJs() {
  const file = path.join(PORTAL_ROOT, "data", "manifest.js");
  const text = readIfExists(file);
  if (text === null) return;

  const designBlockMatch = text.match(/id:\s*"design"[\s\S]*?id:\s*"registry"/);
  const registryBlockMatch = text.match(/id:\s*"registry"[\s\S]*?id:\s*"pc-config"/);

  if (designBlockMatch) {
    const ids = [...designBlockMatch[0].matchAll(/\{\s*id:\s*"([\w-]+)"/g)].map((m) => m[1]);
    const names = ids.filter((id) => id in DESIGN_ID_MAP).map((id) => DESIGN_ID_MAP[id]);
    checkSubsequenceOrder("data/manifest.js design カテゴリ", names);
  } else {
    violations.push(`[data/manifest.js] design カテゴリブロックが見つからない`);
  }

  if (registryBlockMatch) {
    const ids = [...registryBlockMatch[0].matchAll(/\{\s*id:\s*"([\w-]+)"/g)].map((m) => m[1]);
    const names = ids.filter((id) => id in REGISTRY_ID_MAP).map((id) => REGISTRY_ID_MAP[id]);
    checkSubsequenceOrder("data/manifest.js registry カテゴリ", names);
  } else {
    violations.push(`[data/manifest.js] registry カテゴリブロックが見つからない`);
  }
}

// --- 5: index.html ---
function checkIndexHtml() {
  const file = path.join(PORTAL_ROOT, "index.html");
  const text = readIfExists(file);
  if (text === null) return;

  const gridMatch = text.match(/<div class="metric-grid">[\s\S]*?<\/div>\s*<\/div>\s*<!--/) ||
    text.match(/<div class="metric-grid">[\s\S]*?(?=<div class="sec-label">ドキュメント入口)/);
  if (!gridMatch) {
    violations.push(`[index.html] 規模サマリカード（metric-grid）が見つからない`);
    return;
  }
  const gridHtml = gridMatch[0];
  const cardMatches = [...gridHtml.matchAll(/<a class="metric-card[^"]*" href="([^"]+)">([\s\S]*?)<\/a>/g)];

  // catalog を持つ 5 項目のみ対象（href が catalog/ を指すカード）
  const REGISTRY_HREF_TO_NAME = {
    "catalog/rules.html": "Rules",
    "catalog/skills.html": "Skills",
    "catalog/subagents.html": "Subagents",
    "catalog/hooks.html": "Hooks",
    "catalog/output-styles.html": "Output styles",
  };

  const names = [];
  for (const [, href] of cardMatches) {
    if (href in REGISTRY_HREF_TO_NAME) {
      names.push(REGISTRY_HREF_TO_NAME[href]);
    }
  }
  checkSubsequenceOrder("index.html 規模サマリカード", names);
}

// --- 6: #/category/<id> リンク切れ検知 ---

// data/manifest.js のトップレベルカテゴリ id 一覧を取得する。
// VISUAL_TOOL_GROUPS 配列直下の要素（インデント2スペースの "  {"）の直後に現れる
// インデント4スペースの `    id: "..."` のみを拾うことで、sections/tools 配列内の
// id（インデント6スペース以上）と区別する。
function getManifestCategoryIds() {
  const file = path.join(PORTAL_ROOT, "data", "manifest.js");
  const text = readIfExists(file);
  if (text === null) return null;

  const ids = [];
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    if (/^ {2}\{$/.test(lines[i])) {
      for (let j = i + 1; j < lines.length; j++) {
        const m = lines[j].match(/^ {4}id:\s*"([\w-]+)"/);
        if (m) {
          ids.push(m[1]);
          break;
        }
        if (/^ {2}\},?$/.test(lines[j])) break;
      }
    }
  }
  return ids;
}

// ポータル配下の全 HTML（index.html, catalog/*.html, claude/*.html, design/*.html, architecture/*.html）を走査し、
// href="...#/category/<id>" 形式のリンクが manifest.js のカテゴリ id として実在するか検証する。
function checkCategoryLinks() {
  const categoryIds = getManifestCategoryIds();
  if (categoryIds === null) return;
  const categoryIdSet = new Set(categoryIds);

  const targetFiles = [path.join(PORTAL_ROOT, "index.html")];
  for (const dir of ["catalog", "claude", "design", "architecture"]) {
    const dirPath = path.join(PORTAL_ROOT, dir);
    if (!fs.existsSync(dirPath)) continue;
    for (const name of fs.readdirSync(dirPath)) {
      if (name.endsWith(".html")) targetFiles.push(path.join(dirPath, name));
    }
  }

  for (const file of targetFiles) {
    const text = readIfExists(file);
    if (text === null) continue;
    const relFile = path.relative(PORTAL_ROOT, file);

    const hrefMatches = text.matchAll(/href="[^"]*#\/category\/([\w-]+)"/g);
    for (const m of hrefMatches) {
      const refId = m[1];
      if (!categoryIdSet.has(refId)) {
        violations.push(`[${relFile}] #/category/${refId} は data/manifest.js に存在しないカテゴリ id を参照している（リンク切れ）`);
      }
    }
  }
}

checkToolingHtml();
checkManifestJs();
checkIndexHtml();
checkCategoryLinks();

if (violations.length > 0) {
  for (const v of violations) {
    console.log(v);
  }
  process.exit(1);
}
process.exit(0);
