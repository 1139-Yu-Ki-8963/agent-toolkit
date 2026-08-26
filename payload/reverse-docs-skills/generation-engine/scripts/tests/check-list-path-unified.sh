#!/usr/bin/env bash
# docs/scripts/check-list-path-unified.sh の自己テストを第1層から呼ぶ入口。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET="$REPO_ROOT/docs/scripts/check-list-path-unified.sh"

case "${1:-}" in
  --self-test)
    exec bash "$TARGET" --self-test
    ;;
  *)
    echo "usage: $0 --self-test" >&2
    exit 2
    ;;
esac
