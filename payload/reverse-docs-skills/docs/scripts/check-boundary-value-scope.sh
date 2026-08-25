#!/usr/bin/env bash
# check-boundary-value-scope.sh — 1-267の判定表の「確かめる手段」欄を短くする
#
# 検査本体（generation-engine/scripts/tests/check-design-code-consistency.sh）
# への呼び出しをそのまま指示書の表の行へ書くと、行が長くなる。この長い行を
# 判定表の隣の行と同じコミットで変更すると、片付けの判定器の追加行検査
# （textlint の ja-technical-writing/sentence-length）が2行を1つの文として
# 結合して数え、100字の上限を超えて commit を止める。実測（2026-08-25）:
# 元の2行（`--self-test` 行と `generation-engine/samples` 行）を同時に
# 変更すると、変更前の内容のままでも結合後の文が87字超過で不合格になった。
# 式をこのファイルへ移し、表からは短いファイル名だけを呼ぶ形にする。
# 先例: docs/scripts/check-broken-verdict-rows.sh・docs/scripts/check-layer1-declarations.sh
# （こちらは表の縦棒が判定器の列区切りと衝突する別の理由でスクリプト化した）。
#
# 使い方:
#   bash docs/scripts/check-boundary-value-scope.sh              見本の出力を検査する
#   bash docs/scripts/check-boundary-value-scope.sh --self-test  検査本体の自己テストを呼ぶ
#
# 終了コードは検査本体（TARGET）の終了コードをそのまま返す。

set -uo pipefail

TARGET="generation-engine/scripts/tests/check-design-code-consistency.sh"

case "${1:-}" in
  --self-test)
    exec bash "$TARGET" --self-test
    ;;
  *)
    exec bash "$TARGET" generation-engine/samples
    ;;
esac
