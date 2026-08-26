#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

case "${1:-}" in
  ""|--self-test) exec bash "$REPO_ROOT/docs/scripts/check-skill-allowed-tools.sh" --self-test ;;
  *) echo "[UNKNOWN] 未対応の引数です: ${1:-引数なし}" >&2; exit 2 ;;
esac
