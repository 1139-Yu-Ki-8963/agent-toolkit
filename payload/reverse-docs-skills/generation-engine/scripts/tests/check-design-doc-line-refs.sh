#!/usr/bin/env bash
# docs/design の行番号参照検査について、本体の自己テストへ委譲する薄い入口。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

exec bash "$REPO_ROOT/docs/scripts/check-design-doc-line-refs.sh" --self-test
