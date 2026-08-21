#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "../../..");
const conventionsPath = path.join(repoRoot, "delivery-payload/templates/リバース検証/プロジェクト共通/詳細設計記述規約.md");
const apiTemplatePath = path.join(repoRoot, "delivery-payload/templates/リバース検証/API/API詳細設計書.md");

// 1-246: 旧CLIの根拠台帳・行範囲検査は互換目的でも残さない。
// 残すと対象コード位置を納品物へ書く経路が再利用されるため、正本テンプレートへの
// 位置情報再混入を拒否する自己テストだけに責務を限定する。設計判断の正本は
// docs/design/generation-engine/verification/詳細設計書.md に記録する。

function section(document, heading, nextHeading) {
  const start = document.indexOf(heading);
  if (start < 0) throw new Error(heading + " がありません");
  const end = nextHeading ? document.indexOf(nextHeading, start + heading.length) : -1;
  return document.slice(start, end < 0 ? undefined : end);
}

function withoutHtmlComments(document) {
  return document.replace(/<!--[\s\S]*?-->/g, "");
}

function normalizeDigits(document) {
  return document.replace(/[０-９]/g, (digit) =>
    String(digit.charCodeAt(0) - "０".charCodeAt(0)),
  );
}

function protectNetworkAuthorities(document) {
  return document
    .replace(/\b(https?:\/\/)(?:\[[^\]]+\]|[^/\s|`]+)/gu, "$1<AUTHORITY>")
    .replace(
      /(?:\[[0-9a-f:]+\]|\blocalhost|\b(?:[a-z0-9-]+\.){2,}[a-z]{2,}|\b[a-z0-9-]+\.(?:com|org|net|io|dev|app|cloud|local)|\b(?:\d{1,3}\.){3}\d{1,3}):\d{1,5}\b/giu,
      "<AUTHORITY>",
    );
}

function visibleMarkdownLines(document) {
  let fence = null;
  return document.split(/\r?\n/).map((line) => {
    if (fence !== null) {
      const closing = new RegExp("^ {0,3}" + fence.marker + "{" + fence.length + ",}[ \\t]*$");
      if (closing.test(line)) fence = null;
      return null;
    }
    const opening = line.match(/^ {0,3}(`{3,}|~{3,})/);
    if (opening) {
      fence = { marker: opening[1][0], length: opening[1].length };
      return null;
    }
    return line;
  });
}

function assertMatches(document, checks, label) {
  const missing = checks.filter(({ pattern }) => !pattern.test(document)).map(({ name }) => name);
  if (missing.length > 0) {
    throw new Error(label + "の必須項目が不足しています: " + missing.join("、"));
  }
}

function assertNoBodyCodePositions(document, label) {
  const body = protectNetworkAuthorities(
    normalizeDigits(withoutHtmlComments(document.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, ""))),
  );
  const sourceFile = String.raw`(?:[\p{L}\p{N}_.-]+[\\/])*[\p{L}\p{N}_.-]+\.(?:py|ts|tsx|js|jsx|mjs|cjs|vue|svelte|java|kt|cs|go|rs|rb|php|swift|scala|sql|sh|bash|zsh|ps1|c|cpp|h|hpp|html|css|scss|xml|yaml|yml|json|toml|ini|conf|properties|proto|graphql|tf|hcl)(?![\p{L}\p{N}_])`;
  const fileLine = String.raw`(?:[\p{L}\p{N}_.-]+[\\/])+[\p{L}\p{N}_.-]+[：:]\d+`;
  const forbidden = [
    /#<[^>\n]+>:<[^>\n]+>/u,
    new RegExp(sourceFile, "u"),
    new RegExp(fileLine, "u"),
    /[（(]\s*(?:L\s*)?\d+\s*行目?\s*[）)]/u,
    /(?:^|[^\d:])\d+\s*行目/u,
    /(?:^|[^\p{L}\p{N}_])L\d+(?=$|[^\p{L}\p{N}_])/mu,
    /(ファイル名?|対象ファイル)[^\n]{0,20}(行番号|\d+行目)/u,
  ];
  if (forbidden.some((pattern) => pattern.test(body))) {
    throw new Error(label + "の本文に対象コードのファイル名または行番号があります");
  }
}

function assertNoEvidenceColumn(document, label) {
  const lines = visibleMarkdownLines(withoutHtmlComments(document));
  const hasEvidenceColumn = lines.some((line, index) => {
    if (typeof line !== "string" || !/^\|.*\|$/.test(line)) return false;
    const cells = line.slice(1, -1).split("|").map((cell) => cell.trim());
    if (!cells.includes("根拠")) return false;
    const separator = lines[index + 1];
    if (typeof separator !== "string" || !/^\|.*\|$/.test(separator)) return false;
    const parts = separator.slice(1, -1).split("|").map((cell) => cell.trim());
    return parts.length === cells.length && parts.every((cell) => /^:?-{3,}:?$/.test(cell));
  });
  if (hasEvidenceColumn) throw new Error(label + "に根拠列があります");
}

function validateConventions(document) {
  assertMatches(
    document,
    [
      { name: "型", pattern: /^## §1 型の記述$/m },
      { name: "有効な範囲", pattern: /^## §2 有効な範囲の記述$/m },
      { name: "NULL許容", pattern: /^## §3 NULL 許容の記述$/m },
      { name: "初期値・既定値", pattern: /^## §4 初期値・既定値の記述$/m },
      { name: "桁と精度", pattern: /^## §5 桁と精度の記述$/m },
      { name: "疑似コード", pattern: /^## §6 疑似コードの記述$/m },
    ],
    "詳細設計記述規約",
  );
  const pseudocode = section(document, "## §6 疑似コードの記述", "## §7");
  assertMatches(
    pseudocode,
    [
      { name: "実装位置の禁止", pattern: /対象コードのファイルパスや行番号を記録しない/ },
      { name: "文書内参照への限定", pattern: /参照先[^\n]*文書内の節番号[^\n]*関数単位の契約/ },
    ],
    "詳細設計記述規約の§6",
  );
  if (/根拠台帳へ(?:記録|移す)|対象コードのファイル・行を(?:記録|記載)|行番号の注記を(?:付ける|記載する|求める)/u.test(pseudocode)) {
    throw new Error("詳細設計記述規約の§6に廃止済みのコード位置記録があります");
  }
}

function validateDetailedDesign(document, label) {
  assertMatches(
    document,
    [
      { name: "型", pattern: /\|[^\n|]*(型|型名)[^\n]*\|/ },
      { name: "有効な範囲", pattern: /\|[^\n|]*(有効な範囲|スコープ)[^\n]*\|/ },
      { name: "NULL許容", pattern: /\|[^\n|]*NULL許容[^\n]*\|/ },
      { name: "初期値", pattern: /\|[^\n|]*(初期値|既定値)[^\n]*\|/ },
      { name: "桁と精度", pattern: /\|[^\n|]*桁と精度[^\n]*\|/ },
      { name: "疑似コード", pattern: /^## §6 疑似コード$/m },
    ],
    label,
  );
  assertNoEvidenceColumn(document, label);
  assertNoBodyCodePositions(document, label);
}

function buildSyntheticDetailedDesign(template) {
  const header =
    "| 名前 | 型 | 必須 | 有効な範囲 | NULL許容 | 初期値 | 桁と精度 | 制約 |\n" +
    "|---|---|---|---|---|---|---|---|";
  const example =
    header +
    "\n| 会員番号 | string（文字列） | 必須 | 要求内 | 不許容 | なし | 最大12文字 | 英数字 |";
  const pseudocode =
    "~~~text\n入力項目を順に繰り返す\n不正な場合は処理を終了する\n取得結果を返して終了する\n~~~";
  return template
    .replace(header, example)
    .replace(/<!-- 分岐と繰り返しの入れ子だけを日本語で書く。[\s\S]*?-->/, "")
    .replace("`PSEUDOCODE`", pseudocode);
}

function runSelfTest() {
  const conventions = fs.readFileSync(conventionsPath, "utf8");
  const apiTemplate = fs.readFileSync(apiTemplatePath, "utf8");
  const synthetic = buildSyntheticDetailedDesign(apiTemplate);
  const checks = [
    ["詳細設計記述規約", () => validateConventions(conventions)],
    ["API詳細設計テンプレート", () => validateDetailedDesign(apiTemplate, "API詳細設計テンプレート")],
    ["合成詳細設計書", () => validateDetailedDesign(synthetic, "合成詳細設計書")],
    ["行番号注記を拒否", () => {
      let rejected = false;
      try {
        validateDetailedDesign(
          synthetic.replace("入力項目を順に繰り返す", "入力項目を src/api/member.ts:42 の順に処理する"),
          "違反フィクスチャ",
        );
      } catch {
        rejected = true;
      }
      if (!rejected) throw new Error("file:lineを不合格にできません");
    }],
    ["根拠列を拒否", () => {
      const invalid = synthetic
        .replace(
          "| 名前 | 型 | 必須 | 有効な範囲 | NULL許容 | 初期値 | 桁と精度 | 制約 |",
          "| 名前 | 型 | 必須 | 有効な範囲 | NULL許容 | 初期値 | 桁と精度 | 制約 | 根拠 |",
        )
        .replace("|---|---|---|---|---|---|---|---|", "|---|---|---|---|---|---|---|---|---|");
      let rejected = false;
      try {
        validateDetailedDesign(invalid, "違反フィクスチャ");
      } catch {
        rejected = true;
      }
      if (!rejected) throw new Error("根拠列を不合格にできません");
    }],
  ];

  let failed = 0;
  for (const [name, run] of checks) {
    try {
      run();
      console.log("[PASS] " + name);
    } catch (error) {
      failed += 1;
      console.error("[FAIL] " + name + ": " + error.message);
    }
  }
  console.log("実測: PASS " + (checks.length - failed) + " / FAIL " + failed);
  process.exitCode = failed === 0 ? 0 : 1;
}

if (process.argv.length === 2 || process.argv[2] === "--self-test") {
  runSelfTest();
} else {
  console.error("使い方: node check-detailed-design-conventions.cjs --self-test");
  process.exitCode = 2;
}
