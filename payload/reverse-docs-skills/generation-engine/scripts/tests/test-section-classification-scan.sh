#!/usr/bin/env bash
# check-section-classification.sh の実データ走査を第1層の集約へ載せる入口（自己テストの分岐ラベルを含めない）。
set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/docs-script-scan.sh"
run_docs_script_scan "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/docs/scripts/check-section-classification.sh" "check-section-classification.sh"
