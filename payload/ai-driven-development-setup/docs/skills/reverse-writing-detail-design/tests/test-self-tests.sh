#!/usr/bin/env bash
set -u

# test-self-tests.sh — check-detail-design.sh --self-test を実行し、合否を報告する。
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
    sed -n '1,80p' "$out"
    FAIL=$((FAIL + 1))
  fi
  rm -f "$out"
}

run_one "check-detail-design.sh" "${SCRIPTS_DIR}/check-detail-design.sh"

check_extract_body_h1_parity() {
  local detail_script="${SCRIPTS_DIR}/check-detail-design.sh"
  local basic_script="${SCRIPT_DIR}/../../reverse-writing-basic-design/scripts/check-basic-design.sh"
  TOTAL=$((TOTAL + 1))
  local detail_out="${TMPDIR:-/tmp}/test-self-tests-detail-body.$$"
  local basic_out="${TMPDIR:-/tmp}/test-self-tests-basic-body.$$"
  sed -n '/^extract_body_h1()/,/^}$/p' "$detail_script" > "$detail_out"
  sed -n '/^extract_body_h1()/,/^}$/p' "$basic_script" > "$basic_out"
  if [ "$(tail -n 1 "$detail_out")" != "}" ] || [ "$(tail -n 1 "$basic_out")" != "}" ]; then
    echo "FAIL: extract_body_h1-同一性（関数の終端（\`}\`だけの行）が見つかりません）"
    FAIL=$((FAIL + 1))
  elif [ "$(wc -l < "$detail_out")" -lt 3 ] || [ "$(wc -l < "$basic_out")" -lt 3 ]; then
    echo "FAIL: extract_body_h1-同一性（片方または両方の関数定義が見つかりません）"
    FAIL=$((FAIL + 1))
  elif diff "$detail_out" "$basic_out" > /dev/null 2>&1; then
    echo "PASS: extract_body_h1-同一性"
  else
    echo "FAIL: extract_body_h1-同一性（check-detail-design.shとcheck-basic-design.shの関数本体が一致しません）"
    FAIL=$((FAIL + 1))
  fi
  rm -f "$detail_out" "$basic_out"
}

check_extract_body_h1_parity

echo "実行 ${TOTAL} 件 / 失敗 ${FAIL} 件"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
