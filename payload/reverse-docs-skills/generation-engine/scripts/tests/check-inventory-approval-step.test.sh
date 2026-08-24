#!/usr/bin/env bash
# docs/scripts/check-inventory-approval-step.sh の自己テストを第1層から呼ぶ入口。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

case "${1:-}" in
  ""|--self-test)
    exec bash "$REPO_ROOT/docs/scripts/check-inventory-approval-step.sh" --self-test
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
