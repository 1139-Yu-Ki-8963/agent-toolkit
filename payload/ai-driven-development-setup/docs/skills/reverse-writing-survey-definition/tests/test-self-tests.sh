#!/usr/bin/env bash
set -u

# test-self-tests.sh — check-survey-definition.sh と check-design-docs.sh の --self-test を実行し、合否を報告する。
# set -e は使わない。失敗しても最後まで実行し、失敗本数を数えるためである。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/../scripts"

FAIL=0
TOTAL=0

run_one() {
  local name="$1" path="$2"
  TOTAL=$((TOTAL + 1))
  local out="${TMPDIR:-/tmp}/test-self-tests-out.$$"
  if bash "$path" --self-test > "$out" 2>&1; then
    echo "PASS: ${name} --self-test"
  else
    local code=$?
    echo "FAIL: ${name} --self-test (終了コード ${code})"
    sed -n '1,40p' "$out"
    FAIL=$((FAIL + 1))
  fi
  rm -f "$out"
}

run_one "check-survey-definition.sh" "${SCRIPTS_DIR}/check-survey-definition.sh"
run_one "check-design-docs.sh" "${SCRIPTS_DIR}/check-design-docs.sh"

echo "実行 ${TOTAL} 件 / 失敗 ${FAIL} 件"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
