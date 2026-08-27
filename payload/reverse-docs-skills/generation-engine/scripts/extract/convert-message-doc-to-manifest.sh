#!/usr/bin/env bash
# 抽出エンジン: メッセージ定義書(Markdown)からメッセージmanifest(JSON)への変換。
# 「キー | 文言(実測) | 種別 | 抽出元 | 使用画面」の5列パイプテーブルをパースし、
# unitKind=message のユニットマニフェストを出力する。
#
# Usage: convert-message-doc-to-manifest.sh <メッセージ定義書.md> <output.json>
#
# 入力契約:
#   <メッセージ定義書.md> : delivery-payload/templates/リバース検証/プロジェクト共通/メッセージ定義書.md
#                           形式に準拠した5列パイプテーブルを含むMarkdown
#   <output.json>         : 出力先パス
#
# 出力契約:
#   {
#     sourceDir: string(入力ファイルの格納ディレクトリのbasenameのみ。出力先環境に
#       依存する絶対パスは含めない), unitKind: "message", generatedAt: string(UTC ISO8601),
#     strategy: { extractionMethod, approvedByUser, unitIdRegex, excludePatterns },
#     detectionSummary: { method, unitCount, unresolvedCount },
#     units: [{ unitKey, unitNameGuess, kind, identifier, confidence,
#               messageText, messageType, sourceFile: string[], usedScreen }],
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

# 改善課題 1-138: 横断検収条件（本番経路スクリプトへの --self-test 実装）に対応する。
# 必要性: メッセージ定義書からのmanifest変換はgenerating-message-list-for-reverse-docsの
#   本番経路で使われる決定的な抽出処理であり、正常系（5列テーブルからunits抽出）・
#   異常系（入力ファイル不在）を自己テストで固定しておく。
if [ "${1:-}" = "--self-test" ]; then
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/convert-message-doc-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' EXIT

  cat > "$tmp/メッセージ定義書.md" <<'MD'
# メッセージ定義書

| キー | 文言(実測) | 種別 | 抽出元 | 使用画面 |
|---|---|---|---|---|
| `E001` | `必須項目です` | `error` | `src/validators.ts` | `home` |
| `I001` | `保存しました` | `info` | `src/save.ts` | `home` |
MD

  pass=0 fail=0
  if bash "${BASH_SOURCE[0]}" "$tmp/メッセージ定義書.md" "$tmp/out.json" >/dev/null 2>&1; then
    count="$(jq '.units | length' "$tmp/out.json" 2>/dev/null || echo -1)"
    if [ "$count" = "2" ]; then
      echo "PASS: 正常系（5列テーブル2件からunits 2件抽出）で終了コード0"; pass=$((pass + 1))
    else
      echo "FAIL: unitsの件数が2件ではない（実測=${count}）"; fail=$((fail + 1))
    fi
  else
    echo "FAIL: 正常系で終了コード0になるべき"; fail=$((fail + 1))
  fi

  if bash "${BASH_SOURCE[0]}" "$tmp/存在しない定義書.md" "$tmp/out2.json" >/dev/null 2>&1; then
    echo "FAIL: 異常系（入力ファイル不在）で終了コード1になるべき"; fail=$((fail + 1))
  else
    echo "PASS: 異常系（入力ファイル不在）で終了コード1"; pass=$((pass + 1))
  fi

  # 出力-絶対パス不在: sourceDirに入力ファイルの格納先ディレクトリ($tmp)の絶対パスが残らないこと
  if [ -f "$tmp/out.json" ] \
    && ! jq -r '.sourceDir' "$tmp/out.json" | grep -qF -- "$tmp" \
    && jq -e '.sourceDir | test("^/") | not' "$tmp/out.json" >/dev/null 2>&1; then
    echo "PASS: 出力-絶対パス不在（sourceDirに出力先環境の絶対パスが含まれない）"; pass=$((pass + 1))
  else
    echo "FAIL: 出力-絶対パス不在（sourceDirに絶対パスが残っている）"; fail=$((fail + 1))
  fi

  echo "self-test: $pass PASS, $fail FAIL"
  if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
fi

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
# sourceDirは出力先環境の絶対パスを焼き込まない(改善課題1-102の正規化方針に合わせ、
# basenameのみを記録する。メタ表示用であり、実ファイルシステム操作には使わない)。
source_dir="$(basename "$(dirname "$input_file")")"

# パイプテーブル行を抽出し、ヘッダ/セパレータ/プレースホルダ行を除外して
# キー\t文言\t種別\t抽出元\t使用画面 のTSVに変換する
tsv="$(LC_ALL=C awk '
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
  jq -n --arg generatedAt "$generated_at" --arg sourceDir "$source_dir" '{
    sourceDir: $sourceDir, unitKind: "message", generatedAt: $generatedAt,
    strategy: {extractionMethod: "message-definition-table", approvedByUser: false, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {method: "message-definition-table", unitCount: 0, unresolvedCount: 0},
    units: [], summary: {totalCount: 0, byType: {}}
  }' > "$output_file"
  exit 0
fi

units_json="$(printf '%s\n' "$tsv" | jq -R -s '
  split("\n") | map(select(length > 0)) | map(split("\t")) | map({
    unitKey: .[0],
    unitNameGuess: .[1],
    kind: .[2],
    identifier: .[0],
    confidence: "high",
    messageText: .[1],
    messageType: .[2],
    sourceFile: (.[3] | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))),
    usedScreen: .[4]
  })
')"

jq -n \
  --arg generatedAt "$generated_at" \
  --arg sourceDir "$source_dir" \
  --argjson units "$units_json" \
  '
  {
    sourceDir: $sourceDir,
    unitKind: "message",
    generatedAt: $generatedAt,
    strategy: {extractionMethod: "message-definition-table", approvedByUser: false, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {
      method: "message-definition-table",
      unitCount: ($units | length),
      unresolvedCount: ($units | map(select(.kind == "unresolved")) | length)
    },
    units: $units,
    summary: {
      totalCount: ($units | length),
      byType: ($units | group_by(.messageType) | map({key: .[0].messageType, value: length}) | from_entries)
    }
  }
  ' > "$output_file"
