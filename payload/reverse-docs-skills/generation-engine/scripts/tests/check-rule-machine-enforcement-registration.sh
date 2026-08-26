#!/usr/bin/env bash
# docs/scripts/check-rule-machine-enforcement-registration.sh の自己テストを
# 第1層の機械検証から呼ぶ入口。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

case "${1:-}" in
  ""|--self-test)
    exec bash "$REPO_ROOT/docs/scripts/check-rule-machine-enforcement-registration.sh" --self-test
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
