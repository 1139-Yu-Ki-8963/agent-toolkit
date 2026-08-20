#!/usr/bin/env node

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "../../..");
const conventionsPath = path.join(
  repoRoot,
  "delivery-payload/templates/リバース検証/プロジェクト共通/詳細設計記述規約.md",
);
const apiTemplatePath = path.join(
  repoRoot,
  "delivery-payload/templates/リバース検証/API/API詳細設計書.md",
);
const evidenceLedgerTemplatePath = path.join(
  repoRoot,
  "delivery-payload/templates/リバース検証/設計単位共通/設計単位根拠台帳.md",
);

function section(document, heading, nextHeading) {
  const start = document.indexOf(heading);
  if (start < 0) {
    throw new Error(heading + " がありません");
  }
  const end = nextHeading ? document.indexOf(nextHeading, start + heading.length) : -1;
  return document.slice(start, end < 0 ? undefined : end);
}

function withoutHtmlComments(document) {
  return document.replace(/<!--[\s\S]*?-->/g, "");
}

function normalizeDigits(document) {
  return document.replace(/[０-９]/g, (digit) => String(digit.charCodeAt(0) - "０".charCodeAt(0)));
}

function protectNetworkAuthorities(document) {
  return document
    .replace(/\b(https?:\/\/)(?:\[[^\]]+\]|[^/\s|`]+)/gu, "$1<AUTHORITY>")
    .replace(/(?:\[[0-9a-f:]+\]|\blocalhost|\b(?:[a-z0-9-]+\.){2,}[a-z]{2,}|\b[a-z0-9-]+\.(?:com|org|net|edu|gov|mil|int|io|dev|app|cloud|local)|\b(?:\d{1,3}\.){3}\d{1,3}):\d{1,5}\b/giu, "<AUTHORITY>");
}

function visibleMarkdownLines(document) {
  let fence = null;
  return document.split(/\r?\n/).map((line) => {
    if (fence !== null) {
      const closing = new RegExp(`^ {0,3}${fence.marker}{${fence.length},}[ \\t]*$`);
      if (closing.test(line)) {
        fence = null;
      }
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
  const missing = checks
    .filter(({ pattern }) => !pattern.test(document))
    .map(({ name }) => name);
  if (missing.length > 0) {
    throw new Error(label + "の必須項目が不足しています: " + missing.join("、"));
  }
}

function assertNoBodyCodePositions(document, label) {
  const body = protectNetworkAuthorities(
    normalizeDigits(withoutHtmlComments(document.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, ""))),
  );
  const sourceFile = String.raw`(?:[\p{L}\p{N}_.-]+[\\/])*[\p{L}\p{N}_.-]+\.(?:py|pl|pm|cgi|ts|tsx|js|jsx|mjs|cjs|vue|svelte|java|kt|kts|cs|go|rs|rb|php|swift|scala|sql|sh|bash|zsh|fish|ps1|c|cc|cpp|h|hpp|html|css|scss|sass|less|xml|yaml|yml|json|toml|ini|conf|properties|gradle|groovy|ex|exs|erl|hrl|lua|r|fs|fsx|vb|sol|dart|proto|graphql|gql|tf|hcl|bicep|asm)(?![\p{L}\p{N}_])`;
  const fileLine = String.raw`(?:[\p{L}\p{N}_.-]+[\\/])+[\p{L}\p{N}_.-]+[：:]\d+`;
  const forbidden = [
    /#<[^>\n]+>:<[^>\n]+>/,
    /#[^\s#：:、。()（）]+:\d+(?=$|[\s、。;；:：（）()])/mu,
    new RegExp(sourceFile, "u"),
    new RegExp(fileLine, "u"),
    /[（(]\s*(?:L\s*)?\d+\s*行目?\s*[）)]/u,
    /(?:^|[^\d:])\d+\s*行目/u,
    /(?:^|[^\p{L}\p{N}_])L\d+(?=$|[^\p{L}\p{N}_])/mu,
    /(ファイル名?|対象ファイル)[^\n]{0,20}(行番号|\d+行目)/,
    /疑似コードの各行[^\n]{0,40}(行番号|ファイル名)/,
  ];
  if (forbidden.some((pattern) => pattern.test(body))) {
    throw new Error(label + "の本文に対象コードのファイル名または行番号があります");
  }
}

function assertNoEvidenceColumn(document, label) {
  const lines = visibleMarkdownLines(withoutHtmlComments(document));
  const hasEvidenceColumn = lines.some((line, index) => {
      if (!/^\|.*\|$/.test(line)) {
        return false;
      }
      const cells = line
        .slice(1, -1)
        .split("|")
        .map((cell) => cell.trim());
      if (!cells.includes("根拠")) {
        return false;
      }
      const separator = lines[index + 1];
      if (typeof separator !== "string" || !/^\|.*\|$/.test(separator)) {
        return false;
      }
      const separatorCells = separator.slice(1, -1).split("|").map((cell) => cell.trim());
      return separatorCells.length === cells.length && separatorCells.every((cell) => /^:?-{3,}:?$/.test(cell));
    });
  if (hasEvidenceColumn) {
    throw new Error(label + "に根拠列があります");
  }
}

function assertNoConventionLineRequirement(document) {
  const pseudocode = section(
    document.replace("## §6 疑似コードの記述", "## §6 疑似コード"),
    "## §6 疑似コード",
    "## §7",
  );
  const forbidden = [
    /#<[^>\n]+>:<[^>\n]+>/,
    /行番号の注記を(付ける|付す|記載する|求める)/,
    /疑似コードの各(?:処理)?行[^\n]{0,50}(付ける|付す|付記する|記載する|併記する|求める)/,
  ];
  if (forbidden.some((pattern) => pattern.test(pseudocode))) {
    throw new Error("詳細設計記述規約の§6が行番号の注記を要求しています");
  }
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
  assertNoConventionLineRequirement(document);
  const pseudocode = section(
    document.replace("## §6 疑似コードの記述", "## §6 疑似コード"),
    "## §6 疑似コード",
    "## §7",
  );
  assertMatches(
    pseudocode,
    [
      { name: "行番号注記の禁止", pattern: /ファイル名や行番号の注記を付けない/ },
      { name: "単位ごとの根拠資料", pattern: /疑似コードの記述根拠[^\n]*単位ごとの根拠資料/ },
    ],
    "詳細設計記述規約の§6",
  );
}

function validateDetailedDesign(document, label) {
  assertMatches(
    document,
    [
      { name: "型", pattern: /\|[^\n|]*(型|型名)[^\n]*\|/ },
      { name: "有効な範囲またはスコープ", pattern: /\|[^\n|]*(有効な範囲|スコープ)[^\n]*\|/ },
      { name: "NULL許容", pattern: /\|[^\n|]*NULL許容[^\n]*\|/ },
      { name: "初期値または既定値", pattern: /\|[^\n|]*(初期値|既定値)[^\n]*\|/ },
      { name: "桁と精度", pattern: /\|[^\n|]*桁と精度[^\n]*\|/ },
      { name: "疑似コード", pattern: /^## §6 疑似コード$/m },
    ],
    label,
  );
  assertNoEvidenceColumn(document, label);
  assertNoBodyCodePositions(document, label);
}

function validateSyntheticDetailedDesign(document) {
  validateDetailedDesign(document, "合成詳細設計書");
  const parameters = withoutHtmlComments(
    section(document, "### 2.1 パスパラメータ", "### 2.2"),
  );
  const pseudocode = withoutHtmlComments(
    section(document, "## §6 疑似コード", "## §7"),
  );
  assertMatches(
    parameters,
    [
      { name: "文字列型と文字数", pattern: /\| 会員番号 \| string（文字列）[^\n]*最大12文字/ },
      { name: "配列と要素型", pattern: /\| タグ \| string\[\]（配列、要素は文字列）/ },
      { name: "列挙と未定義値", pattern: /enum（列挙: active、inactive。未定義値は不許容）/ },
      { name: "有効な範囲の区分", pattern: /\| 要求内 \|/ },
      { name: "技術用語との対応", pattern: /関数内（ローカル変数）/ },
      { name: "NULLと空値の区別", pattern: /NULLは値なし、空文字は入力あり、空配列は0件/ },
      { name: "初期値と既定値", pattern: /初期値なし、未指定時は既定値active/ },
      { name: "小数の桁と丸め", pattern: /全体10桁・小数部2桁・四捨五入/ },
      { name: "日時の書式と精度", pattern: /ISO 8601・ミリ秒精度・UTC/ },
    ],
    "合成詳細設計書",
  );
  assertMatches(
    pseudocode,
    [
      { name: "分岐", pattern: /場合/ },
      { name: "繰り返し", pattern: /繰り返す/ },
      { name: "終了条件", pattern: /終了する/ },
    ],
    "合成詳細設計書の疑似コード",
  );
  if (/疑似コードの根拠は単位ごとの根拠資料に記録する/.test(withoutHtmlComments(document))) {
    throw new Error("合成詳細設計書に根拠資料への分離文が埋め込まれています");
  }
}

function buildSyntheticDetailedDesign(template) {
  const parameterHeader =
    "| 名前 | 型 | 必須 | 有効な範囲 | NULL許容 | 初期値 | 桁と精度 | 制約 |\n" +
    "|---|---|---|---|---|---|---|---|";
  const parameterExample =
    parameterHeader +
    "\n| 会員番号 | string（文字列） | 必須 | 要求内 | 不許容 | なし | 最大12文字 | 英数字 |" +
    "\n| タグ | string[]（配列、要素は文字列） | 任意 | 関数内（ローカル変数） | 不許容 | 空配列 | 最大10要素 | NULLは値なし、空文字は入力あり、空配列は0件 |" +
    "\n| 状態 | enum（列挙: active、inactive。未定義値は不許容） | 任意 | 要求内 | 不許容 | 初期値なし、未指定時は既定値active | 最大8文字 | 列挙外は拒否 |" +
    "\n| 金額 | decimal（数値） | 必須 | 要求内 | 不許容 | 0 | 全体10桁・小数部2桁・四捨五入 | 0以上 |" +
    "\n| 処理日時 | datetime（日付時刻） | 必須 | 要求内 | 不許容 | 動的に現在時刻を設定 | ISO 8601・ミリ秒精度・UTC | なし |";
  const pseudocode =
    "~~~text\n" +
    "入力項目を順に繰り返す\n" +
    "不正な項目がある場合は処理を終了する\n" +
    "入力が有効な場合は対象を取得する\n" +
    "取得結果を返して終了する\n" +
    "~~~";
  return template
    .replace(parameterHeader, parameterExample)
    .replace(
      /<!-- 分岐と繰り返しの入れ子だけを日本語で書く。[\s\S]*?-->/,
      "",
    )
    .replace(String.fromCharCode(96) + "PSEUDOCODE" + String.fromCharCode(96), pseudocode);
}

function buildSyntheticEvidence(template) {
  return template
    .replace(/<種別>/g, "api")
    .replace(/<識別子>/g, "member")
    .replace(/<YYYY-MM-DD>/g, "2026-08-20")
    .replace(/<対象名>/g, "会員取得API")
    .replace(
      "| `<設計書名>` | `<節番号と見出し>` | `<表の項目名または記述の要約>` | `<対象コードの相対パス>` | `<行番号>` |",
      "| API詳細設計書.md | §6 疑似コード | 入力検査後に会員を取得する | src/api/member.ts | 2 |",
    );
}

function validateEvidenceLedger(document, sourceDir) {
  const visibleLines = visibleMarkdownLines(withoutHtmlComments(document));
  const header = "| 対象文書 | 節 | 項目 | 対象コード | 行 |";
  const headerIndexes = visibleLines
    .map((line, index) => (line === header ? index : -1))
    .filter((index) => index >= 0);
  if (headerIndexes.length !== 1) {
    throw new Error("根拠台帳の完全一致する表ヘッダーが1件ではありません");
  }
  const [headerIndex] = headerIndexes;
  if (!/^\|(?:[ \t]*:?-{3,}:?[ \t]*\|){5}$/.test(visibleLines[headerIndex + 1] || "")) {
    throw new Error("根拠台帳の表ヘッダー直後に5列の区切り行がありません");
  }
  let detailedDesignRows = 0;
  const resolvedSourceDir = fs.realpathSync(sourceDir);
  for (let index = headerIndex + 2; index < visibleLines.length; index += 1) {
    const line = visibleLines[index];
    if (line === null || line === "" || /^##(?:#)? /.test(line)) {
      break;
    }
    if (!/^\|(?:[^|\n]*\|){5}$/.test(line)) {
      throw new Error("根拠台帳の表データ行が5列ではありません");
    }
    const [targetDocument, targetSection, item, targetCode, lineNumber] = line
      .slice(1, -1)
      .split("|")
      .map((cell) => cell.trim());
    if (!targetDocument || !targetSection || !item) {
      throw new Error("根拠台帳に対象文書・節・項目の欠落があります");
    }
    if (targetDocument === "API詳細設計書.md") {
      detailedDesignRows += 1;
    }
    if (targetCode === "該当なし" && lineNumber === "該当なし") {
      continue;
    }
    if (targetCode === "該当なし" || lineNumber === "該当なし") {
      throw new Error("対象コードと行の該当なし指定が一致していません");
    }
    if (path.isAbsolute(targetCode)) {
      throw new Error("対象コードが相対パスではありません");
    }
    const resolvedTarget = path.resolve(resolvedSourceDir, targetCode);
    if (!resolvedTarget.startsWith(resolvedSourceDir + path.sep) || !fs.existsSync(resolvedTarget)) {
      throw new Error("対象コードがsource_dir配下に実在しません");
    }
    const realTarget = fs.realpathSync(resolvedTarget);
    if (!realTarget.startsWith(resolvedSourceDir + path.sep)) {
      throw new Error("対象コードの実体がsource_dir外にあります");
    }
    if (!/^[1-9]\d*$/.test(lineNumber)) {
      throw new Error("行が1始まりの整数ではありません");
    }
    const sourceLines = fs.readFileSync(realTarget, "utf8").split(/\r?\n/);
    if (sourceLines[sourceLines.length - 1] === "") {
      sourceLines.pop();
    }
    if (Number(lineNumber) > sourceLines.length) {
      throw new Error("行が対象コードの実在行数を超えています");
    }
  }
  if (detailedDesignRows === 0) {
    throw new Error("根拠台帳にAPI詳細設計書の対応がありません");
  }
}

function runSelfTest() {
  const conventions = fs.readFileSync(conventionsPath, "utf8");
  const apiTemplate = fs.readFileSync(apiTemplatePath, "utf8");
  const evidenceLedgerTemplate = fs.readFileSync(evidenceLedgerTemplatePath, "utf8");
  const synthetic = buildSyntheticDetailedDesign(apiTemplate);
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "detail-design-conventions-"));
  const sourceDir = path.join(fixtureRoot, "source");
  const sourceFile = path.join(sourceDir, "src/api/member.ts");
  fs.mkdirSync(path.dirname(sourceFile), { recursive: true });
  fs.writeFileSync(sourceFile, "export const member = true;\nreturn member;\n", "utf8");
  const outsideFile = path.join(fixtureRoot, "outside.ts");
  const symlinkFile = path.join(sourceDir, "src/api/escape.ts");
  fs.writeFileSync(outsideFile, "export const outside = true;\n", "utf8");
  fs.symlinkSync(outsideFile, symlinkFile);
  const syntheticEvidence = buildSyntheticEvidence(evidenceLedgerTemplate);
  const checks = [
    {
      name: "生成元の雛形を特定",
      run: () => {
        if (!fs.statSync(conventionsPath).isFile()) {
          throw new Error("配布物の雛形がありません");
        }
        validateConventions(conventions);
      },
    },
    {
      name: "§6の行番号注記要求を撤去し根拠資料へ分離",
      run: () => {
        validateConventions(conventions);
        const invalidConventions = [
          conventions.replace(
            "ファイル名や行番号の注記を付けない",
            "ファイル名と行番号の注記を付ける",
          ),
          conventions.replace(
            "単位ごとの根拠資料に",
            "単位ごとの確認資料に",
          ),
          conventions.replace(
            "## §7 適合確認",
            "- 疑似コードの各行末尾に対象ファイルと行を出典として付記する。\n\n## §7 適合確認",
          ),
        ];
        for (const invalid of invalidConventions) {
          let rejected = false;
          try {
            validateConventions(invalid);
          } catch {
            rejected = true;
          }
          if (!rejected) {
            throw new Error("§6の要求欠落を不合格にできません");
          }
        }
      },
    },
    {
      name: "既存API詳細設計テンプレートの他項目を照合",
      run: () => validateDetailedDesign(apiTemplate, "API詳細設計テンプレート"),
    },
    {
      name: "合成詳細設計書の適合と違反検出",
      run: () => {
        validateSyntheticDetailedDesign(synthetic);
        validateSyntheticDetailedDesign(synthetic.replace("英数字 |", "根拠 |"));
        validateEvidenceLedger(syntheticEvidence, sourceDir);
        validateSyntheticDetailedDesign(
          synthetic.replace("入力項目を順に繰り返す", "09:30 に入力項目を順に繰り返す"),
        );
        const invalidFixtures = [
          synthetic.replace("string（文字列）", "string"),
          synthetic.replace(/\| 要求内 \|/g, "|  |"),
          synthetic.replace("NULLは値なし、空文字は入力あり、空配列は0件", "値の扱いは別途定義する"),
          synthetic.replace("初期値なし、未指定時は既定値active", "初期値と既定値は別途定義する"),
          synthetic.replace("最大12文字", "制限値なし"),
          synthetic.replace(/場合/g, "とき"),
          synthetic.replace("繰り返す", "確認する"),
          synthetic.replace(/終了する/g, "終える"),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す #src/api/member.ts:42（根拠）",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す (src/api/member.ts:42)",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返し、対象ファイルの42行目を参照する",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返し、src/api/member.ts の42行目を参照する",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す src/api/member.ts#L42",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す #src/api/member.ts:42、根拠",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返し、設計/会員処理.ts の42行目を参照する",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す src/handler#L42",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す 設計/会員処理.ts:42、根拠",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す src/handler:42。",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す 設計/会員処理.ts（42行目）",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す src/handler（42行目）",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す 設計/会員処理.ts：42",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す src/handler:42行目",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す src/handler:42を参照",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す 設計/会員処理.ts L42",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す components/member.vue:42",
          ),
          synthetic.replace(
            "入力項目を順に繰り返す",
            "入力項目を順に繰り返す（４２行目）",
          ),
          synthetic.replace(
            "| 会員番号 | string（文字列） | 必須 | 要求内 | 不許容 | なし | 最大12文字 | 英数字 |",
            "<!-- | 会員番号 | string（文字列） | 必須 | 要求内 | 不許容 | なし | 最大12文字 | 英数字 | -->",
          ),
          synthetic.replace(
            "| 会員番号 | string（文字列） | 必須 | 要求内 | 不許容 | なし | 最大12文字 | 英数字 |",
            "| 会員番号 | string（文字列） | 必須 | 要求内 | 不許容 | なし | 最大12文字 | 英数字 src/api/member.ts:42 |",
          ),
          synthetic
            .replace(
              "| 名前 | 型 | 必須 | 有効な範囲 | NULL許容 | 初期値 | 桁と精度 | 制約 |",
              "| 名前 | 型 | 必須 | 有効な範囲 | NULL許容 | 初期値 | 桁と精度 | 制約 | 根拠 |",
            )
            .replace("|---|---|---|---|---|---|---|---|", "|---|---|---|---|---|---|---|---|---|"),
        ];
        for (const [index, invalid] of invalidFixtures.entries()) {
          let rejected = false;
          try {
            validateSyntheticDetailedDesign(invalid);
          } catch {
            rejected = true;
          }
          if (!rejected) {
            throw new Error("必須項目欠落または行番号注記を不合格にできません: fixture " + index);
          }
        }
        const evidenceRow =
          "| API詳細設計書.md | §6 疑似コード | 入力検査後に会員を取得する | src/api/member.ts | 2 |";
        const invalidEvidenceFixtures = [
          syntheticEvidence.replace("| 対象文書 | 節 | 項目 | 対象コード | 行 |", "| 設計項目 | 対象コード |"),
          syntheticEvidence.replace(evidenceRow, "| API詳細設計書.md | §6 疑似コード | 入力検査後に会員を取得する | src/api/member.ts | 0 |"),
          syntheticEvidence.replace(evidenceRow, "| API詳細設計書.md | §6 疑似コード | 入力検査後に会員を取得する | src/api/member.ts | 3 |"),
          syntheticEvidence.replace(evidenceRow, "| API詳細設計書.md | §6 疑似コード | 入力検査後に会員を取得する | src/api/missing.ts | 2 |"),
          syntheticEvidence.replace(evidenceRow, "| API詳細設計書.md | §6 疑似コード | 入力検査後に会員を取得する | 該当なし | 2 |"),
          syntheticEvidence.replace(evidenceRow, "| API基本設計書.md | §6 疑似コード | 入力検査後に会員を取得する | src/api/member.ts | 2 |"),
          syntheticEvidence.replace(evidenceRow, "| API詳細設計書.md | §6 疑似コード | 入力検査後に会員を取得する | src/api/escape.ts | 1 |"),
          syntheticEvidence.replace(evidenceRow, "| malformed |"),
          `~~~text\n${syntheticEvidence}\n~~~`,
          `\`\`\`\`text\n${syntheticEvidence}\n\`\`\``,
          `\`\`\`text\n${syntheticEvidence}\n\`\`\`still-code`,
          `${syntheticEvidence}\n\n${syntheticEvidence}`,
        ];
        for (const invalid of invalidEvidenceFixtures) {
          let rejected = false;
          try {
            validateEvidenceLedger(invalid, sourceDir);
          } catch {
            rejected = true;
          }
          if (!rejected) {
            throw new Error("根拠資料の対応欠落を不合格にできません");
          }
        }
      },
    },
  ];

  let failed = 0;
  for (const check of checks) {
    try {
      check.run();
      console.log("[PASS] " + check.name);
    } catch (error) {
      failed += 1;
      console.error("[FAIL] " + check.name + ": " + error.message);
    }
  }
  console.log("実測: PASS " + (checks.length - failed) + " / FAIL " + failed);
  fs.rmSync(fixtureRoot, { recursive: true, force: true });
  process.exitCode = failed === 0 ? 0 : 1;
}

if (process.argv.length === 2 || process.argv[2] === "--self-test") {
  runSelfTest();
} else if (process.argv[2] === "--check-evidence-ledger" && process.argv.length === 5) {
  const ledgerPath = path.resolve(process.argv[3]);
  const sourceDir = path.resolve(process.argv[4]);
  try {
    validateEvidenceLedger(fs.readFileSync(ledgerPath, "utf8"), sourceDir);
    console.log("[PASS] 設計単位根拠台帳: " + ledgerPath);
  } catch (error) {
    console.error("[FAIL] 設計単位根拠台帳: " + error.message);
    process.exitCode = 1;
  }
} else {
  console.error("使い方: node check-detailed-design-conventions.cjs --self-test");
  console.error("        node check-detailed-design-conventions.cjs --check-evidence-ledger <台帳> <source_dir>");
  process.exitCode = 2;
}
