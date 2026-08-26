#!/usr/bin/env bash
# 見本・テンプレート廃止語検査の自己テストだけを呼ぶ薄い入口。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

exec bash "$REPO_ROOT/docs/scripts/check-retired-terms-in-samples.sh" --self-test
