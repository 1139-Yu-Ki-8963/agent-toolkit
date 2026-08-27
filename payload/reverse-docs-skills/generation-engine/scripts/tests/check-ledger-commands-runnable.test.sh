#!/usr/bin/env bash
# check-ledger-commands-runnable.sh を第1層の集約から呼ぶための薄い入口。
#
# 本体は引数を取らず、実行そのものが検査になる形である。集約の収集条件は
# 「--self-test) を引数として処理する .sh」または「tests/ 配下の test-*.cjs / test-*.mjs」
# であり、本体はどちらにも当たらないため一度も実行されないまま残っていた
# （2026-08-28実測。配線漏れの検査が9件をまとめて報告した）。
#
# 本体を改名すると既存の参照が切れるため、改名せずに入口を置く。
# 判定の中身は写して持たない。本体の終了コードをそのまま返す。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${1:-}" = "--self-test" ] || [ "$#" -eq 0 ]; then
  exec bash "$SCRIPT_DIR/check-ledger-commands-runnable.sh"
fi
echo "使い方: $(basename "$0") [--self-test]" >&2
exit 2
