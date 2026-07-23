#!/usr/bin/env bash
# 抽出エンジン(shared/scripts/extract): DESIGN.md からデザイントークンを抽出し、
# デザインシステムページ用の page-data JSON を出力する。
#
# Usage: extract-design-tokens-from-designmd.sh <DESIGN.md> <output.json>
#
# 入力契約:
#   <DESIGN.md>   : shared/templates/リバース検証/プロジェクト共通/DESIGN.md 準拠のファイル。
#                   先頭に YAML frontmatter（`---` で囲まれたブロック）を持つ想定。
#                   frontmatter は colors: / typography: / components: が
#                   2 スペース固定インデントのネストされたキー: 値、
#                   spacing: / rounded: がスカラー値というテンプレート契約に従う
#                   （facts-schema.md と同様、固定インデント前提の awk パーサで読む）。
#   <output.json> : 出力先パス
#
# 出力契約(<output.json>):
#   {
#     pageKind: "design-system", title: "デザインシステム", generatedAt,
#     tokens: {
#       colors:      [{name, value, role}],
#       typography:  [{name, value, role}],
#       spacing:     [{name, value, role}],   # rounded: も spacing 配列へ合流させる
#       components:  [{name, desc}]
#     },
#     summary: { totalTokens, byCategory: {colors, typography, spacing, components} }
#   }
#
# 抽出手順:
#   1. frontmatter が存在する場合:
#      a. colors: / typography: / components: の 2 スペース indent 配下のキー: 値を読む
#      b. spacing: / rounded: のスカラー値を読み、両方 spacing 配列へ合流させる
#      c. role は frontmatter に存在しないため、本文の Markdown 表（## Colors / ## Typography、
#         列「トークン名 | 用途 | 実測値の抽出元」）からトークン名で突合して補う
#         （表が無い・該当行が無い場合は role を空文字とする。fail ではない）
#      d. components: が 0 件の場合は本文「## Components」表（列「共通コンポーネント | 実装済みの視覚原則」）
#         へフォールバックする（それも 0 件なら components: [] のまま）
#   2. frontmatter が存在しない場合、本文から CSS 変数定義を正規表現フォールバック抽出する
#      （`--color-*` → colors / `--font-*` → typography / `--spacing-*` → spacing。role は空文字。
#      components はフォールバック対象外のため常に [] ）
#
# frontmatter 該当キー 0 件・フォールバック該当 0 件はいずれも正常系
# (該当カテゴリの配列を [] で出力する。fail ではない)。DESIGN.md 自体が存在しない場合のみ exit 1。

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <DESIGN.md> <output.json>" >&2
  exit 1
fi

DESIGN_MD="$1"
OUTPUT_JSON="$2"

if [ ! -f "$DESIGN_MD" ]; then
  echo "Error: DESIGN.md not found: $DESIGN_MD" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_JSON")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TOKENS_TSV="$TMP_DIR/tokens.tsv"       # category \t name \t value \t role
COMPONENTS_TSV="$TMP_DIR/components.tsv" # name \t desc
FRONTMATTER_TXT="$TMP_DIR/frontmatter.txt"
FM_RAW_TSV="$TMP_DIR/fm-raw.tsv"       # section \t name \t value（frontmatter全キー、未フィルタ）
: > "$TOKENS_TSV"
: > "$COMPONENTS_TSV"

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------------------------------------------------------------------------
# has_frontmatter: 先頭行が厳密に "---" かどうかで frontmatter の有無を判定する
# ---------------------------------------------------------------------------
FIRST_LINE="$(head -n1 "$DESIGN_MD" || true)"
HAS_FRONTMATTER=0
if [ "$FIRST_LINE" = "---" ]; then
  HAS_FRONTMATTER=1
fi

# ---------------------------------------------------------------------------
# extract_role_map: 本文の Markdown 表（見出し行 $1、例 "## Colors"）から
#   「トークン名 | 用途 | ...」の先頭2列を name\trole として抽出する。
#   ヘッダ行・区切り行(|---|---|)は tail -n +3 で読み飛ばす。
# ---------------------------------------------------------------------------
extract_role_map() {
  local heading="$1"
  awk -v h="$heading" '
    $0 == h { insec = 1; next }
    insec && /^## / { insec = 0 }
    insec && /^\|/ { print }
  ' "$DESIGN_MD" | tail -n +3 | while IFS= read -r row; do
    name="$(printf '%s' "$row" | awk -F'|' '{print $2}' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/`//g')"
    role="$(printf '%s' "$row" | awk -F'|' '{print $3}' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -z "$name" ] && continue
    printf '%s\t%s\n' "$name" "$role"
  done
}

# ---------------------------------------------------------------------------
# lookup_role: name\trole の対応表($2)から $1 に一致する role を引く。無ければ空文字。
# ---------------------------------------------------------------------------
lookup_role() {
  local name="$1" map="$2" n r
  while IFS=$'\t' read -r n r; do
    if [ "$n" = "$name" ]; then
      printf '%s' "$r"
      return 0
    fi
  done <<< "$map"
  printf ''
}

if [ "$HAS_FRONTMATTER" -eq 1 ]; then
  # 1行目・2行目の "---" に挟まれた本体を取り出す
  awk 'BEGIN{c=0} /^---[ \t]*$/{c++; if(c==2){exit} else {next}} c==1{print}' "$DESIGN_MD" > "$FRONTMATTER_TXT"

  # frontmatter 固定インデント(2スペース)パーサ。
  #   トップレベル "key:"(値なし) → section 見出し(colors: / typography: / components:)
  #   トップレベル "key: value"   → スカラーキー(spacing: / rounded: 等)。section=name=key
  #   "  key: value"(2スペース)  → section 配下のネストキー
  awk '
    /^[A-Za-z0-9_-]+:[[:space:]]*$/ {
      cursec = $0
      sub(/:[[:space:]]*$/, "", cursec)
      next
    }
    /^[A-Za-z0-9_-]+:/ {
      key = $0
      sub(/:.*/, "", key)
      val = $0
      sub(/^[^:]+:[[:space:]]*/, "", val)
      gsub(/^"|"$/, "", val)
      printf "%s\t%s\t%s\n", key, key, val
      cursec = ""
      next
    }
    /^  [A-Za-z0-9_.-]+:/ {
      if (cursec != "") {
        line = $0
        sub(/^  /, "", line)
        key = line
        sub(/:.*/, "", key)
        val = line
        sub(/^[^:]+:[[:space:]]*/, "", val)
        gsub(/^"|"$/, "", val)
        printf "%s\t%s\t%s\n", cursec, key, val
      }
      next
    }
  ' "$FRONTMATTER_TXT" > "$FM_RAW_TSV" || true

  COLOR_ROLE_MAP="$(extract_role_map "## Colors" || true)"
  TYPOGRAPHY_ROLE_MAP="$(extract_role_map "## Typography" || true)"

  # colors / typography: fm-raw から section 一致行を抽出し role を突合する
  while IFS=$'\t' read -r section name value; do
    [ "$section" = "colors" ] || continue
    role="$(lookup_role "$name" "$COLOR_ROLE_MAP")"
    printf 'colors\t%s\t%s\t%s\n' "$name" "$value" "$role" >> "$TOKENS_TSV"
  done < "$FM_RAW_TSV"

  while IFS=$'\t' read -r section name value; do
    [ "$section" = "typography" ] || continue
    role="$(lookup_role "$name" "$TYPOGRAPHY_ROLE_MAP")"
    printf 'typography\t%s\t%s\t%s\n' "$name" "$value" "$role" >> "$TOKENS_TSV"
  done < "$FM_RAW_TSV"

  # spacing: spacing: 自体（スカラー or ネスト）と rounded: を合流させる。role は無し(空文字)
  while IFS=$'\t' read -r section name value; do
    if [ "$section" = "spacing" ] || [ "$section" = "rounded" ]; then
      printf 'spacing\t%s\t%s\t\n' "$name" "$value" >> "$TOKENS_TSV"
    fi
  done < "$FM_RAW_TSV"

  # components: frontmatter 側にキーがあれば name\tdesc として採用
  while IFS=$'\t' read -r section name value; do
    [ "$section" = "components" ] || continue
    printf '%s\t%s\n' "$name" "$value" >> "$COMPONENTS_TSV"
  done < "$FM_RAW_TSV"

  # frontmatter に components が 0 件なら本文「## Components」表へフォールバックする
  if [ ! -s "$COMPONENTS_TSV" ]; then
    awk '
      $0 == "## Components" { insec = 1; next }
      insec && /^## / { insec = 0 }
      insec && /^\|/ { print }
    ' "$DESIGN_MD" | tail -n +3 | while IFS= read -r row; do
      cname="$(printf '%s' "$row" | awk -F'|' '{print $2}' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/`//g')"
      cdesc="$(printf '%s' "$row" | awk -F'|' '{print $3}' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/`//g')"
      [ -z "$cname" ] && continue
      printf '%s\t%s\n' "$cname" "$cdesc" >> "$COMPONENTS_TSV"
    done
  fi
else
  # frontmatter 不在: 本文の CSS 変数定義から正規表現フォールバック抽出する(role は空文字)
  extract_css_vars() {
    local prefix="$1" category="$2"
    grep -oE -- "--${prefix}-[A-Za-z0-9_-]+[[:space:]]*:[[:space:]]*[^;]+" "$DESIGN_MD" 2>/dev/null | while IFS= read -r decl; do
      varname="$(printf '%s' "$decl" | sed -E 's/[[:space:]]*:.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
      value="$(printf '%s' "$decl" | sed -E 's/^[^:]+:[[:space:]]*//; s/[[:space:]]+$//')"
      [ -z "$varname" ] && continue
      printf '%s\t%s\t%s\t\n' "$category" "$varname" "$value" >> "$TOKENS_TSV"
    done
    return 0
  }
  extract_css_vars "color" "colors" || true
  extract_css_vars "font" "typography" || true
  extract_css_vars "spacing" "spacing" || true
fi

# ---------------------------------------------------------------------------
# 最終 JSON 組み立て
# ---------------------------------------------------------------------------
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --rawfile tokensRaw "$TOKENS_TSV" \
  --rawfile componentsRaw "$COMPONENTS_TSV" \
  '
  ($tokensRaw
    | rtrimstr("\n")
    | (if length == 0 then [] else split("\n") end)
    | map(select(length > 0) | split("\t") | {category: .[0], name: .[1], value: .[2], role: (.[3] // "")})
  ) as $rows
  |
  ($componentsRaw
    | rtrimstr("\n")
    | (if length == 0 then [] else split("\n") end)
    | map(select(length > 0) | split("\t") | {name: .[0], desc: (.[1] // "")})
  ) as $components
  |
  ([$rows[] | select(.category == "colors") | {name, value, role}]) as $colors
  |
  ([$rows[] | select(.category == "typography") | {name, value, role}]) as $typography
  |
  ([$rows[] | select(.category == "spacing") | {name, value, role}]) as $spacing
  |
  {
    pageKind: "design-system",
    title: "デザインシステム",
    generatedAt: $generatedAt,
    tokens: {
      colors: $colors,
      typography: $typography,
      spacing: $spacing,
      components: $components
    },
    summary: {
      totalTokens: (($colors | length) + ($typography | length) + ($spacing | length) + ($components | length)),
      byCategory: {
        colors: ($colors | length),
        typography: ($typography | length),
        spacing: ($spacing | length),
        components: ($components | length)
      }
    }
  }
  ' > "$OUTPUT_JSON"
