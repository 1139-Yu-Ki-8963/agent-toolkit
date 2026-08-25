#!/usr/bin/env bash
# .claude/skills/generating-sequence-diagram-for-reverse-docs/scripts/
# test-sequence-kind-policy.mjs を第1層の集約から呼ぶ入口。
#
# 対象は generation-engine/scripts/ の外（.claude/skills/ 配下）にあり、集約
# （run-layer-machine-checks.sh）の走査範囲（generation-engine/scripts/ と
# delivery-payload/templates/rules/checkers/ のみ）に含まれず、一度も集約から
# 実行されないまま残っていた（作業課題一覧「検査が7件、第1層の集約に載らない
# まま実行されない」。1-73で直した後1-83で再び壊れた実害の記録がある）。
# 対象は引数なしで実行するとそのまま自己テストとして動く。薄い exec
# ラッパーで橋渡しする。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

case "${1:-}" in
  ""|--self-test)
    exec node "$REPO_ROOT/.claude/skills/generating-sequence-diagram-for-reverse-docs/scripts/test-sequence-kind-policy.mjs"
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
