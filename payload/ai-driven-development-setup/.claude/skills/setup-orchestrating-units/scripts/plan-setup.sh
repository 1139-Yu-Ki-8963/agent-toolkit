#!/usr/bin/env bash
set -u

# plan-setup.sh — 共有部品 reverse-shared/scripts/plan-units.sh を呼ぶ入口
#
# 目的:
#   実行順の計画を組み立てる処理の実体は reverse-shared/scripts/plan-units.sh
#   にある（setup単位・reverse単位で共有する）。setup の統括はこの入口から
#   呼ぶ。引数はそのまま渡す（--self-testも含む）。
#
# 使い方:
#   plan-setup.sh <リポジトリのルート> [--units a,b,c] [--target <対象リポジトリのルート>] [--format table|steps|both] [--until <機能名>]
#   plan-setup.sh --self-test
#
# 終了コード:
#   2 = reverse-shared/scripts/plan-units.sh が見当たらない
#   それ以外は共有部品の終了コードをそのまま返す
#
# 保守責任者: 人手（ユーザー）。実装を変える場合は
#   docs/skills/reverse-shared/scripts/plan-units.sh を直す（本ファイルは入口のみ）。
#
# 廃棄条件: 共有部品への委譲方式を別の仕組みに変えた時。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_SCRIPT="${SCRIPT_DIR}/../../reverse-shared/scripts/plan-units.sh"

if [ ! -f "$SHARED_SCRIPT" ]; then
  echo "ERROR: 共有部品が見当たらない: ${SHARED_SCRIPT}（docs/skills/reverse-shared が未配置の可能性）" >&2
  exit 2
fi

exec bash "$SHARED_SCRIPT" "$@"
