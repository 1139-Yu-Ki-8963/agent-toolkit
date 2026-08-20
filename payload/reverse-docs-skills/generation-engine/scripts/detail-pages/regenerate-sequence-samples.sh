#!/usr/bin/env bash
# regenerate-sequence-samples.sh — シーケンス図サンプル5件を決定的に再生成する
#
# 使い方:
#   bash regenerate-sequence-samples.sh [<出力先のポータルルート>]
#
# 入力: generation-engine/samples/docs/design/screens/screen-<キー>/シーケンス図-data.json（5件）
# テンプレート: delivery-payload/templates/screen-sequence-template.html
# 出力: <ポータルルート>/画面/screen-<キー>/シーケンス図.html
#
# 出力先の既定値は output-layout.sh（resolve_output_layout / output_layout_get）で
# 解決する。直書きしない（regenerate-semantic-glossary-sample.sh が既定値を直書きして
# 実在しない置き場を指した不具合を繰り返さないため）。
#
# {{PROJECT_NAME}}・{{GENERATED_DATE}}・{{COMMIT_SHORT}}・{{PORTAL_INDEX_HREF}}・
# {{SCREEN_LABEL}}・doc_sidebar_html（左サイドバーの操作ナビ）は、リポジトリ既定の
# 出力先（generation-engine/samples/project-portal/画面/screen-<キー>/シーケンス図.html）に
# 既にコミット済みのサンプルから読み取って引き継ぐ。新しい値を発明しない。
#
# 設計判断（ADR）の正本は .claude/rules/scoped/portal/page-conventions/rule.md の
# 「## 設計判断」内「### regenerate-sequence-samples.sh」に記載する。
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

samples_dir="$repo_root/generation-engine/samples"

source "$script_dir/../output-layout.sh"
layout="$(resolve_output_layout "$samples_dir")"
portal_root_rel="$(output_layout_get "$layout" portalRoot)"
screen_unit_root_rel="$(output_layout_get "$layout" screenUnitRoot)"
screen_view_root_rel="$(output_layout_get "$layout" screenViewRoot)"
screen_view_suffix="${screen_view_root_rel#"$portal_root_rel"/}"

default_portal_root="$samples_dir/$portal_root_rel"
portal_root="${1:-$default_portal_root}"

unit_data_root="$samples_dir/$screen_unit_root_rel"
canonical_view_root="$default_portal_root/$screen_view_suffix"

source "$script_dir/../render-template.sh"
. "$script_dir/../shell-injection.sh"

template_file="$repo_root/delivery-payload/templates/screen-sequence-template.html"
tokens_css_file="$repo_root/delivery-payload/templates/tokens.css"
templates_dir="$repo_root/delivery-payload/templates"
catalog_file="$repo_root/delivery-payload/references/portal-catalog.json"

extract_reference_values() {
  # 既存サンプルから PROJECT_NAME・GENERATED_DATE・COMMIT_SHORT・PORTAL_INDEX_HREF・
  # SCREEN_LABEL・doc_sidebar_html（<nav class="pt-doc-nav">...</nav> 全体）を
  # 読み取る。bash の grep/sed だけでは複数行にまたがる抽出が環境（GNU/BSD）で
  # ぶれるため python3 で確実に抜き出す。
  python3 - "$1" <<'PY'
import json
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    html = f.read()


def find(pattern):
    m = re.search(pattern, html, re.S)
    if not m:
        sys.exit(f"ERROR: 既存サンプルから値を抽出できません（パターン未一致）: {pattern}")
    return m.group(1)


project_name = find(r'pt-brand-name">([^<]*)<')
generated_date = find(r'pt-sidebar-date">([^<]*)<')
commit_short = find(r'pt-meta-commit"><br>コミット ([^<]*)</span>').strip()
portal_index_href = find(r'data-portal-href="([^"]*)"')
screen_label = find(r'<h1 class="pt-title">([^<]*) のシーケンス図</h1>')
doc_sidebar_html = find(r'(<nav class="pt-doc-nav".*?</nav>)')

print(json.dumps({
    "projectName": project_name,
    "generatedDate": generated_date,
    "commitShort": commit_short,
    "portalIndexHref": portal_index_href,
    "screenLabel": screen_label,
    "docSidebarHtml": doc_sidebar_html,
}))
PY
}

count=0
for data_file in "$unit_data_root"/screen-*/シーケンス図-data.json; do
  [ -f "$data_file" ] || continue

  screen_dir="$(dirname "$data_file")"
  screen_key="$(basename "$screen_dir")"

  reference_html="$canonical_view_root/$screen_key/シーケンス図.html"
  if [ ! -f "$reference_html" ]; then
    echo "ERROR: 値の引き継ぎ元となる既存サンプルが見つかりません: $reference_html" >&2
    exit 1
  fi

  reference_json="$(extract_reference_values "$reference_html")"
  project_name="$(jq -r '.projectName' <<<"$reference_json")"
  generated_date="$(jq -r '.generatedDate' <<<"$reference_json")"
  commit_short="$(jq -r '.commitShort' <<<"$reference_json")"
  portal_index_href="$(jq -r '.portalIndexHref' <<<"$reference_json")"
  screen_label="$(jq -r '.screenLabel' <<<"$reference_json")"
  doc_sidebar_html="$(jq -r '.docSidebarHtml' <<<"$reference_json")"

  view_dir="$portal_root/$screen_view_suffix/$screen_key"
  out_html="$view_dir/シーケンス図.html"

  template="$(cat "$template_file")"
  tokens_css="$(cat "$tokens_css_file")"
  page_data="$(cat "$data_file")"

  render_args=(
    "{{PROJECT_NAME}}" "$project_name" \
    "{{GENERATED_DATE}}" "$generated_date" \
    "{{COMMIT_SHORT}}" "$commit_short" \
    "{{PORTAL_INDEX_HREF}}" "$portal_index_href" \
    "{{SCREEN_LABEL}}" "$screen_label" \
    "/* TOKENS_CSS */" "$tokens_css" \
    "{{PAGE_DATA_JSON}}" "$page_data"
  )
  shell_injection_args "$templates_dir" "$catalog_file" "$portal_index_href" "$project_name" "$generated_date" "$commit_short" "generating-sequence-diagram-for-reverse-docs" "list" "" "" "$view_dir" "$doc_sidebar_html"
  if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
    render_args+=("${SHELL_RENDER_ARGS[@]}")
  fi

  out="$(render_template "$template" "${render_args[@]}")"
  mkdir -p "$view_dir"
  printf '%s\n' "$out" > "$out_html"
  printf 'generated: %s\n' "$out_html"
  count=$((count + 1))
done

if [ "$count" -eq 0 ]; then
  echo "ERROR: 入力データ（シーケンス図-data.json）が1件も見つかりません: $unit_data_root" >&2
  exit 1
fi
