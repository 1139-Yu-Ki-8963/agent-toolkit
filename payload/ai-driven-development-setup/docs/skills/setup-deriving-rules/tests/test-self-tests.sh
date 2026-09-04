#!/usr/bin/env bash
set -u

# test-self-tests.sh — 4本のスクリプトの --self-test を順に実行し、合否を報告する。
# set -e は使わない。失敗しても最後まで実行し、失敗本数を数えるためである。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/../scripts"

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

run_one "build-derived-rules.sh" "${SCRIPTS_DIR}/build-derived-rules.sh"
run_one "validate-rule-definitions.sh" "${SCRIPTS_DIR}/validate-rule-definitions.sh"
run_one "check-rule-drift.sh" "${SCRIPTS_DIR}/check-rule-drift.sh"
run_one "resolve-applicable-rules.sh" "${SCRIPTS_DIR}/resolve-applicable-rules.sh"

echo "実行 ${TOTAL} 件 / 失敗 ${FAIL} 件"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
