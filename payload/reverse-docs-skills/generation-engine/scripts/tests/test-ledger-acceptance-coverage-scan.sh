#!/usr/bin/env bash
# test-ledger-acceptance-coverage-scan.sh — docs/scripts/check-ledger-acceptance-coverage.sh の実データ走査
# （引数なしモード）を第1層の機械検証から拾えるようにする入口。
#
# 背景（2026-08-28実測）: 第1層の機械検証は自己テストの分岐を持つ .sh を
# 集めるが、集めた対象は常にその分岐を通して実行する。本体
# （docs/scripts/check-ledger-acceptance-coverage.sh）は引数なしで実データを走査する本番
# 経路を持つが、集約からは一度も実データの走査が行われていなかった
# （generation-engine/scripts/tests/check-commit-issue-trace.sh と同型の
# 欠落。詳細は同ファイルの設計判断を参照）。
#
# 本ファイルは自己テストの分岐ラベルを含まない。list_targets の名前ベース
# 収集（test- で始まる .sh を探す）に拾わせるため test- で始まる名前にして
# いる。集約側は本ファイルに自己テストの分岐ラベルが無いことを確認した
# うえで、引数なしで実行する。
#
# 使い方: bash test-ledger-acceptance-coverage-scan.sh
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TARGET="${REPO_ROOT}/docs/scripts/check-ledger-acceptance-coverage.sh"
. "${SCRIPT_DIR}/lib/docs-script-scan.sh"

if [ $# -gt 0 ]; then
  echo "usage: $0" >&2
  exit 2
fi

run_docs_script_scan "${TARGET}" "check-ledger-acceptance-coverage.sh"
exit $?
