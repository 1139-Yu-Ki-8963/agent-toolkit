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
  # fieldsは増加するため直接--argjsonを採らず、jq -sで両JSONを標準入力から読む。
  # この値での失敗実測はないが、900列での失敗と単一引数131,071バイトの実測がある。
  # 引数長の上限は環境依存である。直接--argjsonへ戻してはならない。
  # checkerが2026-08-23に許可リスト外使用を報告し、この箇所では初回対策となる（1-249）。
  printf '%s\n%s\n' "$input_json" "$fields_json" | jq -s --arg value "$link_value" '
    .[0] as $input | .[1] as $fields
    | reduce $fields[] as $field ($input; .[$field] = $value)
  '
}
