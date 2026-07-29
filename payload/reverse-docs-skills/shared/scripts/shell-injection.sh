#!/usr/bin/env bash
# shell_injection_args — 共通シェル(partials)を render_template のマーカー引数へ展開する共通関数
#
# Usage:
#   source "path/to/render-template.sh"
#   source "path/to/shell-injection.sh"
#   shell_injection_args <templates_dir> <catalog_json> <portal_href> <project_name> \
#                        <generated_date> <commit_short> <generator> [active_category] \
#                        [sites_json_path] [current_site_key] [current_page_dir]
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
# サイドバー内の /*SHELL_SITES_JSON*/ には、モノレポ複数サイトの切替候補一覧を差し込む。
# 9 番目の sites_json_path（納品ルート直下の sites.json）・10 番目の current_site_key・
# 11 番目の current_page_dir（生成中ページのディレクトリの絶対パス）のいずれも省略可能で、
# 省略時（または current_page_dir 省略時）はサイト一覧を空配列にし、切替 UI を出さない。
# sites_json_path が指定されているのにファイルの形式が壊れている場合は ERROR を出して
# return 1 する（fail-fast。他の入力欠落は fail-open）。
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
  local sites_json_path="${9:-}"
  local current_site_key="${10:-}"
  local current_page_dir="${11:-}"

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

  local sites_json='[]'
  if [ -n "$sites_json_path" ] && [ -f "$sites_json_path" ]; then
    if ! jq -e '.specVersion == 1' "$sites_json_path" >/dev/null 2>&1; then
      echo "ERROR: sites.json specVersion must be 1: $sites_json_path" >&2
      return 1
    fi
    if ! jq -e '(.sites | type) == "array" and (.sites | length) >= 1' "$sites_json_path" >/dev/null 2>&1; then
      echo "ERROR: sites.json .sites must be a non-empty array: $sites_json_path" >&2
      return 1
    fi
    if ! jq -e '[.sites[] | (has("key") and has("label") and has("root"))] | all' "$sites_json_path" >/dev/null 2>&1; then
      echo "ERROR: sites.json each site must have key/label/root: $sites_json_path" >&2
      return 1
    fi
    if ! jq -e '(.sites | map(.key) | length) == (.sites | map(.key) | unique | length)' "$sites_json_path" >/dev/null 2>&1; then
      echo "ERROR: sites.json site keys must be unique: $sites_json_path" >&2
      return 1
    fi
    if ! jq -e '[.sites[] | (.root | type == "string" and (startswith("/") | not) and (contains("..") | not))] | all' "$sites_json_path" >/dev/null 2>&1; then
      echo "ERROR: sites.json each root must be a relative path (no leading / or ..): $sites_json_path" >&2
      return 1
    fi

    if [ -n "$current_page_dir" ]; then
      if ! command -v python3 >/dev/null 2>&1; then
        echo "ERROR: python3 is required to resolve sites.json relative links" >&2
        return 1
      fi
      sites_json="$(python3 -c '
import json
import os
import sys

sites_json_path, current_site_key, current_page_dir = sys.argv[1:4]
with open(sites_json_path, encoding="utf-8") as f:
    data = json.load(f)
sites_root = os.path.dirname(os.path.abspath(sites_json_path))
page_dir = os.path.abspath(current_page_dir)

result = []
for site in data["sites"]:
    target = os.path.join(sites_root, site["root"], "index.html")
    href = os.path.relpath(target, page_dir).replace(os.sep, "/")
    result.append({
        "key": site["key"],
        "label": site["label"],
        "href": href,
        "current": site["key"] == current_site_key,
    })
sys.stdout.write(json.dumps(result))
' "$sites_json_path" "$current_site_key" "$current_page_dir")"
    fi
  fi

  # 埋め込み JSON から script 要素を抜け出せないようにする（nav_json と同じ無害化）
  sites_json="$(printf '%s' "$sites_json" | sed 's/</\\u003c/g; s/>/\\u003e/g; s/&/\\u0026/g')"

  local sidebar footer
  sidebar="$(cat "$sidebar_file")"
  footer="$(cat "$footer_file")"

  sidebar="$(render_template "$sidebar" \
    "/*SHELL_NAV_JSON*/" "$nav_json" \
    "/*SHELL_SITES_JSON*/" "$sites_json" \
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
