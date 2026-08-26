#!/usr/bin/env bash
# check-portal-label-collision.sh — docs/scripts/check-portal-label-collision.sh の
# 回帰テストを第1層の機械検証(run-layer-machine-checks.sh)から拾えるように
# する入口。
#
# 判定の中身は本体の --self-test を唯一の正とし、このラッパーには複製しない。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET="$REPO_ROOT/docs/scripts/check-portal-label-collision.sh"

if [ "$#" -gt 1 ]; then
  echo "usage: $0 [--self-test]" >&2
  exit 2
fi

case "${1:-}" in
  ""|--self-test)
    exec bash "$TARGET" --self-test
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
