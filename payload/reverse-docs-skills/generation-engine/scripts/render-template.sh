#!/usr/bin/env bash
# render_template — 単一パス方式のプレースホルダ置換(共通関数)
#
# Usage:
#   source "path/to/render-template.sh"
#   result="$(render_template "$template" "{{KEY1}}" "$val1" "{{KEY2}}" "$val2")"
#
# テンプレートだけを左から走査し、一度確定した出力(地の文または埋め込み済みの値)は
# 二度とプレースホルダの走査対象にしない。値の中身に他マーカーの文字列が偶然含まれて
# いても誤爆しない。置換候補が同位置なら、引数で先に渡されたキーを優先する。
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
  if [ "$#" -lt 1 ]; then
    echo "render_template: template is required" >&2
    return 2
  fi

  local template
  template="$(strip_generator_notice_comment "$1")"; shift

  if [ $(( $# % 2 )) -ne 0 ]; then
    echo "render_template: key/value arguments must be paired" >&2
    return 2
  fi

  local i
  for ((i = 1; i <= $#; i += 2)); do
    if [ -z "${!i}" ]; then
      echo "render_template: empty key is not supported" >&2
      return 2
    fi
  done

  if ! command -v node >/dev/null 2>&1; then
    echo "render_template: node is required" >&2
    return 127
  fi

  # Bash変数はNULを保持できないため、テンプレートとkey/value列を安全に区切って渡せる。
  # Node側はtemplateのみを走査するため、値に含まれるマーカーは再置換されない。
  printf '%s\0' "$template" "$@" | node -e '
const chunks = [];
process.stdin.on("data", (chunk) => chunks.push(chunk));
process.stdin.on("end", () => {
  const input = Buffer.concat(chunks).toString("utf8");
  if (!input.endsWith("\0")) {
    process.stderr.write("render_template: invalid NUL-delimited input\n");
    process.exitCode = 2;
    return;
  }

  const fields = input.split("\0");
  fields.pop();
  const template = fields.shift();
  if ((fields.length % 2) !== 0) {
    process.stderr.write("render_template: key/value arguments must be paired\n");
    process.exitCode = 2;
    return;
  }

  const keys = [];
  const values = [];
  for (let index = 0; index < fields.length; index += 2) {
    if (fields[index] === "") {
      process.stderr.write("render_template: empty key is not supported\n");
      process.exitCode = 2;
      return;
    }
    keys.push(fields[index]);
    values.push(fields[index + 1]);
  }

  const output = [];
  let cursor = 0;
  while (cursor < template.length) {
    let earliest = -1;
    let matchedIndex = -1;
    for (let index = 0; index < keys.length; index += 1) {
      const position = template.indexOf(keys[index], cursor);
      if (position !== -1 && (earliest === -1 || position < earliest)) {
        earliest = position;
        matchedIndex = index;
      }
    }
    if (matchedIndex === -1) {
      output.push(template.slice(cursor));
      break;
    }
    output.push(template.slice(cursor, earliest), values[matchedIndex]);
    cursor = earliest + keys[matchedIndex].length;
  }

  process.stdout.write(output.join(""));
});
'
}
