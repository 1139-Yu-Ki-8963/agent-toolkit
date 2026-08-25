#!/usr/bin/env bash
# check-detailed-design-conventions.cjs を第1層の集約から呼ぶ入口。
#
# 対象は .cjs であり、集約（run-layer-machine-checks.sh）の収集条件（*.sh の
# "--self-test)" 文字列、または test-*.cjs・test-*.mjs という名前）のどちらにも
# 当てはまらず、一度も集約から実行されないまま残っていた（作業課題一覧
# 「検査が7件、第1層の集約に載らないまま実行されない」）。対象は引数なし・
# --self-test のどちらでも自己テストへ入る（process.argv.length === 2 ||
# process.argv[2] === "--self-test"）。薄い exec ラッパーで橋渡しする。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

case "${1:-}" in
  ""|--self-test)
    exec node "$SCRIPT_DIR/check-detailed-design-conventions.cjs" --self-test
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
