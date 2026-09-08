#!/usr/bin/env bash
set -u

# test-self-tests.sh — reverse-orchestrating-flow が持つ2本のスクリプト
# （plan-reverse.sh・build-completion-report.sh）の --self-test を両方とも
# 実行する。
#
# 経緯:
#   従来はexecでplan-reverse.shだけを走らせており、build-completion-report.shの
#   自己テストが検収（check-acceptance.sh）に一切反映されていなかった
#   （第1回改善指示書1-46・判定役の指摘）。それぞれの出力（[PASS]/[FAIL]の
#   各ケースと合計行）をそのまま連結して出し、いずれかが不合格なら
#   終了コード1にする。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN_SCRIPT="${SCRIPT_DIR}/../scripts/plan-reverse.sh"
COMPLETION_SCRIPT="${SCRIPT_DIR}/../scripts/build-completion-report.sh"

exit_code=0

bash "$PLAN_SCRIPT" --self-test
plan_exit=$?
[ "$plan_exit" -eq 0 ] || exit_code=1

bash "$COMPLETION_SCRIPT" --self-test
completion_exit=$?
[ "$completion_exit" -eq 0 ] || exit_code=1

exit "$exit_code"
