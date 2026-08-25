#!/usr/bin/env bash
# check-skill-machine-inspection-consistency.mjs を第1層の集約から呼ぶ入口。
#
# 対象は .mjs であり、集約（run-layer-machine-checks.sh）の収集条件（*.sh の
# "--self-test)" 文字列、または generation-engine/scripts/ 配下の
# test-*.cjs・test-*.mjs という名前）のどちらにも当てはまらず、一度も集約から
# 実行されないまま残っていた（作業課題一覧「検査が7件、第1層の集約に載らない
# まま実行されない」）。対象は既に --self-test 引数を自前で処理するため、
# 薄い exec ラッパーで橋渡しする（generation-engine/scripts/tests/
# check-inventory-approval-step.test.sh と同型）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

case "${1:-}" in
  ""|--self-test)
    exec node "$REPO_ROOT/generation-engine/scripts/check-skill-machine-inspection-consistency.mjs" --self-test
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
