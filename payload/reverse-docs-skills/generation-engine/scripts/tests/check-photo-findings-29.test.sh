#!/usr/bin/env bash
# check-photo-findings-29.sh を第1層の集約から呼ぶための薄い入口。
#
# 本体は引数を取らず、実行そのものが検査になる形である。集約の収集条件は
# 「--self-test) を引数として処理する .sh」または「tests/ 配下の test-*.cjs / test-*.mjs」
# であり、本体はどちらにも当たらないため一度も実行されないまま残っていた
# （2026-08-28実測。本体は26件の目印を検査し、うち1件が欠けて不合格だった）。
#
# 本体を改名すると、既存の設計判断や検収コマンドが持つ名前の参照が切れる。
# 改名せずに集約から呼ぶため、既存のラッパー（check-improvement-ledger-cli.test.sh 等）
# と同じ形の入口を置く。判定の中身は写して持たない。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${1:-}" = "--self-test" ] || [ "$#" -eq 0 ]; then
  exec bash "$SCRIPT_DIR/../check-photo-findings-29.sh"
fi
echo "使い方: $(basename "$0") [--self-test]" >&2
exit 2
