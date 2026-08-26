#!/usr/bin/env bash
# 配布物側の文体検査へ委譲する薄いラッパー（1-237）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

case "${1:-}" in --self-test) ;; esac
exec bash "$REPO_ROOT/delivery-payload/templates/rules/checkers/check-document-style-register.sh" "$@"
