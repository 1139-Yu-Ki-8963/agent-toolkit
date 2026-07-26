#!/usr/bin/env bash
# validate-message-manifest.sh — 転記スキーマ専用の整合検証器
# メッセージ一覧（convert-message-doc-to-manifest.sh の出力）を検証する。
# 検出系の validate-manifest.sh とは契約が異なるため専用化。
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <manifest.json> | --self-test" >&2
  exit 1
fi

if [ "${1:-}" = "--self-test" ]; then
  script_path="$0"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-message-manifest-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  valid="$tmp/valid.json"
  invalid_type="$tmp/invalid-type.json"
  invalid_count="$tmp/invalid-count.json"
  jq -n --arg sourceDir "$tmp/src" '{
    generatedAt: "2026-01-01T00:00:00Z",
    unitKind: "message",
    sourceDir: $sourceDir,
    strategy: {extractionMethod: "markdown-table", approvedByUser: false},
    detectionSummary: {method: "markdown-table", unitCount: 2, unresolvedCount: 1},
    units: [
      {unitKey: "MSG-001", kind: "message", identifier: "MSG-001", confidence: "high",
       messageText: "登録しました", messageType: "success",
       sourceFile: ["src/messages.ts", "src/common.ts"], usedScreen: "users"},
      {unitKey: "MSG-002", kind: "message", identifier: "MSG-002", confidence: "high",
       messageText: "入力してください", messageType: "validation",
       sourceFile: [], usedScreen: "users"}
    ],
    summary: {totalCount: 2, byType: {success: 1, validation: 1}}
  }' > "$valid"
  jq '.units[0].sourceFile = "src/messages.ts"' "$valid" > "$invalid_type"
  jq '.summary.totalCount = 3' "$valid" > "$invalid_count"
  if bash "$script_path" "$valid" >/dev/null 2>&1 &&
    ! bash "$script_path" "$invalid_type" >/dev/null 2>&1 &&
    ! bash "$script_path" "$invalid_count" >/dev/null 2>&1; then
    echo "self-test 全項目 PASS"
    exit 0
  fi
  echo "self-test FAIL" >&2
  exit 1
fi

MANIFEST="$1"
if [ ! -f "$MANIFEST" ]; then
  echo "Error: manifest not found: $MANIFEST" >&2
  exit 1
fi

FAIL_COUNT=0
report() {
  local name="$1" status="$2"
  if [ "$status" -eq 0 ]; then
    printf '  [PASS] %s\n' "$name"
  else
    printf '  [FAIL] %s\n' "$name"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo "=== validate-message-manifest ==="

# 1. schema-必須フィールド（トップレベルと型）
top_ok=0
for key in generatedAt unitKind sourceDir strategy detectionSummary units summary; do
  if ! jq -e "has(\"$key\")" "$MANIFEST" >/dev/null 2>&1; then
    echo "    missing top-level key: $key" >&2
    top_ok=1
  fi
done
if ! jq -e '
  (.generatedAt | type == "string") and
  (.unitKind == "message") and
  (.sourceDir | type == "string") and
  (.strategy | type == "object") and
  (.strategy.extractionMethod | type == "string") and
  (.strategy.approvedByUser | type == "boolean") and
  (.detectionSummary | type == "object") and
  (.detectionSummary.method | type == "string") and
  (.detectionSummary.unitCount | type == "number") and
  (.detectionSummary.unresolvedCount | type == "number") and
  (.units | type == "array") and
  (.summary | type == "object")
' "$MANIFEST" >/dev/null 2>&1; then
  top_ok=1
fi
report "schema-トップレベル必須" "$top_ok"

# 2. schema-必須フィールド（各 unit と型）
item_ok=0
unit_count=$(jq '.units | length' "$MANIFEST" 2>/dev/null || echo 0)
for key in unitKey kind identifier confidence messageText messageType sourceFile usedScreen; do
  missing=$(jq --arg k "$key" '[.units[] | select(has($k) | not)] | length' "$MANIFEST" 2>/dev/null || echo 0)
  if [ "$missing" -gt 0 ]; then
    echo "    $missing units missing key: $key" >&2
    item_ok=1
  fi
done
if ! jq -e '
  all(.units[];
    (.unitKey | type == "string" and length > 0) and
    (.kind == "message") and
    (.identifier | type == "string" and length > 0) and
    (.confidence | type == "string" and length > 0) and
    (.messageText | type == "string") and
    (.messageType | type == "string") and
    (.sourceFile | type == "array" and all(.[]; type == "string" and length > 0)) and
    (.usedScreen | type == "string")
  )
' "$MANIFEST" >/dev/null 2>&1; then
  item_ok=1
fi
report "schema-ユニット必須" "$item_ok"

# 3. sourceFile 配列型
source_ok=0
if ! jq -e 'all(.units[]; (.sourceFile | type == "array") and all(.sourceFile[]; type == "string" and length > 0))' "$MANIFEST" >/dev/null 2>&1; then
  source_ok=1
fi
report "schema-sourceFile配列" "$source_ok"

# 4. 重複-unitKey
dup_ok=0
total_keys=$(jq '[.units[].unitKey] | length' "$MANIFEST" 2>/dev/null || echo 0)
unique_keys=$(jq '[.units[].unitKey] | unique | length' "$MANIFEST" 2>/dev/null || echo 0)
if [ "$total_keys" != "$unique_keys" ]; then
  echo "    duplicate unitKey detected: total=$total_keys unique=$unique_keys" >&2
  dup_ok=1
fi
report "重複-unitKey" "$dup_ok"

# 5. summary-一致
sum_ok=0
declared_total=$(jq '.summary.totalCount // -1' "$MANIFEST" 2>/dev/null || echo -1)
actual_total=$(jq '.units | length' "$MANIFEST" 2>/dev/null || echo 0)
if [ "$declared_total" != "$actual_total" ]; then
  echo "    totalCount mismatch: declared=$declared_total actual=$actual_total" >&2
  sum_ok=1
fi
report "summary-一致" "$sum_ok"

# 6. detectionSummary-一致
detection_ok=0
declared_detection=$(jq '.detectionSummary.unitCount // -1' "$MANIFEST" 2>/dev/null || echo -1)
if [ "$declared_detection" != "$actual_total" ]; then
  echo "    detectionSummary.unitCount mismatch: declared=$declared_detection actual=$actual_total" >&2
  detection_ok=1
fi
report "detectionSummary-一致" "$detection_ok"

# 7. summary.byType-一致
by_type_ok=0
declared_by_type="$(jq -c '.summary.byType // null' "$MANIFEST" 2>/dev/null || echo null)"
actual_by_type="$(jq -c '
  (.units | group_by(.messageType) | map({key: .[0].messageType, value: length}) | from_entries)
' "$MANIFEST" 2>/dev/null || echo null)"
if [ "$declared_by_type" != "$actual_by_type" ]; then
  echo "    byType mismatch: declared=$declared_by_type actual=$actual_by_type" >&2
  by_type_ok=1
fi
report "summary.byType-一致" "$by_type_ok"

# 8. detectionSummary.unresolvedCount-一致(sourceFile空配列数)
unresolved_ok=0
declared_unresolved="$(jq '.detectionSummary.unresolvedCount // -1' "$MANIFEST" 2>/dev/null || echo -1)"
actual_unresolved="$(jq '[.units[] | select((.sourceFile | type) == "array" and ((.sourceFile | length) == 0))] | length' "$MANIFEST" 2>/dev/null || echo -1)"
if [ "$declared_unresolved" != "$actual_unresolved" ]; then
  echo "    unresolvedCount mismatch: declared=$declared_unresolved actual=$actual_unresolved" >&2
  unresolved_ok=1
fi
report "detectionSummary.unresolvedCount-一致" "$unresolved_ok"

echo "=== $((8 - FAIL_COUNT))/8 PASS, ${FAIL_COUNT}/8 FAIL ==="
[ "$FAIL_COUNT" -eq 0 ]
