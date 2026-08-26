#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

case "${1:-}" in
  ""|--self-test) exec bash "$REPO_ROOT/docs/scripts/check-skill-guide-consistency.sh" --self-test ;;
  *) echo "使い方: $0 [--self-test]" >&2; exit 2 ;;
esac
