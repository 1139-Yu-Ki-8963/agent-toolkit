#!/usr/bin/env bash
# 本体（docs/scripts/check-crumb-contrast.sh）の自己テストを第1層の集約へ載せる薄い入口。判定の中身は持たない。
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TARGET="${ROOT}/docs/scripts/check-crumb-contrast.sh"
[ -f "$TARGET" ] || { echo "[UNKNOWN] 本体が無いため判定できません（配布対象外: ${TARGET}）"; exit 2; }
exec bash "$TARGET" --self-test
