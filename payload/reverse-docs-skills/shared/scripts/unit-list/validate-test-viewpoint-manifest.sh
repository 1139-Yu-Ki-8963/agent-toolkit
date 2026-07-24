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
  for key in unitKey screenKey testType category viewpoint; do
    local missing
    missing=$(jq --arg k "$key" '[.units[]? | select(has($k) | not)] | length' "$manifest" 2>/dev/null || echo 0)
    if [ "$missing" -gt 0 ]; then
      echo "    $missing units missing key: $key" >&2
      item_ok=1
    fi
  done
  report "schema-ユニット必須" "$item_ok"

  # 4. 重複-unitKey
  local dup_ok=0
  local total_keys unique_keys
  total_keys=$(jq '[.units[]?.unitKey] | length' "$manifest" 2>/dev/null || echo 0)
  unique_keys=$(jq '[.units[]?.unitKey] | unique | length' "$manifest" 2>/dev/null || echo 0)
  if [ "$total_keys" != "$unique_keys" ]; then
    echo "    duplicate unitKey detected: total=$total_keys unique=$unique_keys" >&2
    dup_ok=1
  fi
  report "重複-unitKey" "$dup_ok"

  # 5. summary-一致
  local sum_ok=0
  local declared_total actual_total
  declared_total=$(jq '.summary.totalCount // -1' "$manifest" 2>/dev/null || echo -1)
  actual_total=$(jq '.units | length' "$manifest" 2>/dev/null || echo 0)
  if [ "$declared_total" != "$actual_total" ]; then
    echo "    totalCount mismatch: declared=$declared_total actual=$actual_total" >&2
    sum_ok=1
  fi
  report "summary-一致" "$sum_ok"

  echo "=== $((5 - fail_count))/5 PASS, ${fail_count}/5 FAIL ==="
  [ "$fail_count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 自己テスト
# ---------------------------------------------------------------------------
self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-test-viewpoint-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  local rc=0

  local pass_fixture="$tmp/pass.json"
  cat > "$pass_fixture" <<'JSON'
{"unitKind":"test_viewpoint","generatedAt":"2026-01-01","units":[{"unitKey":"login-submit-1","screenKey":"screen-login","testType":"unit","category":"境界値","viewpoint":"金額下限"},{"unitKey":"login-empty-2","screenKey":"screen-login","testType":"unit","category":"異常系","viewpoint":"空入力"}],"summary":{"totalCount":2}}
JSON

  if run_validate "$pass_fixture" >/dev/null 2>&1; then
    echo "  [PASS] 陽性: 正当なtest_viewpointマニフェストで全5項目PASS"
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
  jq '.unitKind = "screen"' "$pass_fixture" > "$bad_kind"
  if run_validate "$bad_kind" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性(unitKind不一致): unitKind不一致なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] 陰性(unitKind不一致): unitKind不一致でFAIL"
  fi

  local missing_unit_key="$tmp/missing-unit-key.json"
  jq '.units[0] |= del(.viewpoint)' "$pass_fixture" > "$missing_unit_key"
  if run_validate "$missing_unit_key" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性(ユニットキー欠落): viewpoint欠落なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] 陰性(ユニットキー欠落): viewpoint欠落でFAIL"
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
