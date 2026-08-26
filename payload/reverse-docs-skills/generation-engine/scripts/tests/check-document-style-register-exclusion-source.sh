#!/usr/bin/env bash
# docs側の除外定義構造検査へ委譲する薄いラッパー（1-237）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

case "${1:-}" in --self-test) ;; esac
exec bash "$REPO_ROOT/docs/scripts/check-document-style-register-exclusion-source.sh" "$@"
