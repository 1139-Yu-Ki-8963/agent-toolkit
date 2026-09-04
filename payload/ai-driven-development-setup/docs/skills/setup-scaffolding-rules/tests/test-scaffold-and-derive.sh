#!/usr/bin/env bash
set -u

# test-scaffold-and-derive.sh — 空の対象へ「配置（scaffold-rule-definitions.sh）→
#   検査（validate-rule-definitions.sh）→ 派生（build-derived-rules.sh）→
#   ずれ検査（check-rule-drift.sh）」を通し、すべて終了コード0になることを
#   確かめる連鎖テスト。setup-scaffolding-rules（規約の配置）と
#   setup-deriving-rules（検査・派生・ずれ検知）を、実際に空の対象へ順に
#   通した状態で固定する。
#
# set -e は使わない。失敗しても最後まで実行し、失敗本数を数えるためである。
#
# 使い方: bash test-scaffold-and-derive.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
D_ROOT="$(cd "${S_ROOT}/../setup-deriving-rules" && pwd)"

SCAFFOLD_SCRIPT="${S_ROOT}/scripts/scaffold-rule-definitions.sh"
VALIDATE_SCRIPT="${D_ROOT}/scripts/validate-rule-definitions.sh"
BUILD_SCRIPT="${D_ROOT}/scripts/build-derived-rules.sh"
DRIFT_SCRIPT="${D_ROOT}/scripts/check-rule-drift.sh"
TAXONOMY_JSON="${S_ROOT}/references/rule-taxonomy.json"

FAIL=0

report_pass() { echo "  [PASS] $1"; }
report_fail() {
  echo "  [FAIL] $1" >&2
  FAIL=$((FAIL + 1))
}

# 明示テンプレート付きmktemp -dを使う。裸のmktemp -dは既定領域を使うため、
# サンドボックス実行環境では失敗する（同事情はcheck-rule-drift.sh冒頭の
# コメントを参照）。
T=""
if ! T="$(mktemp -d "${TMPDIR:-/tmp}/test-scaffold-and-derive.XXXXXX" 2>/dev/null)" || [ -z "$T" ]; then
  echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi

cleanup() {
  rm -rf "$T"
}
trap cleanup EXIT

# 1. 配置: 空の対象へ32規約 + project-context を配る
scaffold_out=""
scaffold_rc=0
scaffold_out="$(bash "$SCAFFOLD_SCRIPT" "$T" --apply 2>&1)" || scaffold_rc=$?
if [ "$scaffold_rc" -eq 0 ]; then
  report_pass "scaffold-rule-definitions.sh --apply が終了コード0"
else
  report_fail "scaffold-rule-definitions.sh --apply が終了コード${scaffold_rc}"
  printf '%s\n' "$scaffold_out" | sed 's/^/    /' >&2
fi

# 2. parent.ymlが7件
parent_count="$(find "${T}/docs/rules" -name parent.yml 2>/dev/null | grep -c . || true)"
if [ "$parent_count" -eq 7 ]; then
  report_pass "parent.ymlが7件"
else
  report_fail "parent.ymlが${parent_count}件（期待7）"
fi

# 3. rule.mdが33件（32規約 + project-context）
rule_count="$(find "${T}/docs/rules" -name rule.md 2>/dev/null | grep -c . || true)"
if [ "$rule_count" -eq 33 ]; then
  report_pass "rule.mdが33件（32規約+project-context）"
else
  report_fail "rule.mdが${rule_count}件（期待33）"
fi

# 4. 検査: 配置した定義がvalidate-rule-definitions.shを通る
#    （--taxonomyを指定し、派生のスクリプト4本の除外（改善課題: 空の対象への配置で
#    見つかった不具合への対応）を実際に確かめる）
validate_out=""
validate_rc=0
validate_out="$(bash "$VALIDATE_SCRIPT" "${T}/docs/rules" --taxonomy "$TAXONOMY_JSON" 2>&1)" || validate_rc=$?
if [ "$validate_rc" -eq 0 ]; then
  report_pass "validate-rule-definitions.sh --taxonomyが終了コード0"
else
  report_fail "validate-rule-definitions.sh --taxonomyが終了コード${validate_rc}"
  printf '%s\n' "$validate_out" | sed 's/^/    /' >&2
fi

# 5. 派生: 定義から.claude/rules・.cursor/rules・AGENTS.md等を生成する
#    （build-derived-rules.shは--taxonomyを持たない引数契約のため付けない）
build_out=""
build_rc=0
build_out="$(bash "$BUILD_SCRIPT" "${T}/docs/rules" "$T" --apply 2>&1)" || build_rc=$?
if [ "$build_rc" -eq 0 ]; then
  report_pass "build-derived-rules.sh --applyが終了コード0"
else
  report_fail "build-derived-rules.sh --applyが終了コード${build_rc}"
  printf '%s\n' "$build_out" | sed 's/^/    /' >&2
fi

# 6. project-context/rule.mdがdocs/rules側の定義から派生物として生成される
#    （改善課題: check-rule-drift.shの実行でproject-context/rule.mdが
#    ADDEDとして検出される事象への対応）
pc_derived="${T}/.claude/rules/always/project-context/rule.md"
if [ -f "$pc_derived" ]; then
  first_line="$(head -1 "$pc_derived")"
  if printf '%s' "$first_line" | grep -qF '生成物'; then
    report_pass "project-context/rule.mdが派生物として生成される（生成物コメント付き）"
  else
    report_fail "project-context/rule.mdの派生物1行目に生成物コメントが無い: ${first_line}"
  fi
else
  report_fail "project-context/rule.mdの派生物が見つからない: ${pc_derived}"
fi

# 7. ずれ検査: 定義と派生物が一致している（手作業編集の痕跡が無い）
drift_out=""
drift_rc=0
drift_out="$(bash "$DRIFT_SCRIPT" "${T}/docs/rules" "$T" 2>&1)" || drift_rc=$?
if [ "$drift_rc" -eq 0 ]; then
  report_pass "check-rule-drift.shが終了コード0（ずれなし）"
else
  report_fail "check-rule-drift.shが終了コード${drift_rc}"
  printf '%s\n' "$drift_out" | sed 's/^/    /' >&2
fi

# 8. 配置された全checkerの.test.shをTの中で実行し、失敗0であることを確かめる
checker_total=0
checker_fail=0
checker_names=""
checker_names="$(find "${T}/docs/rules" -type f -name '*.test.sh' 2>/dev/null | sort)"
while IFS= read -r t; do
  [ -n "$t" ] || continue
  checker_total=$((checker_total + 1))
  checker_out=""
  checker_rc=0
  checker_out="$(bash "$t" --self-test 2>&1)" || checker_rc=$?
  if [ "$checker_rc" -ne 0 ]; then
    checker_fail=$((checker_fail + 1))
    echo "    [FAIL] $(basename "$t") --self-test (終了コード ${checker_rc})" >&2
    printf '%s\n' "$checker_out" | sed -n '1,10p' | sed 's/^/      /' >&2
  fi
done <<EOF
$checker_names
EOF
if [ "$checker_fail" -eq 0 ]; then
  report_pass "配置された全checkerの.test.sh（${checker_total}件）が失敗0で通る"
else
  report_fail "配置されたcheckerの.test.shで${checker_fail}/${checker_total}件が失敗した"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS"
  exit 0
else
  echo "FAIL（${FAIL}件の不合格）" >&2
  exit 1
fi
