#!/usr/bin/env bash
set -u

# test-self-tests.sh — reverse-proposing-rules の検収（acceptance）
#
# 目的:
#   check-rule-proposals.sh の --self-test を回す薄い入口。
#
# 使い方:
#   bash test-self-tests.sh
#
# 終了コード:
#   0 = 全件合格
#   1 = 1件以上不合格
#
# 保守責任者: 人手（ユーザー）。check-rule-proposals.sh のケースを増減する
#   場合は本ファイルは変えず、スクリプト側と単体テスト設計書の件数を直す。
#
# 廃棄条件: reverse-proposing-rules自体を廃止した時。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

bash "${SKILL_DIR}/scripts/check-rule-proposals.sh" --self-test
exit $?
