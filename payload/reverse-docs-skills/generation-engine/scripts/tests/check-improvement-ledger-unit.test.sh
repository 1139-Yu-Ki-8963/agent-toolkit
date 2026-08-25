#!/usr/bin/env bash
# check-improvement-ledger.test.mjs（node:test によるパーサの単体テスト）を
# 第1層の集約から呼ぶ入口。
#
# 対象は generation-engine/scripts/tests/ 配下にあるが、ファイル名が
# "check-improvement-ledger.test.mjs" であり、集約（run-layer-machine-checks.sh）
# の名前収集条件（test-*.mjs）に一致しない。改名すると、後続の作業指示が
# 依存する "check-improvement-ledger" という部分文字列が --list の出力行から
# 消える（例: docs/tasks/作業課題一覧.md の検収コマンドはこの部分文字列で
# 数える）ため、改名せず薄い exec ラッパーで橋渡しする。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

case "${1:-}" in
  ""|--self-test)
    exec node "$SCRIPT_DIR/check-improvement-ledger.test.mjs"
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
