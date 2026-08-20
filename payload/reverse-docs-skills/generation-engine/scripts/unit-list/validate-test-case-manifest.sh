#!/usr/bin/env bash
# validate-test-case-manifest.sh — test_case スキーマ専用の整合検証器
# テストケース一覧（unitKind=test_case の出力）を検証する。
# 検出系の validate-manifest.sh とはスキーマ契約が異なるため専用化。
#
# Usage: validate-test-case-manifest.sh <manifest.json>
#        validate-test-case-manifest.sh --self-test
set -euo pipefail

REQUIRED_UNIT_KEYS="unitKey screenKey testType unitNameGuess kind caseKey viewpointKey input steps expected"

# ---------------------------------------------------------------------------
# 検証本体
# ---------------------------------------------------------------------------
run_validate() {
  local manifest="$1"
  local fail_count=0

  report() {
    local name="$1" status="$2"
    if [ "$status" -eq 0 ]; then
      printf '  [PASS] %s\n' "$name"
    else
      printf '  [FAIL] %s\n' "$name"
      fail_count=$((fail_count + 1))
    fi
  }

  echo "=== validate-test-case-manifest ==="

  # 1. schema-トップレベル必須
  local top_ok=0
  for key in unitKind generatedAt units summary; do
    if ! jq -e "has(\"$key\")" "$manifest" >/dev/null 2>&1; then
      echo "    missing top-level key: $key" >&2
      top_ok=1
    fi
  done
  if ! jq -e '(.generatedAt | type) == "string" and (.generatedAt | length) > 0 and (.units | type) == "array" and (.summary | type) == "object"' "$manifest" >/dev/null 2>&1; then
    echo "    generatedAt must be a non-empty string; units must be an array; summary must be an object" >&2
    top_ok=1
  fi
  report "schema-トップレベル必須" "$top_ok"

  # 2. unitKind-一致
  local kind_ok=0
  local kind
  kind=$(jq -r '.unitKind // empty' "$manifest" 2>/dev/null || echo "")
  if [ "$kind" != "test_case" ]; then
    echo "    unitKind mismatch: expected=test_case actual=${kind:-<missing>}" >&2
    kind_ok=1
  fi
  report "unitKind-一致" "$kind_ok"

  # 3. schema-ユニット必須
  local item_ok=0
  for key in $REQUIRED_UNIT_KEYS; do
    local missing
    missing=$(jq --arg k "$key" '[.units[]? | select(has($k) | not)] | length' "$manifest" 2>/dev/null || echo 0)
    if [ "$missing" -gt 0 ]; then
      echo "    $missing units missing key: $key" >&2
      item_ok=1
    fi
  done
  if ! jq -e '[.units[]? | select(
    (.unitKey | type) != "string"
    or (.screenKey | type) != "string"
    or (.testType | type) != "string"
    or (.unitNameGuess | type) != "string"
    or (.kind | type) != "string"
    or (.caseKey | type) != "string"
    or (.viewpointKey | type) != "string"
    or (.input | type) != "string"
    or (.steps | type) != "string"
    or (.expected | type) != "string"
  )] | length == 0' "$manifest" >/dev/null 2>&1; then
    echo "    unit fields must all be strings" >&2
    item_ok=1
  fi
  report "schema-ユニット必須" "$item_ok"

  # 4. testType-許容値
  local type_ok=0
  if ! jq -e '[.units[]? | select((.testType == "unit" or .testType == "integration" or .testType == "scenario") | not)] | length == 0' "$manifest" >/dev/null 2>&1; then
    echo "    testType must be one of unit/integration/scenario" >&2
    type_ok=1
  fi
  report "testType-許容値" "$type_ok"

  # 5. 重複-unitKey
  local dup_ok=0
  local total_keys unique_keys
  total_keys=$(jq '[.units[]?.unitKey] | length' "$manifest" 2>/dev/null || echo 0)
  unique_keys=$(jq '[.units[]?.unitKey] | unique | length' "$manifest" 2>/dev/null || echo 0)
  if [ "$total_keys" != "$unique_keys" ]; then
    echo "    duplicate unitKey detected: total=$total_keys unique=$unique_keys" >&2
    dup_ok=1
  fi
  report "重複-unitKey" "$dup_ok"

  # 6. summary-一致
  local sum_ok=0
  local declared_total actual_total declared_by_test_type actual_by_test_type declared_by_screen actual_by_screen
  declared_total=$(jq '.summary.totalCount // -1' "$manifest" 2>/dev/null || echo -1)
  actual_total=$(jq '.units | length' "$manifest" 2>/dev/null || echo 0)
  # byTestType は3種固定キー(unit/integration/scenario)で0件も出力する契約(aggregate-test-cases.sh)。
  # 検出0件のキー省略も許容するため、両辺とも0デフォルトで補完してから比較する。
  declared_by_test_type=$(jq -cS '{unit: 0, integration: 0, scenario: 0} + (.summary.byTestType // {})' "$manifest" 2>/dev/null || echo null)
  actual_by_test_type=$(jq -cS '{unit: 0, integration: 0, scenario: 0} + ([.units[]?] | group_by(.testType) | map({key: .[0].testType, value: length}) | from_entries)' "$manifest" 2>/dev/null || echo '{}')
  declared_by_screen=$(jq -cS '.summary.byScreen // null' "$manifest" 2>/dev/null || echo null)
  actual_by_screen=$(jq -cS '[.units[]?] | group_by(.screenKey) | map({key: .[0].screenKey, value: length}) | from_entries' "$manifest" 2>/dev/null || echo '{}')
  if ! jq -e '
    (.summary.totalCount | type) == "number"
    and (.summary.totalCount | floor) == .summary.totalCount
    and .summary.totalCount >= 0
    and (.summary.byTestType | type) == "object"
    and all(.summary.byTestType[]?; (type == "number") and (floor == .) and . >= 0)
    and (.summary.byScreen | type) == "object"
    and all(.summary.byScreen[]?; (type == "number") and (floor == .) and . >= 0)
  ' "$manifest" >/dev/null 2>&1; then
    echo "    summary must declare non-negative integer totalCount/byTestType/byScreen" >&2
    sum_ok=1
  fi
  if [ "$declared_total" != "$actual_total" ] || [ "$declared_by_test_type" != "$actual_by_test_type" ] || [ "$declared_by_screen" != "$actual_by_screen" ]; then
    echo "    summary mismatch: total=$declared_total/$actual_total byTestType=$declared_by_test_type/$actual_by_test_type byScreen=$declared_by_screen/$actual_by_screen" >&2
    sum_ok=1
  fi
  report "summary-一致" "$sum_ok"

  echo "=== $((6 - fail_count))/6 PASS, ${fail_count}/6 FAIL ==="
  [ "$fail_count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 自己テスト
# ---------------------------------------------------------------------------
self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-test-case-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  local rc=0

  local pass_fixture="$tmp/pass.json"
  cat > "$pass_fixture" <<'JSON'
{"unitKind":"test_case","generatedAt":"2026-01-01T00:00:00Z","units":[{"unitKey":"screen-login-unit-1","screenKey":"screen-login","testType":"unit","unitNameGuess":"合計0円-登録不可","kind":"unit","caseKey":"合計0円-登録不可","viewpointKey":"金額-下限境界","input":"total: 0","steps":"","expected":"isRegisterableがfalseを返す"},{"unitKey":"screen-login-integration-1","screenKey":"screen-login","testType":"integration","unitNameGuess":"登録実行-一覧反映","kind":"integration","caseKey":"登録実行-一覧反映","viewpointKey":"登録-一覧反映","input":"必須項目入力済み","steps":"登録ボタンを押す","expected":"一覧に新規行が追加される"}],"summary":{"totalCount":2,"byTestType":{"unit":1,"integration":1},"byScreen":{"screen-login":2}}}
JSON

  if run_validate "$pass_fixture" >/dev/null 2>&1; then
    echo "  [PASS] 陽性: 正当なtest_caseマニフェストで全6項目PASS"
  else
    echo "  [FAIL] 陽性: 正当なマニフェストがFAILした" >&2
    rc=1
  fi

  local missing_top="$tmp/missing-top.json"
  jq 'del(.summary)' "$pass_fixture" > "$missing_top"
  if run_validate "$missing_top" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性(トップレベル欠落): summary欠落なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] 陰性(トップレベル欠落): summary欠落でFAIL"
  fi

  local bad_kind="$tmp/bad-kind.json"
  jq '.unitKind = "test_viewpoint"' "$pass_fixture" > "$bad_kind"
  if run_validate "$bad_kind" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性(unitKind不一致): unitKind不一致なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] 陰性(unitKind不一致): unitKind不一致でFAIL"
  fi

  local required_key bad_unit_missing
  for required_key in $REQUIRED_UNIT_KEYS; do
    bad_unit_missing="$tmp/missing-${required_key}.json"
    jq --arg k "$required_key" '.units[0] |= del(.[$k])' "$pass_fixture" > "$bad_unit_missing"
    if run_validate "$bad_unit_missing" >/dev/null 2>&1; then
      echo "  [FAIL] 陰性(ユニットキー欠落): ${required_key}欠落なのにPASSした" >&2
      rc=1
    else
      echo "  [PASS] 陰性(ユニットキー欠落): ${required_key}欠落でFAIL"
    fi
  done

  local bad_type_value="$tmp/bad-type-value.json"
  jq '.units[0].testType = "manual"' "$pass_fixture" > "$bad_type_value"
  if run_validate "$bad_type_value" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性(testType許容値): 未知のtestTypeなのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] 陰性(testType許容値): 未知のtestTypeでFAIL"
  fi

  local dup_key="$tmp/dup-key.json"
  jq '.units[1].unitKey = .units[0].unitKey' "$pass_fixture" > "$dup_key"
  if run_validate "$dup_key" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性(unitKey重複): unitKey重複なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] 陰性(unitKey重複): unitKey重複でFAIL"
  fi

  local bad_sum="$tmp/bad-sum.json"
  jq '.summary.totalCount = 99' "$pass_fixture" > "$bad_sum"
  if run_validate "$bad_sum" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性(summary不一致): totalCount不一致なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] 陰性(summary不一致): totalCount不一致でFAIL"
  fi

  local bad_generated_at="$tmp/bad-generated-at.json"
  jq '.generatedAt = null' "$pass_fixture" > "$bad_generated_at"
  if run_validate "$bad_generated_at" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性(generatedAt型): generatedAt=nullなのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] 陰性(generatedAt型): generatedAt=nullでFAIL"
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <manifest.json>" >&2
  exit 1
fi

MANIFEST="$1"
if [ ! -f "$MANIFEST" ]; then
  echo "Error: manifest not found: $MANIFEST" >&2
  exit 1
fi

run_validate "$MANIFEST"
