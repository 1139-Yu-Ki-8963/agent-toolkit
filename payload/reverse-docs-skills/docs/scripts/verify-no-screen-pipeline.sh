#!/usr/bin/env bash
# 画面0件の見本に対する一気通貫生成を、使い捨ての出力先で1回走らせる。
#
# なぜ要るか: 台帳の検収コマンドが --keep で出力を残す形だったため、
#   2回目以降の実行で前回の残骸が邪魔をして落ちていた（2026-08-28実測）。
#   検証する側は同じコマンドを何度でも実行する。1回しか通らない検収は、
#   記録として成立しない。
#
#   出力先を毎回作り直す処理を検収コマンドへ書くと、行が長くなり
#   台帳の文長の検査に掛かる。処理をここへ移し、表からは短い名前だけを呼ぶ。
#
# 使い方:
#   bash docs/scripts/verify-no-screen-pipeline.sh <検収のキー>
set -uo pipefail

KEY="${1:-probe}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
OUT="${TMPDIR:-/tmp}/verify-no-screen-${KEY}"

rm -rf "$OUT"
cd "$REPO_ROOT" || exit 2
bash generation-engine/scripts/verification/run-layer-full-pipeline.sh \
  --output "$OUT" --repo generation-engine/samples-no-screen --keep
