#!/usr/bin/env bash
# shell_injection_args — 共通シェル(partials)を render_template のマーカー引数へ展開する共通関数
#
# Usage:
#   source "path/to/render-template.sh"
#   source "path/to/shell-injection.sh"
#   shell_injection_args <templates_dir> <catalog_json> <portal_href> <project_name> \
#                        <generated_date> <commit_short> <generator> [active_category]
#   render_args+=("${SHELL_RENDER_ARGS[@]}")
#
# 展開するマーカーは 3 つ。
#   /* SHELL_CSS */      -> partials/shell.css の全文
#   <!--SHELL_SIDEBAR--> -> partials/shell-sidebar.html（内部のプレースホルダを解決済み）
#   <!--SHELL_FOOTER-->  -> partials/shell-footer.html（同上）
#
# サイドバー内の /*SHELL_NAV_JSON*/ には、カタログのカテゴリ一覧から組み立てた JSON を差し込む。
# 各要素は key（カテゴリキー）・num（01 始まりの通し番号）・label（表示名）・count（資料数）を持つ。
# 資料数はカタログの定義から数えるため、生成済みページの有無に依存しない。
#
# partials が 1 つでも欠けている場合は SHELL_RENDER_ARGS を空にして戻る。
# 呼び出し側のテンプレートにマーカーが無い場合も render_template は素通りするため、
# 移行途中のテンプレートが混在していても壊れない。

SHELL_RENDER_ARGS=()

shell_injection_args() {
  local templates_dir="$1"
  local catalog="$2"
  local portal_href="$3"
  local project_name="$4"
  local generated_date="$5"
  local commit_short="$6"
  local generator="$7"
  local active_category="${8:-}"

  local partials_dir="$templates_dir/partials"
  local css_file="$partials_dir/shell.css"
  local sidebar_file="$partials_dir/shell-sidebar.html"
  local footer_file="$partials_dir/shell-footer.html"

  SHELL_RENDER_ARGS=()
  [ -f "$css_file" ] || return 0
  [ -f "$sidebar_file" ] || return 0
  [ -f "$footer_file" ] || return 0

  local nav_json total
  if [ -f "$catalog" ]; then
    nav_json="$(jq -c '[.categories | to_entries[] | {
      key: .value.key,
      num: ((.key + 1) | tostring | if length < 2 then "0" + . else . end),
      label: .value.label,
      count: (.value.blueprints | length)
    }]' "$catalog")"
    total="$(jq -r '[.categories[].blueprints | length] | add // 0' "$catalog")"
  else
    nav_json='[]'
    total='0'
  fi

  # 埋め込み JSON から script 要素を抜け出せないようにする（他ビルダーと同じ無害化）
  nav_json="$(printf '%s' "$nav_json" | sed 's/</\\u003c/g; s/>/\\u003e/g; s/&/\\u0026/g')"

  local sidebar footer
  sidebar="$(cat "$sidebar_file")"
  footer="$(cat "$footer_file")"

  sidebar="$(render_template "$sidebar" \
    "/*SHELL_NAV_JSON*/" "$nav_json" \
    "{{PORTAL_HREF}}" "$portal_href" \
    "{{ACTIVE_CATEGORY}}" "$active_category" \
    "{{PROJECT_NAME}}" "$project_name" \
    "{{TOTAL_ARTIFACTS}}" "$total" \
    "{{GENERATED_DATE}}" "$generated_date" \
    "{{COMMIT_SHORT}}" "$commit_short")"

  footer="$(render_template "$footer" \
    "{{PROJECT_NAME}}" "$project_name" \
    "{{GENERATED_DATE}}" "$generated_date" \
    "{{COMMIT_SHORT}}" "$commit_short" \
    "{{GENERATOR}}" "$generator")"

  SHELL_RENDER_ARGS=(
    "/* SHELL_CSS */" "$(cat "$css_file")"
    "<!--SHELL_SIDEBAR-->" "$sidebar"
    "<!--SHELL_FOOTER-->" "$footer"
  )
}
