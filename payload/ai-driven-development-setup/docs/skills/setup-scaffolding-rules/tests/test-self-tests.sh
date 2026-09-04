#!/usr/bin/env bash
set -u

# test-self-tests.sh — scaffold-rule-definitions.sh --self-test と、
#   templates/rules/tool-defined/<親>/<子>/*.test.sh の全件を実行し、合否を報告する。
# set -e は使わない。失敗しても最後まで実行し、失敗本数を数えるためである。
#
# 規約1件=フォルダ1つ（rule.md + checker + checker.test.sh）の1対1配置
#   （体系の再設計.md「決定事項」）に伴い、checkerのテストは規約フォルダの
#   直下に置かれる。旧来の単一集約フォルダ（templates/rules/checkers/）は
#   廃止済みのため、tool-defined配下を再帰的に探索する。
#
# *.test.sh は旧リポジトリ（reverse-docs-skills）の置き場
#   （delivery-payload/references/ 等）を前提にした自己テストを含む場合がある。
#   その場合はここで失敗として数え、隠さない
#   （記録: docs/design/体系の再設計.md「実践で見つかった欠点と不具合」）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/../scripts"
TOOLDEFINED_DIR="${SCRIPT_DIR}/../templates/rules/tool-defined"

FAIL=0
TOTAL=0
FAILED_NAMES=""

run_one() {
  local name="$1" path="$2"
  TOTAL=$((TOTAL + 1))
  if bash "$path" --self-test > "${TMPDIR:-/tmp}/test-self-tests-out.$$" 2>&1; then
    echo "PASS: ${name} --self-test"
  else
    local code=$?
    echo "FAIL: ${name} --self-test (終了コード ${code})"
    sed -n '1,20p' "${TMPDIR:-/tmp}/test-self-tests-out.$$"
    FAIL=$((FAIL + 1))
    FAILED_NAMES="${FAILED_NAMES}${name}"$'\n'
  fi
  rm -f "${TMPDIR:-/tmp}/test-self-tests-out.$$"
}

run_one "scaffold-rule-definitions.sh" "${SCRIPTS_DIR}/scaffold-rule-definitions.sh"

if [ -d "$TOOLDEFINED_DIR" ]; then
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    run_one "$(basename "$t")" "$t"
  done <<INNER_EOF
$(find "$TOOLDEFINED_DIR" -type f -name '*.test.sh' | sort)
INNER_EOF
fi

echo "実行 ${TOTAL} 件 / 失敗 ${FAIL} 件"
if [ -n "$FAILED_NAMES" ]; then
  echo "失敗一覧:"
  printf '%s' "$FAILED_NAMES" | sed 's/^/  - /'
fi

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
