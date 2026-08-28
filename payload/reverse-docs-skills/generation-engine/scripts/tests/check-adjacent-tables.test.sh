#!/usr/bin/env bash
# check-adjacent-tables.sh の自己テストを第1層の集約へ載せる入口。判定の中身は本体だけが持つ。
set -u
TARGET="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/docs/scripts/check-adjacent-tables.sh"
case "${1:-}" in
  --self-test) exec bash "$TARGET" --self-test ;;
  *) exec bash "$TARGET" "$@" ;;
esac
