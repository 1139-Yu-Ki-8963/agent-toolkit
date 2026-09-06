#!/usr/bin/env bash
set -u

# test-self-tests.sh — 3本のスクリプトと、規約の置き場にある検査
# （docs/rules/*/*/check-*.sh）の --self-test を順に実行し、合否を報告する。
# set -e は使わない。失敗しても最後まで実行し、失敗本数を数えるためである。
#
# 規約の置き場の検査を含める理由（第1回改善指示書1-26）:
#   名前の決まり（check-skill-naming.sh）のように docs/rules/ 配下に自己
#   テストを持つ検査は、docs/skills/*/tests/ の一覧に登録されないため、
#   ここから呼ばない限り機能の自己テストの走行に含まれない。*.test.sh は
#   対象の checker へ --self-test を渡すだけの薄い入口であり、二重実行に
#   なるため対象から外す。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/../scripts"
RULES_ROOT="${SCRIPT_DIR}/../../../rules"

FAIL=0
TOTAL=0

run_one() {
  local name="$1" path="$2"
  TOTAL=$((TOTAL + 1))
  if bash "$path" --self-test > ${TMPDIR:-/tmp}/test-self-tests-out.$$ 2>&1; then
    echo "PASS: ${name} --self-test"
  else
    local code=$?
    echo "FAIL: ${name} --self-test (終了コード ${code})"
    sed -n '1,20p' ${TMPDIR:-/tmp}/test-self-tests-out.$$
    FAIL=$((FAIL + 1))
  fi
  rm -f ${TMPDIR:-/tmp}/test-self-tests-out.$$
}

run_one "validate-skill-definitions.sh" "${SCRIPTS_DIR}/validate-skill-definitions.sh"
run_one "build-derived-skills.sh" "${SCRIPTS_DIR}/build-derived-skills.sh"
run_one "check-skill-drift.sh" "${SCRIPTS_DIR}/check-skill-drift.sh"

if [ -d "$RULES_ROOT" ]; then
  one_checker=""
  while IFS= read -r one_checker; do
    [ -n "$one_checker" ] || continue
    run_one "$(basename "$one_checker")" "$one_checker"
  done <<RULE_CHECKER_LIST
$(find "$RULES_ROOT" -type f -name 'check-*.sh' ! -name '*.test.sh' | sort)
RULE_CHECKER_LIST
fi

echo "実行 ${TOTAL} 件 / 失敗 ${FAIL} 件"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
