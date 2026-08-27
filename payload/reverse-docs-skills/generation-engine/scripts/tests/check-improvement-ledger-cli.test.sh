#!/usr/bin/env bash
# 廃止した改善反映台帳の既定検査が成功扱いで終了することを確かめる入口。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

case "${1:-}" in
  ""|--self-test)
    node "$REPO_ROOT/generation-engine/scripts/check-improvement-ledger.mjs"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      echo "実行 1 件 / 成功 1 件 / 失敗 0 件"
    else
      echo "実行 1 件 / 成功 0 件 / 失敗 1 件" >&2
    fi
    exit "$rc"
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
