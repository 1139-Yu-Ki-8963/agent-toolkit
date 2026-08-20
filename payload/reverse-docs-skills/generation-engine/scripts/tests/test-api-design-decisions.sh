#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
fixture_dir="$script_dir/fixtures/api-design-decisions"
skill="$repo_root/.claude/skills/generating-api-detail-design-for-reverse-docs/SKILL.md"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/api-design-decisions.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/output"

grep -qF 'コードコメントを `観測（コードコメント）` に分類できるのは' "$skill"
grep -qF 'TODO、過去の経緯だけを述べるコメント、却下済み案の説明、別処理を説明する近接コメントは観測から除外する' "$skill"
grep -qF '確からしさは `medium` または `low` に限り、推定に `high` を使わない' "$skill"
grep -qF '両欄を `不明（原本に記述なし）` とする' "$skill"
grep -qF '12.5 の推定は設計理由だけを対象とする。仕様値、型、制約、既定値を推定する例外ではない' "$skill"
grep -qF '設計単位根拠台帳へ回す' "$skill"

bash "$repo_root/generation-engine/scripts/scaffold-design-unit.sh" \
  api detail "$tmp/output" inventory-cache "在庫確認" \
  "$repo_root/delivery-payload/templates/リバース検証" >/dev/null

doc="$tmp/output/docs/design/apis/api-inventory-cache/詳細設計/API詳細設計書.md"
ledger="$tmp/output/docs/design/apis/api-inventory-cache/設計単位根拠台帳.md"
node - "$fixture_dir/comment-source.py" "$fixture_dir/api-manifest.ext.json" "$doc" <<'NODE'
const fs = require("fs");
const [sourcePath, manifestPath, documentPath] = process.argv.slice(2);
const source = fs.readFileSync(sourcePath, "utf8");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const marker = source.match(/^\s*# design-decision: (\{.+\})$/m);
if (!marker) throw new Error("design-decision comment not found");
const decision = JSON.parse(marker[1]);
const unit = manifest.units[0];
let document = fs.readFileSync(documentPath, "utf8");
const replacements = {
  APIKEY: unit.unitKey,
  APIID: unit.unitId,
  METHOD: unit.method,
  PATH: "/api/members",
  FEATUREKEY: unit.featureKey,
  SOURCEREF: unit.sourceFile,
};
for (const [token, value] of Object.entries(replacements)) {
  document = document.replaceAll(token, value);
}
document = document.replace(
  "### 1.2 業務上の役割",
  "### 1.2 業務上の役割\n\n外部URLは https://example.com:443/api である。接続先は api.example.com:8443 と api.example.rs:8443 である。",
);
const functionHeader = "| 関数 | 役割 |\n|---|---|";
document = document.replace(
  functionHeader,
  `${functionHeader}\n| fetch_inventory | 在庫情報を取得する |`,
);
const separator = "|---|---|---|---|---|---|---|---|";
const row = `| ${decision.key} | ${decision.decision} | ${decision.reason} | 観測（コードコメント） | 現在の選択と理由を直接結ぶコメント | ${decision.alternative} | ${decision.rejection} | ${decision.confidence} |`;
const decisionHeading = "### 12.5 設計判断とその理由";
const headingIndex = document.indexOf(decisionHeading);
const separatorIndex = document.indexOf(separator, headingIndex);
if (headingIndex < 0 || separatorIndex < 0) throw new Error("design decision table not found");
document = `${document.slice(0, separatorIndex)}${separator}\n${row}${document.slice(separatorIndex + separator.length)}`;
fs.writeFileSync(documentPath, document);
NODE

cp "$repo_root/delivery-payload/templates/リバース検証/設計単位共通/設計単位根拠台帳.md" "$ledger"
node - "$ledger" <<'NODE'
const fs = require("fs");
const ledgerPath = process.argv[2];
let ledger = fs.readFileSync(ledgerPath, "utf8");
ledger = ledger
  .replace("<YYYY-MM-DD>", "2026-08-20")
  .replace("<対象名>", "在庫確認")
  .replace(
    "| `<設計書名>` | `<節番号と見出し>` | `<表の項目名または記述の要約>` | `<対象コードの相対パス>` | `<行番号>` |",
    "| API詳細設計書.md | §12.5 設計判断とその理由 | local-cache-choice | comment-source.py | 2 |",
  );
fs.writeFileSync(ledgerPath, ledger);
NODE

bash "$repo_root/generation-engine/scripts/scaffold-design-unit.sh" \
  --verify api detail "$tmp/output" inventory-cache "在庫確認" \
  "$repo_root/delivery-payload/templates/リバース検証" >/dev/null
node "$repo_root/generation-engine/scripts/validate-api-design-decisions.mjs" "$doc" >/dev/null
node "$repo_root/generation-engine/scripts/tests/check-detailed-design-conventions.cjs" \
  --check-evidence-ledger "$ledger" "$fixture_dir" >/dev/null
grep -qF '| パス | /api/members |' "$doc"
grep -qF '| local-cache-choice | ローカルキャッシュを使う | 外部在庫サービスの一時障害で注文受付を止めないため | 観測（コードコメント） |' "$doc"
grep -qF '| 同期照会 | 外部在庫サービスの一時障害で注文受付を止めないため | high |' "$doc"
if grep -qF '注文受付を停止して在庫サービスの復旧を待つ' "$doc"; then
  echo "FAIL: 却下済み案のコメントを設計判断へ転記した" >&2
  exit 1
fi

invalid_inference="$tmp/invalid-inference.md"
cp "$doc" "$invalid_inference"
sed -i.bak 's/観測（コードコメント）/推定（実装構造）/' "$invalid_inference"
if node "$repo_root/generation-engine/scripts/validate-api-design-decisions.mjs" "$invalid_inference" >/dev/null 2>&1; then
  echo "FAIL: 推定に high を指定した文書を検出できない" >&2
  exit 1
fi

missing_reason="$tmp/missing-reason.md"
cp "$doc" "$missing_reason"
sed -i.bak '/| local-cache-choice |/d' "$missing_reason"
node "$repo_root/generation-engine/scripts/validate-api-design-decisions.mjs" "$missing_reason" >/dev/null
grep -qF '| 根拠を記録する資料 | `../設計単位根拠台帳.md` |' "$missing_reason"

invalid_file_line="$tmp/invalid-file-line.md"
cp "$doc" "$invalid_file_line"
sed -i.bak 's/### 1.2 業務上の役割/### 1.2 業務上の役割 src\/api\/member.py:42/' "$invalid_file_line"
if node "$repo_root/generation-engine/scripts/validate-api-design-decisions.mjs" "$invalid_file_line" >/dev/null 2>&1; then
  echo "FAIL: 本文のfile:lineを検出できない" >&2
  exit 1
fi

invalid_parenthesized_line="$tmp/invalid-parenthesized-line.md"
cp "$doc" "$invalid_parenthesized_line"
sed -i.bak 's/### 1.2 業務上の役割/### 1.2 業務上の役割（42行目）/' "$invalid_parenthesized_line"
if node "$repo_root/generation-engine/scripts/validate-api-design-decisions.mjs" "$invalid_parenthesized_line" >/dev/null 2>&1; then
  echo "FAIL: 本文のファイル名を省いた括弧書きを検出できない" >&2
  exit 1
fi

invalid_sentence_line="$tmp/invalid-sentence-line.md"
cp "$doc" "$invalid_sentence_line"
sed -i.bak 's/### 1.2 業務上の役割/### 1.2 業務上の役割（対象ファイルの42行目を参照）/' "$invalid_sentence_line"
if node "$repo_root/generation-engine/scripts/validate-api-design-decisions.mjs" "$invalid_sentence_line" >/dev/null 2>&1; then
  echo "FAIL: 本文の文中行番号を検出できない" >&2
  exit 1
fi

invalid_unlisted_file_line="$tmp/invalid-unlisted-file-line.md"
cp "$doc" "$invalid_unlisted_file_line"
sed -i.bak 's/### 1.2 業務上の役割/### 1.2 業務上の役割 components\/member.vue:42/' "$invalid_unlisted_file_line"
if node "$repo_root/generation-engine/scripts/validate-api-design-decisions.mjs" "$invalid_unlisted_file_line" >/dev/null 2>&1; then
  echo "FAIL: 許可拡張子一覧外のfile:lineを検出できない" >&2
  exit 1
fi

invalid_fullwidth_line="$tmp/invalid-fullwidth-line.md"
cp "$doc" "$invalid_fullwidth_line"
sed -i.bak 's/### 1.2 業務上の役割/### 1.2 業務上の役割（４２行目）/' "$invalid_fullwidth_line"
if node "$repo_root/generation-engine/scripts/validate-api-design-decisions.mjs" "$invalid_fullwidth_line" >/dev/null 2>&1; then
  echo "FAIL: 全角数字の文中行番号を検出できない" >&2
  exit 1
fi

invalid_url_code_position="$tmp/invalid-url-code-position.md"
cp "$doc" "$invalid_url_code_position"
sed -i.bak 's|https://example.com:443/api|https://git.example/repo/components/member.vue#L42|' "$invalid_url_code_position"
if node "$repo_root/generation-engine/scripts/validate-api-design-decisions.mjs" "$invalid_url_code_position" >/dev/null 2>&1; then
  echo "FAIL: URL内のコード位置を検出できない" >&2
  exit 1
fi

echo "PASS: コメント付き合成フィクスチャから設計判断を生成して検証"
