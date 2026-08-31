#!/usr/bin/env bash
# test-payload-references-scan.sh — 配布物の参照切れと「正本」参照の実データ走査を
# 第1層の集約へ載せる薄い入口。判定の中身は本体（check-payload-references.sh）を
# 唯一の正とし、ここへ写して持たない（1-56「検査の常設」への対応）。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/../verification/check-payload-references.sh"
