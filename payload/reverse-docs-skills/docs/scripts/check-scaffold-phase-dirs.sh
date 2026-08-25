#!/usr/bin/env bash
# check-scaffold-phase-dirs.sh — 1-210の判定表の「確かめる手段」欄を短くする
#
# 判定「basic-design配置」「detail-design配置」「ハードコード残存なし」を
# 指示書の表へ直接パイプ付きコマンドで書くと、片付けの判定器が
# 縦棒を列の
# 区切りと読み違え、判定行そのものを壊す。先例: docs/scripts/check-broken-
# verdict-rows.sh・docs/scripts/check-layer1-declarations.sh。式をこの
# ファイルへ移し、表からは短いファイル名だけを呼ぶ形にする。
#
# 出力先を ${TMPDIR:-/tmp} 配下に取るのは、判定不能規約
# （.claude/rules/always/verification/indeterminate-result/rule.md）に
# 沿うためである。裸の /tmp 直下はサンドボックス制約で書き込めない場合が
# あり、その場合は mktemp の失敗として [UNKNOWN]・終了コード2を返す。
#
# 使い方:
#   bash docs/scripts/check-scaffold-phase-dirs.sh --basic
#     api種別・basicフェーズで単位を1件生成し、basic-designフォルダに
#     配置されるかを判定する。
#   bash docs/scripts/check-scaffold-phase-dirs.sh --detail
#     同様にdetailフェーズで判定する。
#   bash docs/scripts/check-scaffold-phase-dirs.sh --no-hardcode
#     design_unit_phase_label() 関数の本体に「基本設計」「詳細設計」という
#     直書きの文字列が残っていないかを判定する。
#
# 終了コード: 満たせば0、満たさなければ1。

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
scaffold="$repo_root/generation-engine/scripts/scaffold-design-unit.sh"

if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-scaffold-phase-dirs.XXXXXX" \
    2>/dev/null)" || [ -z "$work" ]; then
  msg="[UNKNOWN] 一時領域を作成できません"
  msg+="（mktempがサンドボックス制約等で失敗した可能性があります）"
  echo "$msg" >&2
  exit 2
fi
trap 'rm -rf "$work"' EXIT

case "${1:-}" in
  --basic)
    bash "$scaffold" api basic "$work/out" api-sample01 サンプルAPI > "$work/log.txt" 2>&1
    test -f "$work/out/docs/design/apis/api-api-sample01/basic-design/API基本設計書.md"
    ;;
  --detail)
    bash "$scaffold" api detail "$work/out" api-sample01 サンプルAPI > "$work/log.txt" 2>&1
    test -d "$work/out/docs/design/apis/api-api-sample01/detail-design"
    ;;
  --no-hardcode)
    sed -n '/^design_unit_phase_label/,/^}/p' "$scaffold" > "$work/fn.txt"
    count="$(grep -c '基本設計' "$work/fn.txt")"
    count2="$(grep -c '詳細設計' "$work/fn.txt")"
    total=$((count + count2))
    echo "直書きの残存: $total 件"
    test "$total" -eq 0
    ;;
  *)
    echo "usage: check-scaffold-phase-dirs.sh --basic|--detail|--no-hardcode" >&2
    exit 2
    ;;
esac
