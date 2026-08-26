#!/usr/bin/env bash
# docs/scripts/check-ledger-acceptance-coverage.sh の自己テストを
# 第1層の機械検証から拾えるようにする薄い入口。判定は本体へ委譲する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET="$REPO_ROOT/docs/scripts/check-ledger-acceptance-coverage.sh"

case "${1:-}" in
  --self-test)
    exec bash "$TARGET" --self-test
    ;;
  *)
    echo "usage: $0 --self-test" >&2
    exit 2
    ;;
esac
