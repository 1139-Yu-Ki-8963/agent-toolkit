#!/usr/bin/env bash
# check-customer-facing-adequacy.sh — 配布物側の checkers/check-customer-facing-adequacy.sh
# への薄いラッパー（1-233）。
#
# 検査本体は delivery-payload/templates/rules/checkers/check-customer-facing-adequacy.sh
# にある（配布物として納品先へ配るため）。本ファイルは第1層の機械検証
# （run-layer-machine-checks.sh の動的収集）から実行されるよう、同じ
# --self-test 契約のまま本体へ委譲するだけの薄いラッパーであり、判定の
# 中身を二重に持たない。
#
# 使い方:
#   check-customer-facing-adequacy.sh <project_root>
#   check-customer-facing-adequacy.sh --self-test
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
exec bash "$REPO_ROOT/delivery-payload/templates/rules/checkers/check-customer-facing-adequacy.sh" "$@"
