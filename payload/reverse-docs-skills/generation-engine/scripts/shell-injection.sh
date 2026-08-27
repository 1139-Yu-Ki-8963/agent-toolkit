#!/usr/bin/env bash
# shell_injection_args — 共通シェル(partials)を render_template のマーカー引数へ展開する共通関数
#
# Usage:
#   source "path/to/render-template.sh"
#   source "path/to/shell-injection.sh"
#   shell_injection_args <templates_dir> <catalog_json> <portal_href> <project_name> \
#                        <generated_date> <commit_short> <generator> [active_category] \
#                        [sites_json_path] [current_site_key] [current_page_dir] \
#                        [doc_sidebar_html] [shell_counts_json]
#   render_args+=("${SHELL_RENDER_ARGS[@]}")
#
# 展開するマーカーは 3 つ。
#   /* SHELL_CSS */      -> partials/shell.css の全文
#   <!--SHELL_SIDEBAR--> -> partials/shell-sidebar.html（内部のプレースホルダを解決済み）
#   <!--SHELL_FOOTER-->  -> partials/shell-footer.html（同上）
#
# サイドバー内の /*SHELL_NAV_JSON*/ には、カタログのカテゴリ一覧から組み立てた JSON を差し込む。
# 各要素は key（カテゴリキー）・num（01 始まりの通し番号）・label（表示名）・count（資料数）を持つ。
# 13 番目の shell_counts_json（`[{"key":"<カテゴリキー>","count":<実カード数>},...]` 形式）が
# 指定された場合、count と総資料数（{{TOTAL_ARTIFACTS}}）はその値を使う。
# discovery で実在が確認されたカード数を単一の情報源として揃えるための引数であり、
# 未指定（空文字）の場合は従来どおりカタログの blueprints 数を数える（後方互換）。
#
# サイドバー内の /*SHELL_SITES_JSON*/ には、モノレポ複数サイトの切替候補一覧を差し込む。
# 9 番目の sites_json_path（納品ルート直下の sites.json）・10 番目の current_site_key・
# 11 番目の current_page_dir（生成中ページのディレクトリの絶対パス）のいずれも省略可能で、
# 省略時（または current_page_dir 省略時）はサイト一覧を空配列にし、切替 UI を出さない。
# sites_json_path が指定されているのにファイルの形式が壊れている場合は ERROR を出して
# return 1 する（fail-fast。他の入力欠落は fail-open）。
#
# サイドバー内の {{DOC_SIDEBAR}} には、12 番目の doc_sidebar_html（文書ビューア型ページの
# 章目次ブロックの HTML。未指定なら空文字）を差し込む。共通サイドバーへ統合済みの
# ページ固有 TOC（旧 .dp-toc）はここで注入する。
#
# partials が 1 つでも欠けている場合は SHELL_RENDER_ARGS を空にして戻る。
# 呼び出し側のテンプレートにマーカーが無い場合も render_template は素通りするため、
# 移行途中のテンプレートが混在していても壊れない。
#
# 集約の対象外: 本ファイルは source される共通関数ライブラリで
# あり、単体で実行される本番経路のスクリプトではない（トップレベルの引数解析・実行文を
# 持たない）。回帰検証は本関数を source する各consumer（build-portal.sh 等）自身の
# --self-test を通じて間接的に行うのが基本だが、改善課題 1-156 により doc_nav（二重引用符を
# 含む HTML 文字列）をファイル経由で安全に受け渡せることを検証する self-test を本ファイルにも
# 追加した（直接 `bash shell-injection.sh --self-test` で実行した場合のみ発火し、他スクリプトに
# source された際は発火しない。詳細は下記ガード条件を参照）。

if [ "${BASH_SOURCE[0]}" = "$0" ] && [ "${1:-}" = "--self-test" ]; then
  # 改善課題 1-156: generating-sequence-diagram-for-reverse-docs の Step 3-1 は、
  # 二重引用符を含む doc_nav（戻るリンク・設計書項目のナビHTML）を、単一引用符の
  # bash -c スクリプト内へ文字列結合で埋め込まず、ファイル経由（cat）で読み込む形に
  # 修正した。本 self-test はその手順を再現し、(1) 生成が停止せず終了コード0で完了する
  # こと (2) ナビゲーションの表示テキストが出力に実在すること、の2点を検証する。
  self_test() {
    local script_dir pass=0 fail=0 tmp
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/shell-injection-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
      echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
      exit 2
    fi
    trap 'rm -rf "$tmp"' EXIT

    mkdir -p "$tmp/partials"
    printf '.pt-sidebar{}\n' > "$tmp/partials/shell.css"
    printf '<nav class="pt-sidebar">{{DOC_SIDEBAR}}</nav>\n' > "$tmp/partials/shell-sidebar.html"
    printf '<footer>{{PROJECT_NAME}}/{{GENERATED_DATE}}/{{COMMIT_SHORT}}/{{GENERATOR}}</footer>\n' > "$tmp/partials/shell-footer.html"

    # 二重引用符を含む doc_nav フィクスチャ（実データの戻るリンク・nav-item を模す）
    cat > "$tmp/doc-nav-quoted.html" <<'NAV'
<a class="back-link" href="../../一覧/画面一覧/画面一覧.html">← 画面一覧へ戻る</a><a class="nav-item" href="基本設計/画面基本設計書.html">基本設計</a>
NAV
    # 引用符を含まない doc_nav フィクスチャ（従来ケースの回帰確認用）
    printf 'plain-nav-without-quotes' > "$tmp/doc-nav-plain.html"

    # doc_nav をファイル経由（cat）で読み込み、shell_injection_args → render_template の
    # 実経路を通す。script_dir・doc_nav_file・tmp はすべて位置引数($1/$2/$3)として渡し、
    # スクリプト本文の文字列へは一切結合しない（1-156 が禁止する「文字列結合での埋め込み」を
    # self-test 自身が再現しないため）。
    local out rc
    out="$(
      bash -c '
        set -e
        script_dir="$1"; doc_nav_file="$2"; work="$3"
        source "$script_dir/render-template.sh"
        . "$script_dir/shell-injection.sh"
        doc_nav="$(cat "$doc_nav_file")"
        doc_sidebar_html="<div class=\"pt-doc-nav__group\">画面 / 設計書</div>${doc_nav}"
        shell_injection_args "$work" "$work/nonexistent-catalog.json" "index.html" "テストプロジェクト" "2026-07-31" "" "generator" "" "" "" "" "$doc_sidebar_html"
        if [ ${#SHELL_RENDER_ARGS[@]} -eq 0 ]; then
          echo "EMPTY_SHELL_RENDER_ARGS" >&2
          exit 1
        fi
        render_template "<html>/* SHELL_CSS */<!--SHELL_SIDEBAR--><!--SHELL_FOOTER--></html>" "${SHELL_RENDER_ARGS[@]}"
      ' _ "$script_dir" "$tmp/doc-nav-quoted.html" "$tmp"
    )"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      echo "PASS: 二重引用符を含むdoc_navでも生成が停止せず終了コード0" >&2
      pass=$((pass + 1))
    else
      echo "FAIL: 二重引用符を含むdoc_navで終了コード0にならない（rc=${rc}）" >&2
      fail=$((fail + 1))
    fi
    case "$out" in
      *"画面一覧へ戻る"*)
        echo "PASS: ナビゲーションの表示テキストが出力に実在する" >&2
        pass=$((pass + 1))
        ;;
      *)
        echo "FAIL: ナビゲーションの表示テキストが出力から欠落している" >&2
        fail=$((fail + 1))
        ;;
    esac

    local out_plain rc_plain
    out_plain="$(
      bash -c '
        set -e
        script_dir="$1"; doc_nav_file="$2"; work="$3"
        source "$script_dir/render-template.sh"
        . "$script_dir/shell-injection.sh"
        doc_nav="$(cat "$doc_nav_file")"
        doc_sidebar_html="<div class=\"pt-doc-nav__group\">画面 / 設計書</div>${doc_nav}"
        shell_injection_args "$work" "$work/nonexistent-catalog.json" "index.html" "テストプロジェクト" "2026-07-31" "" "generator" "" "" "" "" "$doc_sidebar_html"
        render_template "<html>/* SHELL_CSS */<!--SHELL_SIDEBAR--><!--SHELL_FOOTER--></html>" "${SHELL_RENDER_ARGS[@]}"
      ' _ "$script_dir" "$tmp/doc-nav-plain.html" "$tmp"
    )"
    rc_plain=$?
    if [ "$rc_plain" -eq 0 ] && case "$out_plain" in *"plain-nav-without-quotes"*) true ;; *) false ;; esac; then
      echo "PASS: 引用符を含まないdoc_navも従来どおり生成できる" >&2
      pass=$((pass + 1))
    else
      echo "FAIL: 引用符を含まないdoc_navの回帰生成に失敗した（rc=${rc_plain}）" >&2
      fail=$((fail + 1))
    fi

    echo "self-test: ${pass} PASS, ${fail} FAIL" >&2
    [ "$fail" -eq 0 ]
  }
  if self_test; then exit 0; else exit 1; fi
fi

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
  local doc_sidebar_html="${12:-}"
  local shell_counts_json="${13:-}"

  local partials_dir="$templates_dir/partials"
  local css_file="$partials_dir/shell.css"
  local sidebar_file="$partials_dir/shell-sidebar.html"
  local footer_file="$partials_dir/shell-footer.html"

  SHELL_RENDER_ARGS=()
  [ -f "$css_file" ] || return 0
  [ -f "$sidebar_file" ] || return 0
  [ -f "$footer_file" ] || return 0

  local active_category_label
  if [ -f "$catalog" ] && [ -n "$active_category" ]; then
    active_category_label="$(jq -r --arg key "$active_category" '(.categories[] | select(.key == $key) | .label) // empty' "$catalog" 2>/dev/null)"
  fi
  # カテゴリキーが解決できない場合（catalog不在・キー未指定・catalog内に該当キーなし）の既定値。
  # 22テンプレート中「一覧・設計図」（listカテゴリ）が最多（9件）のため、既定値もこれに倣う。
  : "${active_category_label:=一覧・設計図}"

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

  if [ -n "$shell_counts_json" ]; then
    nav_json="$(jq -c --argjson counts "$shell_counts_json" '
      ($counts | map({(.key): .count}) | add // {}) as $countByKey
      | map(.count = ($countByKey[.key] // .count))
    ' <<<"$nav_json")"
    total="$(jq -r '[.[].count] | add // 0' <<<"$shell_counts_json")"
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
    "{{COMMIT_SHORT}}" "$commit_short" \
    "{{DOC_SIDEBAR}}" "$doc_sidebar_html")"

  footer="$(render_template "$footer" \
    "{{PROJECT_NAME}}" "$project_name" \
    "{{GENERATED_DATE}}" "$generated_date" \
    "{{COMMIT_SHORT}}" "$commit_short" \
    "{{GENERATOR}}" "$generator")"

  SHELL_RENDER_ARGS=(
    "/* SHELL_CSS */" "$(cat "$css_file")"
    "<!--SHELL_SIDEBAR-->" "$sidebar"
    "<!--SHELL_FOOTER-->" "$footer"
    "{{ACTIVE_CATEGORY_LABEL}}" "$active_category_label"
  )
}
