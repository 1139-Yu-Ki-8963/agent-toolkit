#!/usr/bin/env bash
# validate-message-manifest.sh — message 完全契約専用の整合検証器
#
# Usage: validate-message-manifest.sh <manifest.json>
#        validate-message-manifest.sh --self-test
set -euo pipefail

run_validate() {
  local manifest="$1" fail_count=0
  report() {
    local name="$1" status="$2"
    if [ "$status" -eq 0 ]; then printf '  [PASS] %s\n' "$name"
    else printf '  [FAIL] %s\n' "$name"; fail_count=$((fail_count + 1)); fi
  }

  echo "=== validate-message-manifest ==="
  local top_ok=0
  for key in generatedAt sourceDir unitKind strategy detectionSummary units summary; do
    if ! jq -e "has(\"$key\")" "$manifest" >/dev/null 2>&1; then
      echo "    missing top-level key: $key" >&2; top_ok=1
    fi
  done
  if [ "$(jq -r '(.generatedAt | type) == "string" and (.sourceDir | type) == "string" and .unitKind == "message" and ((.units | type) == "array") and ((.summary | type) == "object") and ((.detectionSummary | type) == "object")' "$manifest" 2>/dev/null || echo false)" != "true" ]; then
    echo "    generatedAt/sourceDir/unitKind/units/summary/detectionSummary type mismatch" >&2; top_ok=1
  fi
  report "schema-トップレベル完全契約" "$top_ok"

  local strategy_ok=0
  if [ "$(jq -r '(.strategy | type) == "object" and ((.strategy.extractionMethod // "") | type) == "string" and ((.strategy.extractionMethod // "") | length > 0) and .strategy.approvedByUser == false and (.strategy | has("unitIdRegex")) and ((.strategy.unitIdRegex == null) or (.strategy.unitIdRegex | type) == "string") and ((.strategy.excludePatterns | type) == "array")' "$manifest" 2>/dev/null || echo false)" != "true" ]; then
    echo "    strategy must declare extractionMethod, approvedByUser=false, unitIdRegex, excludePatterns" >&2; strategy_ok=1
  fi
  report "strategy-完全契約" "$strategy_ok"

  local detection_ok=0
  if [ "$(jq -r '(.detectionSummary.method | type) == "string" and (.detectionSummary.method | length) > 0 and (.detectionSummary.unitCount | type) == "number" and (.detectionSummary.unitCount | floor == .) and .detectionSummary.unitCount >= 0 and (.detectionSummary.unresolvedCount | type) == "number" and (.detectionSummary.unresolvedCount | floor == .) and .detectionSummary.unresolvedCount >= 0' "$manifest" 2>/dev/null || echo false)" != "true" ]; then
    echo "    detectionSummary must declare method and non-negative integer counts" >&2; detection_ok=1
  fi
  report "detectionSummary-完全契約" "$detection_ok"

  local item_ok=0
  for key in unitKey unitNameGuess kind identifier confidence messageText messageType sourceFile usedScreen; do
    local missing
    missing=$(jq --arg k "$key" '[.units[]? | select(has($k) | not)] | length' "$manifest" 2>/dev/null || echo 0)
    if [ "$missing" -gt 0 ]; then echo "    $missing units missing key: $key" >&2; item_ok=1; fi
  done
  if [ "$(jq -r '[.units[]? | select((.unitKey | type) != "string" or (.unitNameGuess | type) != "string" or (.kind | type) != "string" or (.identifier | type) != "string" or (.confidence | type) != "string" or (.messageText | type) != "string" or (.messageType | type) != "string" or (.usedScreen | type) != "string" or (.sourceFile | type) != "array" or any(.sourceFile[]?; type != "string"))] | length == 0' "$manifest" 2>/dev/null || echo false)" != "true" ]; then
    echo "    unitKey/unitNameGuess/kind/identifier/confidence/messageText/messageType/usedScreen must be strings and sourceFile must be string[]" >&2; item_ok=1
  fi
  report "schema-ユニット完全契約" "$item_ok"

  local dup_ok=0 total_keys unique_keys
  total_keys=$(jq '[.units[]?.unitKey] | length' "$manifest" 2>/dev/null || echo 0)
  unique_keys=$(jq '[.units[]?.unitKey] | unique | length' "$manifest" 2>/dev/null || echo 0)
  if [ "$total_keys" != "$unique_keys" ]; then
    echo "    duplicate unitKey detected: total=$total_keys unique=$unique_keys" >&2; dup_ok=1
  fi
  report "重複-unitKey" "$dup_ok"

  local summary_ok=0 declared_total actual_total declared_unresolved actual_unresolved declared_by_type actual_by_type declared_unit_count
  declared_total=$(jq '.summary.totalCount // -1' "$manifest" 2>/dev/null || echo -1)
  declared_unit_count=$(jq '.detectionSummary.unitCount // -1' "$manifest" 2>/dev/null || echo -1)
  actual_total=$(jq '.units | length' "$manifest" 2>/dev/null || echo 0)
  declared_unresolved=$(jq '.detectionSummary.unresolvedCount // -1' "$manifest" 2>/dev/null || echo -1)
  actual_unresolved=$(jq '[.units[]? | select(.kind == "unresolved")] | length' "$manifest" 2>/dev/null || echo 0)
  declared_by_type=$(jq -c '.summary.byType // null' "$manifest" 2>/dev/null || echo null)
  actual_by_type=$(jq -c '[.units[]?] | group_by(.messageType) | map({key: .[0].messageType, value: length}) | from_entries' "$manifest" 2>/dev/null || echo '{}')
  if [ "$(jq -r '(.summary.totalCount | type) == "number" and (.summary.totalCount | floor == .) and .summary.totalCount >= 0 and (.summary.byType | type) == "object" and all(.summary.byType[]?; (type == "number") and (floor == .) and . >= 0)' "$manifest" 2>/dev/null || echo false)" != "true" ] || [ "$declared_total" != "$actual_total" ] || [ "$declared_unit_count" != "$actual_total" ] || [ "$declared_unresolved" != "$actual_unresolved" ] || [ "$declared_by_type" != "$actual_by_type" ]; then
    echo "    count mismatch: total=$declared_total/$actual_total unitCount=$declared_unit_count/$actual_total unresolved=$declared_unresolved/$actual_unresolved byType=$declared_by_type/$actual_by_type" >&2
    summary_ok=1
  fi
  report "summary/detectionSummary-一致" "$summary_ok"
  echo "=== $((6 - fail_count))/6 PASS, ${fail_count}/6 FAIL ==="
  [ "$fail_count" -eq 0 ]
}

self_test() {
  local script_dir tmp rc=0
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-message-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/プロジェクト共通" "$tmp/repo" "$tmp/docs/project-portal"
  cat > "$tmp/docs/プロジェクト共通/メッセージ定義書.md" <<'EOF'
| キー | 文言(実測) | 種別 | 抽出元 | 使用画面 |
|---|---|---|---|---|
| login-required | ログインしてください | error | src/auth.ts, src/guard.ts | ログイン |
EOF
  local manifest="$tmp/message.json" output="$tmp/docs/一覧/メッセージ一覧/メッセージ一覧.html"
  "$script_dir/../extract/convert-message-doc-to-manifest.sh" "$tmp/docs/プロジェクト共通/メッセージ定義書.md" "$manifest"
  if run_validate "$manifest" >/dev/null 2>&1 \
    && [ "$(jq -r '.units[0].sourceFile | length' "$manifest")" = "2" ] \
    && [ "$(jq -r '.strategy.approvedByUser' "$manifest")" = "false" ] \
    && "$script_dir/build-unit-list.sh" "$manifest" "$output" --unit-kind message >/dev/null 2>&1 \
    && sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' "$output" | sed '1d;$d' | jq -cS . > "$tmp/embedded.json" \
    && jq -cS . "$manifest" > "$tmp/original.json" \
    && diff -q "$tmp/embedded.json" "$tmp/original.json" >/dev/null \
    && grep -q 'href="../../index.html"' "$output"; then
    echo "  [PASS] pipeline: 変換→validator→HTML→埋め込みJSON再検証（sourceFile配列・戻りリンクを含む）"
  else
    echo "  [FAIL] pipeline: 完全契約の変換→HTMLパイプライン" >&2; rc=1
  fi
  local bad="$tmp/bad.json"
  jq 'del(.detectionSummary) | .units[0].sourceFile = "src/auth.ts"' "$manifest" > "$bad"
  if run_validate "$bad" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性: 完全契約欠落・sourceFile文字列を受け入れた" >&2; rc=1
  else
    echo "  [PASS] 陰性: 完全契約欠落・sourceFile文字列でFAIL"
  fi
  local required_string_key
  for required_string_key in unitKey unitNameGuess kind identifier confidence messageText messageType usedScreen; do
    jq --arg k "$required_string_key" '.units[0][$k] = null' "$manifest" > "$bad"
    if run_validate "$bad" >/dev/null 2>&1; then
      echo "  [FAIL] 陰性: ${required_string_key}=nullを受け入れた" >&2; rc=1
    else
      echo "  [PASS] 陰性: ${required_string_key}=nullでFAIL"
    fi
  done
  jq '.summary.totalCount = "1"' "$manifest" > "$bad"
  if run_validate "$bad" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性: summary.totalCount文字列を受け入れた" >&2; rc=1
  else
    echo "  [PASS] 陰性: summary.totalCount文字列でFAIL"
  fi
  jq 'del(.detectionSummary.method)' "$manifest" > "$bad"
  if run_validate "$bad" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性: detectionSummary.method欠落を受け入れた" >&2; rc=1
  else
    echo "  [PASS] 陰性: detectionSummary.method欠落でFAIL"
  fi
  jq 'del(.strategy.unitIdRegex)' "$manifest" > "$bad"
  if run_validate "$bad" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性: strategy.unitIdRegex欠落を受け入れた" >&2; rc=1
  else
    echo "  [PASS] 陰性: strategy.unitIdRegex欠落でFAIL"
  fi
  jq '.strategy.unitIdRegex = 1' "$manifest" > "$bad"
  if run_validate "$bad" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性: strategy.unitIdRegex数値を受け入れた" >&2; rc=1
  else
    echo "  [PASS] 陰性: strategy.unitIdRegex数値でFAIL"
  fi
  jq '.strategy.approvedByUser = true' "$manifest" > "$bad"
  if run_validate "$bad" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性: approvedByUser=trueを受け入れた" >&2; rc=1
  else
    echo "  [PASS] 陰性: approvedByUser=trueでFAIL"
  fi
  jq '.detectionSummary.unitCount = "1" | .detectionSummary.unresolvedCount = -1' "$manifest" > "$bad"
  if run_validate "$bad" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性: detectionSummary集計値の不正型・負数を受け入れた" >&2; rc=1
  else
    echo "  [PASS] 陰性: detectionSummary集計値の不正型・負数でFAIL"
  fi
  [ "$rc" -eq 0 ] && echo "self-test 全項目 PASS" || echo "self-test FAIL" >&2
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit $?; fi
if [ "$#" -lt 1 ] || [ ! -f "$1" ]; then echo "Usage: $0 <manifest.json>" >&2; exit 1; fi
run_validate "$1"
