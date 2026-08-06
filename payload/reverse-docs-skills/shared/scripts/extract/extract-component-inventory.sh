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

# 改善課題 1-138: 横断検収条件（本番経路スクリプトへの --self-test 実装）に対応する。
# 必要性: コンポーネント棚卸しの抽出はgenerating-component-inventory-for-reverse-docsの
#   本番経路で使われる決定的な抽出処理であり、正常系（export名・カテゴリ・被参照カウントの
#   抽出）・異常系（source-dir不在）を自己テストで固定しておく。
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-component-inventory-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT

  mkdir -p "$tmp/src/components" "$tmp/src/pages"
  cat > "$tmp/src/components/Foo.tsx" <<'TSX'
type Props = { label: string };
export default function Foo(props: Props) {
  return null;
}
TSX
  cat > "$tmp/src/pages/Home.tsx" <<'TSX'
import Foo from "../components/Foo";
export default function Home() {
  return Foo;
}
TSX

  pass=0 fail=0
  if bash "${BASH_SOURCE[0]}" "$tmp/src" "$tmp/out.json" >/dev/null 2>&1; then
    total="$(jq '.summary.totalComponents' "$tmp/out.json" 2>/dev/null || echo -1)"
    foo_count="$(jq '[.components[] | select(.name == "Foo") | .importCount][0] // -1' "$tmp/out.json" 2>/dev/null)"
    if [ "$total" = "2" ] && [ "$foo_count" = "1" ]; then
      echo "PASS: 正常系（component 2件・Foo importCount=1）で終了コード0"; pass=$((pass + 1))
    else
      echo "FAIL: 抽出結果が期待と異なる（totalComponents=$total, Foo importCount=$foo_count）"; fail=$((fail + 1))
    fi
  else
    echo "FAIL: 正常系で終了コード0になるべき"; fail=$((fail + 1))
  fi

  if bash "${BASH_SOURCE[0]}" "$tmp/存在しないsource" "$tmp/out2.json" >/dev/null 2>&1; then
    echo "FAIL: 異常系（source-dir不在）で終了コード1になるべき"; fail=$((fail + 1))
  else
    echo "PASS: 異常系（source-dir不在）で終了コード1"; pass=$((pass + 1))
  fi

  echo "self-test: $pass PASS, $fail FAIL"
  if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
fi

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

# --- 非UTF-8原本の走査対応(改善課題1-131): detect-encoding.sh の走査ヘルパーを読み込む ---
_EXTRACT_COMPONENT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../detect-encoding.sh
source "$_EXTRACT_COMPONENT_SCRIPT_DIR/../detect-encoding.sh"
SCAN_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/extract-component-inventory-scan.XXXXXX")"

trap 'rm -rf "$TMP_DIR" "$SCAN_WORKDIR"' EXIT

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

  # scan_file: 非UTF-8原本ならUTF-8一時コピー(改善課題1-131)。file自体は出力パス算出に
  # 使うため変更しない。走査(grep)には常にscan_fileを使う
  scan_file="$(to_utf8_for_scan "$file" "$SCAN_WORKDIR")"

  name="$(extract_export_name "$scan_file")"

  hasprops="false"
  if grep -qE 'Props' "$scan_file" 2>/dev/null; then
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
  # ディレクトリ横断の再帰走査は1ファイルずつのUTF-8変換を適用できないため、
  # LC_ALL=C でバイト単位走査にし、非UTF-8原本でも「不正なマルチバイト列」警告と
  # 誤ったバイナリ判定を避ける(改善課題1-131。export名はASCII識別子のためバイト一致で足りる)。
  count="$(LC_ALL=C grep -rlE "import.*\\b${escaped}\\b" \
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
