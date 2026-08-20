#!/usr/bin/env bash
# link-checker.sh - HTML ファイル内の相対パスリンクを検証する
# 使用法: link-checker.sh [チェック対象ディレクトリ]
# 終了コード: 壊れたリンク 0 件なら 0、1 件以上なら 1

set -euo pipefail

TARGET_DIR="${1:-ai-management-portal}"

# 絶対パスに変換
if [[ "${TARGET_DIR}" != /* ]]; then
  TARGET_DIR="$(pwd)/${TARGET_DIR}"
fi

if [[ ! -d "${TARGET_DIR}" ]]; then
  echo "ERROR: ディレクトリが見つかりません: ${TARGET_DIR}" >&2
  exit 1
fi

broken_count=0

# 対象ディレクトリ内の全 HTML ファイルを走査
while IFS= read -r html_file; do
  html_dir="$(dirname "${html_file}")"
  line_num=0

  while IFS= read -r line; do
    line_num=$((line_num + 1))

    # href="..." と src="..." からパスを抽出
    # http://, https://, #, javascript:, data:, mailto: で始まるものは除外
    while IFS= read -r attr_value; do
      # 除外パターンをスキップ
      case "${attr_value}" in
        http://*|https://*|"#"*|"javascript:"*|"data:"*|"mailto:"*)
          continue
          ;;
        /*|*\${*)
          # / で始まるサーバー絶対パスと ${...} テンプレート変数を除外
          continue
          ;;
      esac

      # 空値はスキップ
      [[ -z "${attr_value}" ]] && continue

      # クエリ文字列・フラグメントを除去してパス部分のみ取得
      path_only="${attr_value%%\#*}"
      path_only="${path_only%%\?*}"

      [[ -z "${path_only}" ]] && continue

      # # のみのアンカーリンクをスキップ
      [[ "${path_only}" == "#" ]] && continue

      # HTML ファイルのディレクトリから相対パスを解決
      resolved="${html_dir}/${path_only}"

      if [[ ! -e "${resolved}" ]]; then
        echo "BROKEN: ${html_file}:${line_num}: ${attr_value}"
        broken_count=$((broken_count + 1))
      fi
    done < <(
      # href と src の値を抽出（シングル/ダブルクォート両対応）
      printf '%s\n' "${line}" \
        | grep -oE '(href|src)="[^"]*"' \
        | sed 's/^[^=]*="\(.*\)"$/\1/' 2>/dev/null
      printf '%s\n' "${line}" \
        | grep -oE "(href|src)='[^']*'" \
        | sed "s/^[^=]*='\\(.*\\)'\$/\\1/" 2>/dev/null
    )
  done < "${html_file}"
done < <(find "${TARGET_DIR}" -name "*.html" | sort)

if [[ "${broken_count}" -eq 0 ]]; then
  echo "OK: 壊れたリンクなし"
  exit 0
else
  echo "FAIL: 壊れたリンク ${broken_count} 件"
  exit 1
fi
