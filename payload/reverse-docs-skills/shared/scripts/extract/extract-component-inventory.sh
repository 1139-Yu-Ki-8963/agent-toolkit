#!/usr/bin/env bash
# 抽出エンジン: ソースディレクトリ配下のコンポーネントファイルを棚卸しし、
# コンポーネント棚卸しカタログ JSON を出力する。
#
# Usage: extract-component-inventory.sh <source-dir> <output.json>
#
# 入力契約:
#   <source-dir> : 原本ソースのルート。配下を再帰的に find/grep する
#   <output.json>: 出力先パス
#
# 出力契約(<output.json>):
#   {
#     pageKind: "component-inventory", title: "コンポーネント棚卸し", generatedAt,
#     components: [{name, file, category, hasProps, importCount}],
#     summary: {totalComponents, byCategory, topImported}
#   }
#
# 抽出内容(自動分類なし。決定的な抽出のみ):
#   a. 対象ファイル: *.tsx / *.jsx / *.vue（node_modules/.next/dist/build は除外）
#   b. export 名   : export default function/class、export function/const、
#                     export default <bare識別子>; の順に最初の一致を採用。
#                     いずれも一致しない場合はファイル名(拡張子抜き)を使う
#   c. props 型    : ファイル内に "Props" を含む行があれば hasProps=true
#   d. 分類        : ディレクトリパスから導出（components/ pages/ layouts/ 以外は other）
#   e. 被参照カウント: export 名ごとに `import.*<name>` を含むファイル数を数える
#
# コンポーネントファイルが 0 件は正常系(components: [] を出力する。fail ではない)。

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <source-dir> <output.json>" >&2
  exit 1
fi

SOURCE_DIR="$1"
OUTPUT_JSON="$2"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "Error: source-dir not found: $SOURCE_DIR" >&2
  exit 1
fi

# SOURCE_DIR を末尾スラッシュなしの絶対パス相当へ正規化(相対パス表示の起点に使う)
SOURCE_DIR="${SOURCE_DIR%/}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

META_TSV="$TMP_DIR/meta.tsv"
NAMES_TXT="$TMP_DIR/names.txt"
COUNTS_TSV="$TMP_DIR/counts.tsv"
FINAL_TSV="$TMP_DIR/final.tsv"
: > "$META_TSV"
: > "$COUNTS_TSV"
: > "$FINAL_TSV"

# ---------------------------------------------------------------------------
# regex_escape: grep -E に渡す前に正規表現メタ文字をエスケープする
# ---------------------------------------------------------------------------
regex_escape() {
  printf '%s' "$1" | sed -e 's/[.[\*^$()+?{}|\\]/\\&/g'
}

# ---------------------------------------------------------------------------
# derive_category: 相対パスからカテゴリを導出する(自動分類ではなくパス由来の決定的分類)
# ---------------------------------------------------------------------------
derive_category() {
  local relpath="$1"
  case "$relpath" in
    */components/*|components/*) printf 'component' ;;
    */pages/*|pages/*) printf 'page' ;;
    */layouts/*|layouts/*) printf 'layout' ;;
    *) printf 'other' ;;
  esac
}

# ---------------------------------------------------------------------------
# extract_export_name: export default function/class、export function/const、
#   export default <bare識別子>; の順に最初の一致を採用する。
#   いずれも一致しない場合はファイル名(拡張子抜き)を使う
# ---------------------------------------------------------------------------
extract_export_name() {
  local file="$1"
  local name=""

  name="$(grep -m1 -oE 'export default function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$file" 2>/dev/null \
    | grep -oE '[A-Za-z_][A-Za-z0-9_]*$' || true)"

  if [ -z "$name" ]; then
    name="$(grep -m1 -oE 'export default class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$file" 2>/dev/null \
      | grep -oE '[A-Za-z_][A-Za-z0-9_]*$' || true)"
  fi

  if [ -z "$name" ]; then
    name="$(grep -m1 -oE '^export function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$file" 2>/dev/null \
      | grep -oE '[A-Za-z_][A-Za-z0-9_]*$' || true)"
  fi

  if [ -z "$name" ]; then
    name="$(grep -m1 -oE '^export const[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$file" 2>/dev/null \
      | grep -oE '[A-Za-z_][A-Za-z0-9_]*$' || true)"
  fi

  if [ -z "$name" ]; then
    name="$(grep -m1 -oE '^export default[[:space:]]+[A-Za-z_][A-Za-z0-9_]*;' "$file" 2>/dev/null \
      | grep -oE '[A-Za-z_][A-Za-z0-9_]*' | tail -1 || true)"
  fi

  if [ -z "$name" ]; then
    name="$(basename "$file")"
    name="${name%.*}"
  fi

  printf '%s' "$name"
}

# ---------------------------------------------------------------------------
# Pass 1: 対象ファイルごとに name / relpath / category / hasProps を meta.tsv へ書く
# ---------------------------------------------------------------------------
while IFS= read -r -d '' file; do
  relpath="${file#"$SOURCE_DIR"/}"

  name="$(extract_export_name "$file")"

  hasprops="false"
  if grep -qE 'Props' "$file" 2>/dev/null; then
    hasprops="true"
  fi

  category="$(derive_category "$relpath")"

  printf '%s\t%s\t%s\t%s\n' "$name" "$relpath" "$category" "$hasprops" >> "$META_TSV"
done < <(find "$SOURCE_DIR" \
  \( -name node_modules -o -name .next -o -name dist -o -name build \) -prune -o \
  \( -name '*.tsx' -o -name '*.jsx' -o -name '*.vue' \) -type f -print0)

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ ! -s "$META_TSV" ]; then
  jq -n \
    --arg generatedAt "$GENERATED_AT" \
    '{
      pageKind: "component-inventory",
      title: "コンポーネント棚卸し",
      generatedAt: $generatedAt,
      components: [],
      summary: {
        totalComponents: 0,
        byCategory: { component: 0, page: 0, layout: 0, other: 0 },
        topImported: []
      }
    }' > "$OUTPUT_JSON"
  exit 0
fi

# ---------------------------------------------------------------------------
# Pass 2: export 名ごとの被参照カウント(import.*<name> を含むファイル数)を数える
# ---------------------------------------------------------------------------
cut -f1 "$META_TSV" | sort -u > "$NAMES_TXT"

while IFS= read -r name; do
  [ -z "$name" ] && continue
  escaped="$(regex_escape "$name")"
  count="$(grep -rlE "import.*\\b${escaped}\\b" \
    --include='*.tsx' --include='*.jsx' --include='*.ts' \
    "$SOURCE_DIR" 2>/dev/null | wc -l | tr -d ' ' || true)"
  [ -z "$count" ] && count=0
  printf '%s\t%s\n' "$name" "$count" >> "$COUNTS_TSV"
done < "$NAMES_TXT"

# ---------------------------------------------------------------------------
# Pass 3: meta.tsv と counts.tsv を name で突合し final.tsv を組み立てる
# ---------------------------------------------------------------------------
declare -A COUNT_MAP
while IFS=$'\t' read -r name count; do
  COUNT_MAP["$name"]="$count"
done < "$COUNTS_TSV"

while IFS=$'\t' read -r name relpath category hasprops; do
  count="${COUNT_MAP[$name]:-0}"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$relpath" "$category" "$hasprops" "$count" >> "$FINAL_TSV"
done < "$META_TSV"

# final.tsv: name \t file \t category \t hasProps \t importCount
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --rawfile raw "$FINAL_TSV" \
  '
  ($raw
    | rtrimstr("\n")
    | split("\n")
    | map(select(length > 0) | split("\t") | {
        name: .[0],
        file: .[1],
        category: .[2],
        hasProps: (.[3] == "true"),
        importCount: (.[4] | tonumber)
      })
    | sort_by(-.importCount, .name)
  ) as $components
  |
  {
    pageKind: "component-inventory",
    title: "コンポーネント棚卸し",
    generatedAt: $generatedAt,
    components: $components,
    summary: {
      totalComponents: ($components | length),
      byCategory: (
        { component: 0, page: 0, layout: 0, other: 0 }
        + ($components | group_by(.category) | map({key: .[0].category, value: length}) | from_entries)
      ),
      topImported: (
        $components
        | map({name: .name, count: .importCount})
        | .[0:10]
      )
    }
  }
  ' > "$OUTPUT_JSON"
