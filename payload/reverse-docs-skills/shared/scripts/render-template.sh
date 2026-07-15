#!/usr/bin/env bash
# render_template — 単一パス方式のプレースホルダ置換(共通関数)
#
# Usage:
#   source "path/to/render-template.sh"
#   result="$(render_template "$template" "{{KEY1}}" "$val1" "{{KEY2}}" "$val2")"
#
# テンプレートの「まだ処理していない残り」だけを走査対象にし、一度確定した出力
# (地の文または埋め込み済みの値)は二度とプレースホルダのパターンマッチ対象にしない。
# 値の中身に他マーカーの文字列が偶然含まれていても誤爆しない。

render_template() {
  local template="$1"; shift
  local -a keys=() vals=()
  while [ $# -gt 0 ]; do
    keys+=("$1"); vals+=("$2"); shift 2
  done

  local rest="$template" result="" i n=${#keys[@]}
  local best_idx best_prefix candidate

  while :; do
    best_idx=-1
    best_prefix=""
    for ((i = 0; i < n; i++)); do
      case "$rest" in
        *"${keys[$i]}"*)
          candidate="${rest%%"${keys[$i]}"*}"
          if [ "$best_idx" -eq -1 ] || [ "${#candidate}" -lt "${#best_prefix}" ]; then
            best_idx=$i
            best_prefix="$candidate"
          fi
          ;;
      esac
    done
    [ "$best_idx" -eq -1 ] && break
    result="${result}${best_prefix}${vals[$best_idx]}"
    rest="${rest#"${best_prefix}"}"
    rest="${rest#"${keys[$best_idx]}"}"
  done

  result="${result}${rest}"
  printf '%s' "$result"
}
