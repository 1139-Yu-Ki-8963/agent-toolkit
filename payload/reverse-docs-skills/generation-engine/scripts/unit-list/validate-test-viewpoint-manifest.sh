#!/usr/bin/env bash
# validate-test-viewpoint-manifest.sh — test_viewpoint スキーマ専用の整合検証器
# テスト観点一覧（unitKind=test_viewpoint の出力）を検証する。
# 検出系の validate-manifest.sh とはスキーマ契約が異なるため専用化。
#
# Usage: validate-test-viewpoint-manifest.sh <manifest.json>
#        validate-test-viewpoint-manifest.sh --self-test
set -euo pipefail

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

  echo "=== validate-test-viewpoint-manifest ==="

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
  if [ "$kind" != "test_viewpoint" ]; then
    echo "    unitKind mismatch: expected=test_viewpoint actual=${kind:-<missing>}" >&2
    kind_ok=1
  fi
  report "unitKind-一致" "$kind_ok"

  # 3. schema-ユニット必須
  local item_ok=0
  for key in unitKey screenKey sourceKind testType category viewpoint; do
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
    or (.sourceKind | type) != "string"
    or (.testType | type) != "string"
    or (.category | type) != "string"
    or (.viewpoint | type) != "string"
  )] | length == 0' "$manifest" >/dev/null 2>&1; then
    echo "    unitKey/screenKey/sourceKind/testType/category/viewpoint must be strings" >&2
    item_ok=1
  fi
  report "schema-ユニット必須" "$item_ok"

  # 4. sourceKind-許容値
  local source_kind_ok=0
  if ! jq -e '[.units[]? | select((.sourceKind == "screen" or .sourceKind == "api" or .sourceKind == "table" or .sourceKind == "batch" or .sourceKind == "report" or .sourceKind == "external" or .sourceKind == "feature") | not)] | length == 0' "$manifest" >/dev/null 2>&1; then
    echo "    sourceKind must be one of screen/api/table/batch/report/external/feature" >&2
    source_kind_ok=1
  fi
  report "sourceKind-許容値" "$source_kind_ok"

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
  declared_by_test_type=$(jq -cS '.summary.byTestType // null' "$manifest" 2>/dev/null || echo null)
  actual_by_test_type=$(jq -cS '[.units[]?] | group_by(.testType) | map({key: .[0].testType, value: length}) | from_entries' "$manifest" 2>/dev/null || echo '{}')
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
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-test-viewpoint-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  local rc=0

  local pass_fixture="$tmp/pass.json"
  cat > "$pass_fixture" <<'JSON'
{"unitKind":"test_viewpoint","generatedAt":"2026-01-01T00:00:00Z","units":[{"unitKey":"login-submit-1","screenKey":"screen-login","sourceKind":"screen","testType":"unit","category":"境界値","viewpoint":"金額下限"},{"unitKey":"login-empty-2","screenKey":"screen-login","sourceKind":"screen","testType":"unit","category":"異常系","viewpoint":"空入力"}],"summary":{"totalCount":2,"byTestType":{"unit":2},"byScreen":{"screen-login":2}}}
JSON

  if _gt_out3="$(run_validate "$pass_fixture" 2>&1)"; then
    echo "  [PASS] 陽性: 正当なtest_viewpointマニフェストで全6項目PASS"
  else
    echo "  [FAIL] 陽性: 正当なマニフェストがFAILした" >&2
    printf '%s\n' "$_gt_out3" | sed 's/^/    /' >&2
    rc=1
  fi

  local missing_top="$tmp/missing-top.json"
  jq 'del(.summary)' "$pass_fixture" > "$missing_top"
  if _gt_out4="$(run_validate "$missing_top" 2>&1)"; then
    echo "  [FAIL] 陰性(トップレベル欠落): summary欠落なのにPASSした" >&2
    printf '%s\n' "$_gt_out4" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 陰性(トップレベル欠落): summary欠落でFAIL"
  fi

  local bad_units_type="$tmp/bad-units-type.json"
  jq '.units = {} | .summary.totalCount = 0' "$pass_fixture" > "$bad_units_type"
  if _gt_out5="$(run_validate "$bad_units_type" 2>&1)"; then
    echo "  [FAIL] 陰性(units型): unitsがobjectなのにPASSした" >&2
    printf '%s\n' "$_gt_out5" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 陰性(units型): unitsがobjectでFAIL"
  fi

  local bad_kind="$tmp/bad-kind.json"
  jq '.unitKind = "screen"' "$pass_fixture" > "$bad_kind"
  if _gt_out6="$(run_validate "$bad_kind" 2>&1)"; then
    echo "  [FAIL] 陰性(unitKind不一致): unitKind不一致なのにPASSした" >&2
    printf '%s\n' "$_gt_out6" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 陰性(unitKind不一致): unitKind不一致でFAIL"
  fi

  local missing_unit_key="$tmp/missing-unit-key.json"
  jq '.units[0] |= del(.viewpoint)' "$pass_fixture" > "$missing_unit_key"
  if _gt_out7="$(run_validate "$missing_unit_key" 2>&1)"; then
    echo "  [FAIL] 陰性(ユニットキー欠落): viewpoint欠落なのにPASSした" >&2
    printf '%s\n' "$_gt_out7" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 陰性(ユニットキー欠落): viewpoint欠落でFAIL"
  fi

  local required_key bad_unit_type
  for required_key in unitKey screenKey sourceKind testType category viewpoint; do
    bad_unit_type="$tmp/bad-unit-type-${required_key}.json"
    jq --arg k "$required_key" '.units[0][$k] = null' "$pass_fixture" > "$bad_unit_type"
    if _gt_out8="$(run_validate "$bad_unit_type" 2>&1)"; then
      echo "  [FAIL] 陰性(ユニット値型): ${required_key}=nullなのにPASSした" >&2
      printf '%s\n' "$_gt_out8" | sed 's/^/    /' >&2
      rc=1
    else
      echo "  [PASS] 陰性(ユニット値型): ${required_key}=nullでFAIL"
    fi
  done

  local bad_source_kind="$tmp/bad-source-kind.json"
  jq '.units[0].sourceKind = "unknown"' "$pass_fixture" > "$bad_source_kind"
  if _gt_out_source_kind="$(run_validate "$bad_source_kind" 2>&1)"; then
    echo "  [FAIL] 陰性(sourceKind許容値): 未知のsourceKindなのにPASSした" >&2
    printf '%s\n' "$_gt_out_source_kind" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 陰性(sourceKind許容値): 未知のsourceKindでFAIL"
  fi

  local dup_key="$tmp/dup-key.json"
  jq '.units[1].unitKey = .units[0].unitKey' "$pass_fixture" > "$dup_key"
  if _gt_out9="$(run_validate "$dup_key" 2>&1)"; then
    echo "  [FAIL] 陰性(unitKey重複): unitKey重複なのにPASSした" >&2
    printf '%s\n' "$_gt_out9" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 陰性(unitKey重複): unitKey重複でFAIL"
  fi

  local bad_sum="$tmp/bad-sum.json"
  jq '.summary.totalCount = 99' "$pass_fixture" > "$bad_sum"
  if _gt_out10="$(run_validate "$bad_sum" 2>&1)"; then
    echo "  [FAIL] 陰性(summary不一致): totalCount不一致なのにPASSした" >&2
    printf '%s\n' "$_gt_out10" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 陰性(summary不一致): totalCount不一致でFAIL"
  fi

  local bad_sum_type="$tmp/bad-sum-type.json"
  jq '.summary.totalCount = "2"' "$pass_fixture" > "$bad_sum_type"
  if _gt_out11="$(run_validate "$bad_sum_type" 2>&1)"; then
    echo "  [FAIL] 陰性(summary型): totalCountが文字列なのにPASSした" >&2
    printf '%s\n' "$_gt_out11" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 陰性(summary型): totalCountが文字列でFAIL"
  fi

  local bad_generated_at="$tmp/bad-generated-at.json"
  jq '.generatedAt = null' "$pass_fixture" > "$bad_generated_at"
  if _gt_out12="$(run_validate "$bad_generated_at" 2>&1)"; then
    echo "  [FAIL] 陰性(generatedAt型): generatedAt=nullなのにPASSした" >&2
    printf '%s\n' "$_gt_out12" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 陰性(generatedAt型): generatedAt=nullでFAIL"
  fi

  local bad_aggregates="$tmp/bad-aggregates.json"
  jq '.summary.byTestType = [] | .summary.byScreen = "broken"' "$pass_fixture" > "$bad_aggregates"
  if _gt_out13="$(run_validate "$bad_aggregates" 2>&1)"; then
    echo "  [FAIL] 陰性(summary集計型): byTestType/byScreen不正型なのにPASSした" >&2
    printf '%s\n' "$_gt_out13" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 陰性(summary集計型): byTestType/byScreen不正型でFAIL"
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
