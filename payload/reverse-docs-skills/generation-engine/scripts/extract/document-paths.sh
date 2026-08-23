#!/usr/bin/env bash
# document-paths.sh — 実在する資料だけをマニフェストのPathフィールドへ追加する共通処理。
# sourceして document_paths_add_existing <json> <実体> <リンク値> <field>... を呼ぶ。
# 設計判断の正本: docs/rules/portal/page-conventions/rule.md の
# 「## 設計判断」内「### document-paths.sh」を参照する。

# 入力JSONを保ったまま、actual_fileが通常ファイルとして実在する場合だけ、指定された
# 全フィールドへlink_valueを追加する。実在しない場合はフィールドを追加しない。
document_paths_add_existing() {
  local input_json="$1" actual_file="$2" link_value="$3"
  shift 3

  if [ ! -f "$actual_file" ] || [ -z "$link_value" ] || [ "$#" -eq 0 ]; then
    printf '%s' "$input_json"
    return 0
  fi

  local fields_json
  fields_json="$(jq -cn '$ARGS.positional' --args "$@")" || return 1
  printf '%s' "$input_json" | jq --arg value "$link_value" --argjson fields "$fields_json" '
    reduce $fields[] as $field (. ; .[$field] = $value)
  '
}
