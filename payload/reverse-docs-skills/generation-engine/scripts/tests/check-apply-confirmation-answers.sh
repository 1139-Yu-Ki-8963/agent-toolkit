#!/usr/bin/env bash
# apply-confirmation-answers.mjs の自己テストを第1層の機械検証から実行する入口。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET="$REPO_ROOT/delivery-payload/templates/delivered-skills/resolving-confirmation-items/scripts/apply-confirmation-answers.mjs"

case "${1:-}" in
  --self-test)
    exec node "$TARGET" --self-test
    ;;
  *)
    echo "usage: $0 --self-test" >&2
    exit 2
    ;;
esac
