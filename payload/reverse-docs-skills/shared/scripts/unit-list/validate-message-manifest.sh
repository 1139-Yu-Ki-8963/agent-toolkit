#!/usr/bin/env bash
# validate-message-manifest.sh — 転記スキーマ専用の整合検証器
# メッセージ一覧（convert-message-doc-to-manifest.sh の出力）を検証する。
# 検出系の validate-manifest.sh とは契約が異なるため専用化。
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <manifest.json>" >&2
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

# 1. schema-必須フィールド（トップレベル）
top_ok=0
for key in generatedAt units summary; do
  if ! jq -e "has(\"$key\")" "$MANIFEST" >/dev/null 2>&1; then
    echo "    missing top-level key: $key" >&2
    top_ok=1
  fi
done
report "schema-トップレベル必須" "$top_ok"

# 2. schema-必須フィールド（各 unit）
item_ok=0
unit_count=$(jq '.units | length' "$MANIFEST" 2>/dev/null || echo 0)
for key in unitKey messageText messageType sourceFile usedScreen; do
  missing=$(jq --arg k "$key" '[.units[] | select(has($k) | not)] | length' "$MANIFEST" 2>/dev/null || echo 0)
  if [ "$missing" -gt 0 ]; then
    echo "    $missing units missing key: $key" >&2
    item_ok=1
  fi
done
report "schema-ユニット必須" "$item_ok"

# 3. 重複-unitKey
dup_ok=0
total_keys=$(jq '[.units[].unitKey] | length' "$MANIFEST" 2>/dev/null || echo 0)
unique_keys=$(jq '[.units[].unitKey] | unique | length' "$MANIFEST" 2>/dev/null || echo 0)
if [ "$total_keys" != "$unique_keys" ]; then
  echo "    duplicate unitKey detected: total=$total_keys unique=$unique_keys" >&2
  dup_ok=1
fi
report "重複-unitKey" "$dup_ok"

# 4. summary-一致
sum_ok=0
declared_total=$(jq '.summary.totalCount // -1' "$MANIFEST" 2>/dev/null || echo -1)
actual_total=$(jq '.units | length' "$MANIFEST" 2>/dev/null || echo 0)
if [ "$declared_total" != "$actual_total" ]; then
  echo "    totalCount mismatch: declared=$declared_total actual=$actual_total" >&2
  sum_ok=1
fi
report "summary-一致" "$sum_ok"

echo "=== $((4 - FAIL_COUNT))/4 PASS, ${FAIL_COUNT}/4 FAIL ==="
[ "$FAIL_COUNT" -eq 0 ]
