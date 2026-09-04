#!/usr/bin/env bash
set -euo pipefail

# check-skill-design-docs.test.sh — check-skill-design-docs.sh の回帰テスト用の薄い入口。
#
# 判定の中身は本体（check-skill-design-docs.sh）の --self-test に持つ。本ファイルは
# それを呼び終了コードをそのまま返すだけであり、判定を二重に持たない（本体の
# --self-test を唯一の正とする。両者がずれると、どちらが正しいか分からなくなる
# ため）。
#
# 保守責任者: 人手（ユーザー）。本体の --self-test の呼び出し方（引数）を変える
#   場合は本ファイルも同時に更新する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/check-skill-design-docs.sh" --self-test
