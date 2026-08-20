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
#
# 集約の対象外: 本ファイルは source される共通関数ライブラリで
# あり、単体で実行される本番経路のスクリプトではない（トップレベルの引数解析・実行文を
# 持たない）。回帰検証は本関数を source する各consumer（build-portal.sh・
# build-unit-list.sh 等）自身の --self-test を通じて間接的に行うのが基本だが、改善課題
# 1-156（doc_nav 等の二重引用符を含む値をファイル経由で安全に渡す経路の検証）は
# generation-engine/scripts/shell-injection.sh --self-test が本関数を source して間接的にカバーする。

# strip_generator_notice_comment — テンプレート先頭の生成情報コメントを除去する(改善課題 1-47)
#
# 対象: テンプレート先頭(最初の<style>タグより前)にある、最初のHTMLコメント
#       <!-- ... --> のうち、生成スクリプト名・プレースホルダ一覧・内部フィールド名
#       (render_template()等)のいずれかを本文に含むもの。
# 対象外: <style>より後に現れるコメント(<!--SHELL_SIDEBAR-->等の埋め込みマーカーや
#         本文中の条件分岐説明等)。先頭に判定を限定することで、意味のある本文コメントを
#         誤って消さない。
# 判定に一致しない場合(様式テンプレート等、先頭コメント自体が無い場合を含む)は
# 入力をそのまま返す。
strip_generator_notice_comment() {
  local input="$1"

  case "$input" in
    *"<!--"*) ;;
    *) printf '%s' "$input"; return 0 ;;
  esac

  local before="${input%%<!--*}"
  case "$before" in
    *"<style"*)
      printf '%s' "$input"
      return 0
      ;;
  esac

  local after_open="${input#*<!--}"
  case "$after_open" in
    *"-->"*) ;;
    *) printf '%s' "$input"; return 0 ;;
  esac

  local comment_body="${after_open%%-->*}"
  case "$comment_body" in
    *"生成スクリプト"*|*"生成:"*|*"プレースホルダ"*|*"render_template()"*)
      local after_close="${after_open#*-->}"
      printf '%s' "${before}${after_close}"
      ;;
    *)
      printf '%s' "$input"
      ;;
  esac
}

render_template() {
  local template
  template="$(strip_generator_notice_comment "$1")"; shift
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
