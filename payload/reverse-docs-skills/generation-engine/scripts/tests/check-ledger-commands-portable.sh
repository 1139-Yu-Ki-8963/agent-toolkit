#!/usr/bin/env bash
# docs/scripts/check-ledger-commands-portable.sh の自己テストを呼ぶ薄い入口。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET="$REPO_ROOT/docs/scripts/check-ledger-commands-portable.sh"

exec bash "$TARGET" --self-test
