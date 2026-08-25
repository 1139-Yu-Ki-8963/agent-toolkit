#!/usr/bin/env bash
# check-sequence-kind-policy-test.sh — シーケンス図の指示書の判定表の
# 「確かめる手段」欄を短くする
#
# 判定式をそのまま指示書の表の行へ書くと、行が長くなる。この長い行を
# 判定表の隣の行と同じコミットで変更すると、片付けの判定器の追加行検査
# （textlintのja-technical-writing/sentence-length）が複数行を1つの文として
# 結合して数え、100字の上限を超えてcommitを止める。実測（2026-08-25）:
# 判定1〜3の3行を同時に変更すると、判定式は単独でも100字を超えていた。
# 判定1の式（自己テストのパスをそのまま`node`へ渡すだけの行）も、単独で
# 100字を超えていた。加えて、素の`grep -c AssertionError`は一致0件のとき
# 終了コード1を返すため、「含まれないことが正しい」判定であるにも
# かかわらず判定器が「満たさない」と誤判定する。`test ... -eq 0`で
# 件数比較する形へ直し、式をこのファイルへ移して表からは短いファイル名
# だけを呼ぶ形にする。
# 先例: docs/scripts/check-boundary-value-scope.sh（同じ理由でスクリプト化した）
#
# 判定3（抽出条件がコメント文言と一致する）の`grep -rn "1-65" <2ファイル>`も、
# 対象パスを2つ並べるだけで100字を超えていた（実測: 179字）。同じ理由で
# 本ファイルへ移した。
#
# 使い方:
#   bash docs/scripts/check-sequence-kind-policy-test.sh                       判定1: 自己テストの終了コードが0
#   bash docs/scripts/check-sequence-kind-policy-test.sh --no-assertion-error  判定2: AssertionErrorが含まれない
#   bash docs/scripts/check-sequence-kind-policy-test.sh --comment-match       判定3: 抽出条件がコメント文言と一致する

set -uo pipefail

TARGET=".claude/skills/generating-sequence-diagram-for-reverse-docs/scripts/test-sequence-kind-policy.mjs"
UNIT_LIST_TEMPLATE="delivery-payload/templates/unit-list/unit-list-template.html"

case "${1:-}" in
  --no-assertion-error)
    test "$(node "$TARGET" 2>&1 | grep -c AssertionError)" -eq 0
    ;;
  --comment-match)
    grep -rn "1-65" "$TARGET" "$UNIT_LIST_TEMPLATE"
    ;;
  *)
    node "$TARGET"
    ;;
esac
