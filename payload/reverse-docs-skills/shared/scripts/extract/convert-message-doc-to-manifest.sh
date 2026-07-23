#!/usr/bin/env bash
# 抽出エンジン: メッセージ定義書(Markdown)からメッセージmanifest(JSON)への変換。
# 「キー | 文言(実測) | 種別 | 抽出元 | 使用画面」の5列パイプテーブルをパースし、
# unitKind=message のユニットマニフェストを出力する。
#
# Usage: convert-message-doc-to-manifest.sh <メッセージ定義書.md> <output.json>
#
# 入力契約:
#   <メッセージ定義書.md> : shared/templates/リバース検証/プロジェクト共通/メッセージ定義書.md
#                           形式に準拠した5列パイプテーブルを含むMarkdown
#   <output.json>         : 出力先パス
#
# 出力契約:
#   {
#     unitKind: "message",
#     generatedAt: string(UTC ISO8601),
#     units: [{ unitKey, messageText, messageType, sourceFile, usedScreen }],
#     summary: { totalCount: number, byType: { <messageType>: number, ... } }
#   }
#
# パース仕様:
#   - パイプ(|)区切りの行のうち、5列に分割できる行だけを対象とする
#   - ヘッダ行(1列目が "キー")・セパレータ行(全列がハイフン/コロン/空白のみ)・
#     プレースホルダ行(1列目が "<...>" 形式)はスキップする
#   - 各列のバッククォート(`)は除去し、前後空白をトリムする
#   - テーブルが1件も見つからない場合はエラーにせず units:[] で正常終了する(fail-safe)
#
# 終了コード:
#   0 : 正常終了(テーブル未検出でも units:[] で正常出力)
#   1 : 入力ファイル不在、または引数不足

set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <メッセージ定義書.md> <output.json>" >&2
}

if [ "$#" -lt 2 ]; then
  usage
  exit 1
fi

input_file="$1"
output_file="$2"

if [ ! -f "$input_file" ]; then
  echo "ERROR: input file not found: $input_file" >&2
  exit 1
fi

generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# パイプテーブル行を抽出し、ヘッダ/セパレータ/プレースホルダ行を除外して
# キー\t文言\t種別\t抽出元\t使用画面 のTSVに変換する
tsv="$(awk '
  function trim(s) {
    gsub(/^[ \t\r]+|[ \t\r]+$/, "", s)
    return s
  }
  function unbacktick(s) {
    gsub(/^`+|`+$/, "", s)
    return s
  }
  /^[ \t]*\|/ {
    line = $0
    gsub(/^[ \t]*\|/, "", line)
    gsub(/\|[ \t\r]*$/, "", line)
    n = split(line, cols, "|")
    if (n != 5) next

    for (i = 1; i <= 5; i++) {
      cols[i] = unbacktick(trim(cols[i]))
    }

    # セパレータ行判定(ハイフン・コロン・空白のみで構成)
    is_sep = 1
    for (i = 1; i <= 5; i++) {
      if (cols[i] !~ /^[-: ]*$/) { is_sep = 0 }
    }
    if (is_sep) next

    # ヘッダ行判定
    if (cols[1] == "キー") next

    # プレースホルダ行判定(<...> 形式)
    if (cols[1] ~ /^<.*>$/) next

    printf "%s\t%s\t%s\t%s\t%s\n", cols[1], cols[2], cols[3], cols[4], cols[5]
  }
' "$input_file")"

if [ -z "$tsv" ]; then
  jq -n --arg generatedAt "$generated_at" '{
    unitKind: "message",
    generatedAt: $generatedAt,
    units: [],
    summary: { totalCount: 0, byType: {} }
  }' > "$output_file"
  exit 0
fi

units_json="$(printf '%s\n' "$tsv" | jq -R -s '
  split("\n") | map(select(length > 0)) | map(split("\t")) | map({
    unitKey: .[0],
    messageText: .[1],
    messageType: .[2],
    sourceFile: .[3],
    usedScreen: .[4]
  })
')"

jq -n \
  --arg generatedAt "$generated_at" \
  --argjson units "$units_json" \
  '
  {
    unitKind: "message",
    generatedAt: $generatedAt,
    units: $units,
    summary: {
      totalCount: ($units | length),
      byType: ($units | group_by(.messageType) | map({key: .[0].messageType, value: length}) | from_entries)
    }
  }
  ' > "$output_file"
