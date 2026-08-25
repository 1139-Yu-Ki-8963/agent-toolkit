#!/usr/bin/env bash
# check-confirmation-ledger.mjs を第1層の集約から呼ぶ入口。
#
# 対象は --ledger を必須引数とし、fixture なしに単体で自己完結できない
# （引数なしで実行すると使い方を表示して終了コード1で終わる）。ロジックの
# 検証は generation-engine/scripts/tests/test-confirmation-ledger.mjs が既に
# 複数のfixtureで対象を子プロセスとして呼び出しており、そちらが唯一の
# 実質的なテストである。本ラッパーはその既存テストへ委譲するだけであり、
# 対象そのものは集約からは実行されない代わりに、既存テストの二重実行という
# 形で集約の対象一覧へ現れる（作業課題一覧「検査が7件、第1層の集約に載らない
# まま実行されない」）。所要時間が短いため二重実行の許容範囲内と判断した。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

case "${1:-}" in
  ""|--self-test)
    exec node "$SCRIPT_DIR/test-confirmation-ledger.mjs"
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
