#!/bin/bash
# 判定表の「確かめる手段」の欄が壊れていないかを調べる。
#
# 壊れた形とは、逆引用符で囲まれたコマンドの中へ状態の値
# （未着手・未確認・完了・対応中・対象外）が入り込んだものを指す。
# 判定器が表の列を書き換えるとき、コマンドに含まれる縦棒を列の区切りと
# 読み違えると、この形が生まれる。生まれるとコマンドが壊れ、以後その判定は
# 実行できなくなる。
#
#   壊れた形の例（コマンドの途中に状態が入っている）
#   | 1. 例 | `output=$(cmd 2>&1 | 未着手 | :)` | 完了 | abc | 説明 |
#
# 使い方:
#   bash docs/scripts/check-broken-verdict-rows.sh [対象...]
#   bash docs/scripts/check-broken-verdict-rows.sh --self-test
#
# 対象を省略すると docs/tasks/*.md と docs/tasks/done/*.md を見る。
# 壊れた行が1件でもあれば終了コード1、0件なら0を返す。
#
# 実装判断: 判定の本体を指示書の表へ直接書くと、その式に含まれる縦棒を
#   判定器が列の区切りと読み違え、判定行そのものを壊す。実際に
#   2026-08-24、表へ直接書いた式が判定器の切り出しに失敗し、実行すると
#   終了コード0なのに「満たさない」と記録された。式をこのファイルへ
#   移し、表からはファイル名だけを呼ぶ形にして、縦棒を表から取り除く。
#
# 実装判断: 逆引用符の対を数え、奇数番目の区切り（囲まれた中身）だけを見る。
#   前後の逆引用符を対応づけずに拾う形は、2列目のコマンドの閉じと5列目の
#   証跡の開きをまたいで一致し、正しい行を誤って検出する。
#
# 実装判断: awk の実行へ LC_ALL=en_US.UTF-8 を都度明示する。全角文字を含む
#   正規表現は LC_ALL=C の下で match が働かない（実装判断記録規約の
#   「ロケールの使い分け」節）。ファイル冒頭の export では、呼び出し元が
#   LC_ALL=C を前置きした場合に上書きされるため足りない。

set -u

run_check() {
  if [ "$#" -eq 0 ]; then
    set -- docs/tasks/*.md docs/tasks/done/*.md
  fi
  local found
  found="$(LC_ALL=en_US.UTF-8 awk -F'`' '
    {
      # 逆引用符が奇数個の行は対が閉じていない。どこが囲まれた中身かを
      # 決められないため、判定の対象から外す。文中で逆引用符を1つだけ使う
      # 記述（説明の途中で引用を開いたまま終える形）がこれに当たる。
      if ((NF - 1) % 2 != 0) next
      for (i = 2; i <= NF; i += 2) {
        if ($i ~ /\| *(未着手|未確認|完了|対応中|対象外) *\|/) {
          printf "%s:%d: %s\n", FILENAME, FNR, substr($i, 1, 70)
        }
      }
    }
  ' "$@" 2>/dev/null)"

  if [ -n "$found" ]; then
    printf '%s\n' "$found" >&2
    printf '[FAIL] 壊れた判定行=%s件\n' "$(printf '%s\n' "$found" | wc -l | tr -d ' ')" >&2
    return 1
  fi
  echo "[PASS] 壊れた判定行=0件"
  return 0
}

run_self_test() {
  local tmp rc=0 pass=0 fail=0
  # 置き場を明示するのは、引数なしの mktemp が既定の置き場へ書こうとして失敗する環境があるためである（実測 2026-08-24）。素直な mktemp へ戻さない。
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため自己テストを判定できません（mktemp -d が一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    return 2
  fi

  printf '| 1. 例 | `test -z ""` | 完了 | abc | 説明 |\n' > "$tmp/ok.md"
  if run_check "$tmp/ok.md" >/dev/null 2>&1; then
    echo "  [PASS] 正しい行は素通りする"; pass=$((pass + 1))
  else
    echo "  [FAIL] 正しい行は素通りする" >&2; fail=$((fail + 1)); rc=1
  fi

  printf '| 1. 例 | `output=$(cmd 2>&1 | 未着手 | :)` | 完了 | abc | 説明 |\n' > "$tmp/ng.md"
  if run_check "$tmp/ng.md" >/dev/null 2>&1; then
    echo "  [FAIL] 壊れた行を検出する" >&2; fail=$((fail + 1)); rc=1
  else
    echo "  [PASS] 壊れた行を検出する"; pass=$((pass + 1))
  fi

  printf '| 1. 例 | `test -z ""` | 未着手 | abc | `別のコマンド` |\n' > "$tmp/two.md"
  if run_check "$tmp/two.md" >/dev/null 2>&1; then
    echo "  [PASS] 2つの区間をまたぐ形を誤検出しない"; pass=$((pass + 1))
  else
    echo "  [FAIL] 2つの区間をまたぐ形を誤検出しない" >&2; fail=$((fail + 1)); rc=1
  fi

  rm -rf "$tmp"
  printf '実行 %d 件 / 成功 %d 件 / 失敗 %d 件\n' "$((pass + fail))" "$pass" "$fail"
  return "$rc"
}

case "${1:-}" in
  --self-test) shift; run_self_test "$@" ;;
  *) run_check "$@" ;;
esac
