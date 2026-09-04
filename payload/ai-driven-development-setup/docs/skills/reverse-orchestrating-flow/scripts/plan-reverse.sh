#!/usr/bin/env bash
set -u

# plan-reverse.sh — reverse単位に固定して共有部品 plan-units.sh を呼ぶ入口
#
# 目的:
#   reverse の統括の手順1が呼ぶ。実行順を組み立てる処理の実体は
#   reverse-shared/scripts/plan-units.sh にある（setup単位・reverse単位で
#   共有する）。本スクリプトは --units reverse を固定して渡す入口である。
#
# 使い方:
#   plan-reverse.sh <このリポジトリのルート> [--until <機能名>] [--target <対象リポジトリのルート>] [--format table|steps|both]
#   plan-reverse.sh --self-test
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

if [ "${1:-}" = "--self-test" ]; then
  if [ ! -f "$SHARED_SCRIPT" ]; then
    echo "ERROR: 共有部品が見当たらない: ${SHARED_SCRIPT}" >&2
    exit 2
  fi
  exec bash "$SHARED_SCRIPT" --self-test
fi

if [ ! -f "$SHARED_SCRIPT" ]; then
  echo "ERROR: 共有部品が見当たらない: ${SHARED_SCRIPT}（docs/skills/reverse-shared が未配置の可能性）" >&2
  exit 2
fi

if [ $# -lt 1 ]; then
  echo "usage: $(basename "$0") <このリポジトリのルート> [--until <機能名>] [--target <対象リポジトリのルート>] [--format table|steps|both]" >&2
  exit 2
fi

root="$1"; shift
exec bash "$SHARED_SCRIPT" "$root" --units reverse "$@"
