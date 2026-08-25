#!/usr/bin/env bash
# check-screen-doc-template-guard.sh — screen-doc-templateの指示書の判定表の
# 「確かめる手段」欄を短くする
#
# 検査対象のgrep式をそのまま指示書の表の行へ書くと、行が長くなる。この長い行を
# 判定表の隣の行と同じコミットで変更すると、片付けの判定器の追加行検査
# （textlintのja-technical-writing/sentence-length）が複数行を1つの文として
# 結合して数え、100字の上限を超えてcommitを止める。実測（2026-08-25）:
# 判定2・3の2行を同時に変更すると、変更前の内容のままでも結合後の文が
# 100字超過で不合格になった。式をこのファイルへ移し、表からは短い
# ファイル名だけを呼ぶ形にする。
# 先例: docs/scripts/check-boundary-value-scope.sh（同じ理由でスクリプト化した）
#
# 使い方:
#   bash docs/scripts/check-screen-doc-template-guard.sh                    判定2: ガード文を持つ
#   bash docs/scripts/check-screen-doc-template-guard.sh --no-direct-chain  判定3: 直接チェーンの呼び出しが残らない

set -uo pipefail

TARGET="delivery-payload/templates/screen-doc-template.html"

case "${1:-}" in
  --no-direct-chain)
    test "$(grep -c "getElementById('doc-md').textContent" "$TARGET")" -eq 0
    ;;
  *)
    grep -q "if (!container || !heroTitle || !tocList) return;" "$TARGET"
    ;;
esac
