#!/usr/bin/env bash
# docs/scripts/check-done-instruction-verdicts.sh の自己テストを呼ぶ薄い入口。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET="$REPO_ROOT/docs/scripts/check-done-instruction-verdicts.sh"

case "${1:-}" in
  --self-test)
    exec bash "$TARGET" --self-test
    ;;
  *)
    echo "usage: $0 --self-test" >&2
    exit 2
    ;;
esac
