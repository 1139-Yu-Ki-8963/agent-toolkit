#!/usr/bin/env bash
set -u

# test-self-tests.sh — reverse-extracting-code-readings の検収（acceptance）
#
# 目的:
#   scripts/extract-code-readings.sh・scripts/compare-code-readings.sh の --self-test を
#   回し、読み取り結果を取り出す機能の完了条件（同じコードから2回取り出して
#   一致する・機械で0件だった項目とAIの読み取りの項目が未に載る 等）を
#   自己完結で確かめる。
#
# 使い方:
#   bash test-self-tests.sh
#
# 終了コード:
#   0 = 全件合格
#   1 = 1件以上不合格
#
# 保守責任者: 人手（ユーザー）。scripts/ に新しいスクリプトを足すときは
#   本ファイルにも run_case を足す。
#
# 廃棄条件: reverse-extracting-code-readings自体を廃止した時。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

run_case "extract-code-readings.sh --self-test" bash "${SKILL_DIR}/scripts/extract-code-readings.sh" --self-test
run_case "compare-code-readings.sh --self-test" bash "${SKILL_DIR}/scripts/compare-code-readings.sh" --self-test

echo "実行 ${total} 件 / 失敗 ${fail} 件"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
