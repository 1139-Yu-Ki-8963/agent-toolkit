#!/bin/bash -p
set -euo pipefail

# ensure-githooks.test.sh — ensure-githooks.sh の回帰テスト用の薄い入口。
# 判定の中身は本体の --self-test に持つ（二重に持たない）。
#
# シェバンと`bash -p`は対にする（2026-09-06第19版）。`bash`を明示指定して
# 委譲する`exec`はこの入口自身のシェバンを引き継がないため、委譲先にも
# `-p`を明示する。片方だけでは`BASH_ENV`によるインタプリタ起動の乗っ取り
# を防げない。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash -p "${SCRIPT_DIR}/ensure-githooks.sh" --self-test
