#!/usr/bin/env bash
# 画面を持たず API だけを持つ対象の輪郭で、一気通貫生成を使い捨ての出力先で1回走らせる。
#
# なぜ要るか: 検証する側は画面を持たず API だけを持つコードを対象にしている。
#   台帳の検収は、この輪郭で納品物が成立することを確かめなければ意味を持たない
#   (docs/design/画面なしAPIのみ対象の設計.md 6節)。verify-no-screen-pipeline.sh は
#   全種別を持たない見本を対象にしており、API のみの輪郭を確かめない。
#   出力先を毎回作り直す処理を検収コマンドへ書くと、行が長くなり台帳の文長の
#   検査に掛かる。処理をここへ移し、表からは短い名前だけを呼ぶ。
#
# 使い方:
#   bash docs/scripts/verify-api-only-pipeline.sh <検収のキー>
#
# 終了コード: 生成連鎖の終了コードをそのまま返す(10段すべて成功なら0)。
set -uo pipefail
KEY="${1:-probe}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
OUT="${TMPDIR:-/tmp}/verify-api-only-${KEY}"
rm -rf "$OUT"
cd "$REPO_ROOT" || exit 2
bash generation-engine/scripts/verification/run-layer-full-pipeline.sh \
  --output "$OUT" --profile api-only --keep
