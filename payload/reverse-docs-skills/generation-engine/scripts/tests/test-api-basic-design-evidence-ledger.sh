#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TEMPLATE_ROOT="$REPO_ROOT/delivery-payload/templates/リバース検証"
DESIGN_TEMPLATE="$TEMPLATE_ROOT/API/API基本設計書.md"
LEDGER_TEMPLATE="$TEMPLATE_ROOT/設計単位共通/設計単位根拠台帳.md"
LAYOUT="$REPO_ROOT/delivery-payload/references/output-layout.json"
INVENTORY="$REPO_ROOT/delivery-payload/references/deliverable-inventory.json"
CATALOG="$REPO_ROOT/delivery-payload/references/portal-catalog.json"
SCAFFOLD="$REPO_ROOT/generation-engine/scripts/scaffold-design-unit.sh"

tmp_base="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
tmp="$(mktemp -d "$tmp_base/api-basic-evidence-ledger.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
failures=0

pass() { printf '  [PASS] %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1" >&2; failures=$((failures + 1)); }

printf '=== API基本設計書・設計単位根拠台帳 self-test ===\n'

evidence_header_count="$(awk -F'|' '
  /^\|/ {
    for (i = 2; i < NF; i += 1) {
      cell = $i
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell)
      if (cell == "根拠") count += 1
    }
  }
  END { print count + 0 }
' "$DESIGN_TEMPLATE")"
if [ "$evidence_header_count" -eq 0 ]; then
  pass "API基本設計書の15表に根拠列が無い"
else
  fail "API基本設計書に根拠列が残っている（${evidence_header_count}件）"
fi

layout_name="$(jq -r '.layout.unitEvidenceLedgerFile // empty' "$LAYOUT")"
inventory_count="$(jq '[.items[] | select(.kind == "unit-evidence-ledger" and .layoutKey == "unitEvidenceLedgerFile")] | length' "$INVENTORY")"
catalog_count="$(jq '[.categories[].blueprints[] | select(.kind == "unit-evidence-ledger")] | length' "$CATALOG")"
if [ "$layout_name" = "設計単位根拠台帳.md" ] && [ "$inventory_count" -eq 1 ] && [ "$catalog_count" -eq 1 ] && [ -f "$LEDGER_TEMPLATE" ]; then
  pass "根拠台帳の様式・配置・納品物定義が揃っている"
else
  fail "根拠台帳の様式・配置・納品物定義が不整合"
fi

mkdir -p "$tmp/src" "$tmp/out"
cat > "$tmp/src/order.py" <<'PY'
# evidence: §1 外部仕様 | 業務上の目的 | 注文を受け付ける
def accept_order(order):
# evidence: §2 業務仕様 | 注文受付 | 注文内容を受け取る
    if not order:
# evidence: §3 方式設計 | 性能 | 受付結果を直ちに返す
        raise ValueError("注文がありません")
# evidence: §4 データ仕様 | 注文 | 注文内容を扱う
# evidence: §5 エラーと例外 | 注文なし | 注文がない場合は受け付けない
# evidence: §6 関連資料 | 対象コード | 注文受付の対象コードを確認する
    return {"accepted": True}
PY

bash "$SCAFFOLD" api basic "$tmp/out" order "注文受付" "$TEMPLATE_ROOT" >/dev/null
unit_dir="$tmp/out/docs/design/apis/api-order"
design="$unit_dir/基本設計/API基本設計書.md"
ledger="$unit_dir/$layout_name"

awk '
  /<!--/ { in_comment = 1; next }
  /-->/ { in_comment = 0; next }
  !in_comment { print }
' "$design" > "$tmp/design.generated.md"
mv "$tmp/design.generated.md" "$design"
node - "$tmp/src/order.py" "$design" "$LEDGER_TEMPLATE" "$ledger" <<'NODE'
const fs = require('fs');
const [source, design, template, ledger] = process.argv.slice(2);
const sourceLines = fs.readFileSync(source, 'utf8').split(/\r?\n/);
const facts = sourceLines.flatMap((line, index) => {
  const match = line.match(/^# evidence: (.+?) \| (.+?) \| (.+)$/);
  if (!match) return [];
  const implementationIndex = sourceLines.findIndex((candidate, candidateIndex) =>
    candidateIndex > index && candidate.trim() !== '' && !candidate.startsWith('#')
  );
  if (implementationIndex < 0) throw new Error(`missing implementation after ${match[1]}`);
  return [{ section: match[1], item: match[2], description: match[3], line: implementationIndex + 1 }];
});
if (facts.length !== 6) throw new Error(`expected 6 source annotations, got ${facts.length}`);

let designText = fs.readFileSync(design, 'utf8').replace('status: draft', 'status: authored');
for (const fact of facts) {
  const heading = `## ${fact.section}`;
  const start = designText.indexOf(heading);
  const end = designText.indexOf('\n## ', start + heading.length);
  if (start < 0) throw new Error(`missing design section: ${fact.section}`);
  const insertion = `\n${fact.item}: ${fact.description}\n`;
  designText = designText.slice(0, end < 0 ? designText.length : end) + insertion + designText.slice(end < 0 ? designText.length : end);
}
fs.writeFileSync(design, designText);

let text = fs.readFileSync(template, 'utf8');
const replacements = [
  ['unit_kind: <種別>', 'unit_kind: api'],
  ['unit_key: <識別子>', 'unit_key: order'],
  ['status: draft', 'status: authored'],
  ['updated: <YYYY-MM-DD>', `updated: ${new Date().toISOString().slice(0, 10)}`],
  ['<対象名>', '注文受付']
];
for (const [from, to] of replacements) {
  if (!text.includes(from)) throw new Error(`missing template value: ${from}`);
  text = text.replace(from, to);
}
const sample = '| `<設計書名>` | `<節番号と見出し>` | `<表の項目名または記述の要約>` | `<対象コードの相対パス>` | `<行番号>` |';
const rows = facts.map((fact) =>
  `| API基本設計書.md | ${fact.section} | ${fact.item} | src/order.py | ${fact.line} |`
).join('\n');
if (!text.includes(sample)) throw new Error('missing evidence ledger row template');
fs.writeFileSync(ledger, text.replace(sample, rows));
console.log('  [INFO] 根拠台帳をテンプレート展開・frontmatter置換・根拠行書込みで合成生成');
NODE

pattern='interface [A-Z]|: *(string|number|boolean)\b|\bstyled-components\b|\bFastAPI\b|\bExpress\b|@app\.(get|post|put|delete)|\.(py|pl|pm|cgi)\b|api-manifest|unitId|unitKey|ioSummary|authRequired|dispatch-entry'
vocabulary_hits="$(grep -nE "$pattern" "$design" || true)"
if [ -z "$vocabulary_hits" ]; then
  pass "合成フィクスチャのAPI基本設計書が業務語彙の検査0件"
else
  fail "合成フィクスチャのAPI基本設計書が業務語彙の検査に抵触"
fi

if node - "$tmp/src/order.py" "$design" "$ledger" <<'NODE'
const fs = require('fs');
const [source, design, ledger] = process.argv.slice(2);
const sourceLines = fs.readFileSync(source, 'utf8').split(/\r?\n/);
const facts = sourceLines.flatMap((line, index) => {
  const match = line.match(/^# evidence: (.+?) \| (.+?) \| (.+)$/);
  if (!match) return [];
  const implementationIndex = sourceLines.findIndex((candidate, candidateIndex) =>
    candidateIndex > index && candidate.trim() !== '' && !candidate.startsWith('#')
  );
  if (implementationIndex < 0) throw new Error(`missing implementation after ${match[1]}`);
  return [{ section: match[1], item: match[2], description: match[3], line: implementationIndex + 1 }];
});
const designText = fs.readFileSync(design, 'utf8');
const ledgerText = fs.readFileSync(ledger, 'utf8');
const required = [
  'unit_kind: api',
  'unit_key: order',
  'status: authored',
  '| 対象文書 | 節 | 項目 | 対象コード | 行 |'
];
const missing = required.filter((value) => !ledgerText.includes(value));
if (ledgerText.includes('<YYYY-MM-DD>')) missing.push('updated placeholder');
for (const fact of facts) {
  const heading = `## ${fact.section}`;
  const start = designText.indexOf(heading);
  const end = designText.indexOf('\n## ', start + heading.length);
  if (start < 0 || !designText.slice(start, end < 0 ? designText.length : end).includes(fact.description)) {
    missing.push(`design description in ${fact.section}: ${fact.description}`);
  }
  const row = `| API基本設計書.md | ${fact.section} | ${fact.item} | src/order.py | ${fact.line} |`;
  if (!ledgerText.includes(row)) missing.push(`ledger row: ${row}`);
}
if (missing.length > 0) {
  console.error(`missing generated evidence: ${missing.join(', ')}`);
  process.exit(1);
}
NODE
then
  pass "合成生成の根拠台帳がfrontmatter・§1〜§6・項目・対象コード・行を対応づける"
else
  fail "合成生成の根拠台帳が設計書との根拠対応を満たさない"
fi

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: %s件\n' "$failures" >&2
  exit 1
fi
printf 'PASS: 4項目\n'
