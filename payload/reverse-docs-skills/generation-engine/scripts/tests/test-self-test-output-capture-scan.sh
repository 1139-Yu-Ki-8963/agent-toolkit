#!/usr/bin/env bash
# test-self-test-output-capture-scan.sh — 出力捨て検査（1-57）の実データ走査を
# 第1層の集約へ載せる薄い入口。判定の中身は本体を唯一の正とし、写して持たない。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/check-self-test-output-capture.sh"
