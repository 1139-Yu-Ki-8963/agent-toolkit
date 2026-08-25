#!/usr/bin/env bash
# check-portal-label-collision.sh — docs/scripts/check-portal-label-collision.sh の
# 自己テストを第1層の機械検証(run-layer-machine-checks.sh)から拾えるようにする入口。
#
# docs/scripts/ 配下は第1層の集約の走査対象外である。本体の判定を複製せず、
# このラッパーから本体の --self-test を呼ぶことで、第1層へ自己テストを載せる。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET="$REPO_ROOT/docs/scripts/check-portal-label-collision.sh"

if [ "$#" -ne 1 ]; then
  echo "usage: $0 --self-test" >&2
  exit 2
fi

case "${1:-}" in
  --self-test)
    exec bash "$TARGET" --self-test
    ;;
  *)
    echo "usage: $0 --self-test" >&2
    exit 2
    ;;
esac
