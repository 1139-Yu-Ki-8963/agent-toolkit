#!/usr/bin/env bash
# check-improvement-ledger.mjs（CLIとして直接実行したときの本番経路）を
# 第1層の集約から呼ぶ入口。
#
# 対象は .mjs であり、集約（run-layer-machine-checks.sh）の収集条件のどちらにも
# 当てはまらず、一度も集約から実行されないまま残っていた（作業課題一覧
# 「検査が7件、第1層の集約に載らないまま実行されない」）。対象は引数なしで
# 実行すると既定の台帳（docs/tasks/work-records/改善反映台帳.md）を読み、
# 判定結果をJSONで出力して不合格なら終了コード1を返す（本番の呼び方そのもの）。
# 薄い exec ラッパーで橋渡しする。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

case "${1:-}" in
  ""|--self-test)
    exec node "$REPO_ROOT/generation-engine/scripts/check-improvement-ledger.mjs"
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
