#!/usr/bin/env bash
set -u

# start-run.sh — 共有部品 reverse-shared/scripts/start-run.sh を呼ぶ入口
#
# 目的:
#   実行フォルダを作る処理の実体は reverse-shared/scripts/start-run.sh に
#   ある（setup単位・reverse単位で共有する）。setup の統括はこの3行の
#   入口から呼ぶ。引数はそのまま渡す。
#
# 使い方:
#   start-run.sh <対象リポジトリのルート> --project-name <対象プロジェクト名> --output-root <出力の置き場の親> \
#     [--units <単位をカンマ区切り>] [--scope <出力の範囲>] [--deploy-to <対象プロジェクトのフォルダのルート>]
#   start-run.sh --self-test
#
# 終了コード:
#   2 = reverse-shared/scripts/start-run.sh が見当たらない
#   それ以外は共有部品の終了コードをそのまま返す
#
# 保守責任者: 人手（ユーザー）。実装を変える場合は
#   docs/skills/reverse-shared/scripts/start-run.sh を直す（本ファイルは入口のみ）。
#
# 廃棄条件: 共有部品への委譲方式を別の仕組みに変えた時。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_SCRIPT="${SCRIPT_DIR}/../../reverse-shared/scripts/start-run.sh"

if [ ! -f "$SHARED_SCRIPT" ]; then
  echo "ERROR: 共有部品が見当たらない: ${SHARED_SCRIPT}（docs/skills/reverse-shared が未配置の可能性）" >&2
  exit 2
fi

exec bash "$SHARED_SCRIPT" "$@"
