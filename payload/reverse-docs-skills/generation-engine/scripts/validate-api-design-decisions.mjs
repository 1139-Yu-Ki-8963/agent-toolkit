#!/usr/bin/env node

import fs from "node:fs";

const targets = process.argv.slice(2);
if (targets.length === 0) {
  console.error("usage: validate-api-design-decisions.mjs <API実装記録.md...>");
  process.exit(2);
}

let failures = 0;
const fail = (file, message) => {
  failures += 1;
  console.error(`FAIL: ${file}: ${message}`);
};

const stripFrontmatterAndComments = (text) =>
  text
    .replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, "")
    .replace(/<!--[\s\S]*?-->/g, "");

const stripObservationSourceSection = (text) =>
  text.replace(/\n### 9\.1 観測の出どころ\n[\s\S]*?(?=\n### |\n## |$)/, "");

const normalizeDigits = (text) =>
  text.replace(/[０-９]/g, (digit) => String(digit.charCodeAt(0) - "０".charCodeAt(0)));

const protectNetworkAuthorities = (text) =>
  text
    .replace(/\b(https?:\/\/)(?:\[[^\]]+\]|[^/\s|`]+)/gu, "$1<AUTHORITY>")
    .replace(/(?:\[[0-9a-f:]+\]|\blocalhost|\b(?:[a-z0-9-]+\.){2,}[a-z]{2,}|\b[a-z0-9-]+\.(?:com|org|net|edu|gov|mil|int|io|dev|app|cloud|local)|\b(?:\d{1,3}\.){3}\d{1,3}):\d{1,5}\b/giu, "<AUTHORITY>");

const sourceFile = String.raw`(?:[\p{L}\p{N}_.-]+[\\/])*[\p{L}\p{N}_.-]+\.(?:py|pl|pm|cgi|ts|tsx|js|jsx|mjs|cjs|vue|svelte|java|kt|kts|cs|go|rs|rb|php|swift|scala|sql|sh|bash|zsh|fish|ps1|c|cc|cpp|h|hpp|html|css|scss|sass|less|xml|yaml|yml|json|toml|ini|conf|properties|gradle|groovy|ex|exs|erl|hrl|lua|r|fs|fsx|vb|sol|dart|proto|graphql|gql|tf|hcl|bicep|asm)(?![\p{L}\p{N}_])`;
const fileLine = String.raw`(?:[\p{L}\p{N}_.-]+[\\/])+[\p{L}\p{N}_.-]+[：:]\d+`;
const bodyCodePositionPatterns = [
  new RegExp(sourceFile, "u"),
  new RegExp(fileLine, "u"),
  /[（(]\s*(?:L\s*)?\d+\s*行目?\s*[）)]/u,
  /(?:^|[^\d:])\d+\s*行目/u,
  /(?:^|[^\p{L}\p{N}_])L\d+(?=$|[^\p{L}\p{N}_])/mu,
  /(?:ファイル名?|対象ファイル)[^\n]{0,20}(?:行番号|\d+行目)/u,
];

for (const file of targets) {
  const failuresBeforeFile = failures;
  let text;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch (error) {
    fail(file, `読み取れない: ${error.message}`);
    continue;
  }
  const body = protectNetworkAuthorities(
    normalizeDigits(stripObservationSourceSection(stripFrontmatterAndComments(text))),
  );
  if (bodyCodePositionPatterns.some((pattern) => pattern.test(body))) {
    fail(file, "本文に対象コードのファイル名または行番号が混入している");
  }
  const decisionMatch = text.match(
    /### 4\.5 設計判断とその理由\n([\s\S]*?)(?=\n## §|\s*$)/,
  );
  if (!decisionMatch) {
    fail(file, "4.5 設計判断とその理由が存在しない（API実装記録）");
    continue;
  }

  const decisionSection = decisionMatch[1];
  const rows = decisionSection
    .split("\n")
    .filter((line) => /^\| .+ \|$/.test(line))
    .filter((line) => !line.startsWith("| 判断キー |"))
    .filter((line) => !/^\|[-|]+\|$/.test(line.replaceAll(" ", "")))
    .map((line) => line.slice(2, -2).split(" | "));

  for (const row of rows) {
    if (row.length !== 8) {
      fail(file, `4.5 の列数が8ではない: ${row.length}`);
      continue;
    }
    const [key, decision, reason, kind, material, alternative, rejection, confidence] = row;
    if ([key, decision, reason, material, alternative, rejection, confidence].some((value) => !value)) {
      fail(file, `4.5 に空欄がある: ${key || "判断キー不明"}`);
    }
    if (!new Set(["観測（コードコメント）", "推定（実装構造）"]).has(kind)) {
      fail(file, `記述区分が不正: ${kind}`);
    }
    if (kind === "推定（実装構造）" && !new Set(["medium", "low"]).has(confidence)) {
      fail(file, `推定の確からしさが不正: ${confidence}`);
    }
    const unknownAlternative = alternative === "不明（実装に記述なし）";
    const unknownRejection = rejection === "不明（実装に記述なし）";
    if (unknownAlternative !== unknownRejection) {
      fail(file, `選択肢と不採用理由の不明表記が片方だけ: ${key}`);
    }
  }

  if (failures === failuresBeforeFile) console.log(`PASS: ${file}`);
}

process.exit(failures === 0 ? 0 : 1);
