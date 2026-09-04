#!/usr/bin/env bash
set -u

# test-self-tests.sh — reverse-shared の検収（acceptance）
#
# 目的:
#   reverse-shared は名前の決まり（skill-naming）によりSKILL.mdを持たない
#   共有部品であり、検収は本tests/が担う。read-run.sh・check-entry.sh・
#   unit-dir-name.sh・units-status.sh・list-units-of.sh・start-run.sh・
#   plan-units.sh・check-basic-phase.sh・record-acceptance.sh・
#   check-acceptance-record.shの--self-testを回すことに加え、references/の複製が
#   docs/design/common/の定義と一致していること（複製のずれ防止）を確かめる。
#   setupの原本（写しの元）が無い環境、およびdocs/design/common自体が無い環境では、
#   同一性の検査をSKIPにする。
#
# 使い方:
#   bash test-self-tests.sh
#
# 終了コード:
#   0 = 全件合格
#   1 = 1件以上不合格
#
# 保守責任者: 人手（ユーザー）。references/の複製元（docs/design/common/unit-kinds.json・
#   docs/design/common/output-layout.json・docs/design/common/fact-shapes.json）を変える
#   ときは、複製先とあわせて本テストも確かめる。
#
# 廃棄条件: reverse-shared自体を廃止した時。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DESIGN_DIR="${SHARED_DIR}/../../design/common"
if [ -d "$DESIGN_DIR" ]; then
  DESIGN_DIR="$(cd "$DESIGN_DIR" && pwd)"
else
  DESIGN_DIR=""
fi
SETUP_DIR="${SHARED_DIR}/../setup-scaffolding-rules/templates/rules/tool-defined"
if [ -d "$SETUP_DIR" ]; then
  SETUP_DIR="$(cd "$SETUP_DIR" && pwd)"
else
  SETUP_DIR=""
fi

total=0
fail=0

run_case() {
  local desc="$1"; shift
  total=$((total + 1))
  if "$@"; then
    echo "PASS: ${desc}"
  else
    echo "FAIL: ${desc}"
    fail=$((fail + 1))
  fi
}

cmp_ignoring_notice() {
  local expected="$1" actual="$2"
  local tmp_expected tmp_actual
  tmp_expected="$(mktemp "${TMPDIR:-/tmp}/reverse-shared-cmp.XXXXXX")"
  tmp_actual="$(mktemp "${TMPDIR:-/tmp}/reverse-shared-cmp.XXXXXX")"
  tail -n +2 "$expected" > "$tmp_expected"
  tail -n +3 "$actual" > "$tmp_actual"
  cmp -s "$tmp_expected" "$tmp_actual"
  local result=$?
  rm -f "$tmp_expected" "$tmp_actual"
  return $result
}

run_case "read-run.sh --self-test" bash "${SHARED_DIR}/scripts/read-run.sh" --self-test
run_case "design-root.sh --self-test" bash "${SHARED_DIR}/scripts/design-root.sh" --self-test
run_case "check-entry.sh --self-test" bash "${SHARED_DIR}/scripts/check-entry.sh" --self-test
run_case "unit-dir-name.sh --self-test" bash "${SHARED_DIR}/scripts/unit-dir-name.sh" --self-test
run_case "units-status.sh --self-test" bash "${SHARED_DIR}/scripts/units-status.sh" --self-test
run_case "list-units-of.sh --self-test" bash "${SHARED_DIR}/scripts/list-units-of.sh" --self-test
run_case "check-doc-heading-addendum.sh --self-test" bash "${SHARED_DIR}/scripts/check-doc-heading-addendum.sh" --self-test
run_case "check-unit-test-design-doc-sections.sh --self-test" bash "${SHARED_DIR}/scripts/check-unit-test-design-doc-sections.sh" --self-test
run_case "start-run.sh --self-test" bash "${SHARED_DIR}/scripts/start-run.sh" --self-test
run_case "plan-units.sh --self-test" bash "${SHARED_DIR}/scripts/plan-units.sh" --self-test
run_case "check-basic-phase.sh --self-test" bash "${SHARED_DIR}/scripts/check-basic-phase.sh" --self-test
run_case "record-acceptance.sh --self-test" bash "${SHARED_DIR}/scripts/record-acceptance.sh" --self-test
run_case "check-acceptance-record.sh --self-test" bash "${SHARED_DIR}/scripts/check-acceptance-record.sh" --self-test
if [ -n "$DESIGN_DIR" ]; then
  run_case "定義と複製が一致する: unit-kinds.json" cmp -s "${DESIGN_DIR}/unit-kinds.json" "${SHARED_DIR}/references/unit-kinds.json"
  run_case "定義と複製が一致する: output-layout.json" cmp -s "${DESIGN_DIR}/output-layout.json" "${SHARED_DIR}/references/output-layout.json"
  run_case "定義と複製が一致する: fact-shapes.json" cmp -s "${DESIGN_DIR}/fact-shapes.json" "${SHARED_DIR}/references/fact-shapes.json"
else
  echo "SKIP: 定義と複製が一致する: unit-kinds.json（原本のdocs/design/commonが無い）"
  echo "SKIP: 定義と複製が一致する: output-layout.json（原本のdocs/design/commonが無い）"
  echo "SKIP: 定義と複製が一致する: fact-shapes.json（原本のdocs/design/commonが無い）"
fi
if [ -n "$SETUP_DIR" ] && [ -f "${SETUP_DIR}/documentation-standards/document-writing/check-doc-heading-addendum.sh" ]; then
  run_case "写しが原本と一致する: check-doc-heading-addendum.sh" cmp_ignoring_notice "${SETUP_DIR}/documentation-standards/document-writing/check-doc-heading-addendum.sh" "${SHARED_DIR}/scripts/check-doc-heading-addendum.sh"
else
  echo "SKIP: 写しが原本と一致する: check-doc-heading-addendum.sh（原本が無い）"
fi
if [ -n "$SETUP_DIR" ] && [ -f "${SETUP_DIR}/quality-assurance/test-policy/check-unit-test-design-doc-sections.sh" ]; then
  run_case "写しが原本と一致する: check-unit-test-design-doc-sections.sh" cmp_ignoring_notice "${SETUP_DIR}/quality-assurance/test-policy/check-unit-test-design-doc-sections.sh" "${SHARED_DIR}/scripts/check-unit-test-design-doc-sections.sh"
else
  echo "SKIP: 写しが原本と一致する: check-unit-test-design-doc-sections.sh（原本が無い）"
fi

echo "実行 ${total} 件 / 失敗 ${fail} 件"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
