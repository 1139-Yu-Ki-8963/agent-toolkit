#!/usr/bin/env bash
# 抽出エンジン: 画面テスト設計書(Markdown)群からテスト観点manifest(JSON)への横断集約。
# output_dir 配下の <screenUnitRoot>/screen-*/テスト設計/{画面単体テスト設計書.md,画面テスト設計書.md} を
# 優先して走査し、旧詳細設計配下の観点表は新配置がない場合だけ後方互換として集約する。
#
# Usage: aggregate-test-viewpoints.sh <output_dir> <output.json>
#
# 入力契約:
#   <output_dir> : <screenUnitRoot>/screen-<ID>/テスト設計/画面単体テスト設計書.md および
#                 画面テスト設計書.md を含むディレクトリツリーのルート。新配置がない既存生成物では
#                 詳細設計/単体テスト観点表.md・結合テスト観点表.mdを後方互換として読む
#   <output.json> : 出力先パス
#
# 出力契約:
#   {
#     unitKind: "test_viewpoint",
#     generatedAt: string(UTC ISO8601),
#     units: [{ unitKey, screenKey, testType, category, viewpoint }],
#     summary: { totalCount: number, byTestType: {...}, byScreen: {...} }
#   }
#
# パース仕様:
#   - 新体系の画面単体テスト設計書・画面テスト設計書はいずれも1画面単位のためtestType=unitとして扱う
#   - 既存生成物の旧結合テスト観点表だけは後方互換のtestType=integrationを維持する
#   - screenKey はパス中の "screen-" で始まるディレクトリ名をそのまま使う
#   - Markdown の見出し行(#〜######)を「カテゴリ」として保持し、以降のテーブル行に適用する
#   - 標準的な Markdown テーブル（ヘッダ行 + セパレータ行 + データ行）を検出し、
#     ヘッダ列名が「観点」と完全一致（無ければ部分一致）する列をデータ列として抽出する
#   - データ行の1列目が "<...>" 形式（テンプレートのプレースホルダ例示行）のものはスキップする
#   - 観点表が1件も見つからない場合はエラーにせず units:[] で正常終了する(fail-safe)
#
# 終了コード:
#   0 : 正常終了(観点表未検出でも units:[] で正常出力)
#   1 : output_dir 不在、または引数不足

set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <output_dir> <output.json>" >&2
}

self_test() {
  local script_path="$0" script_dir tmp docs manifest html portal manifest_only
  local layout_json screen_unit_root units_root
  if [ -d "${TMPDIR:-/tmp}" ]; then
    TMPDIR="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
    export TMPDIR
  fi
  local api_unit_root
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  # shellcheck source=../output-layout.sh
  source "$script_dir/../output-layout.sh"
  layout_json="$(resolve_output_layout "")" || return 1
  screen_unit_root="$(output_layout_get "$layout_json" screenUnitRoot)" || return 1
  units_root="$(output_layout_get "$layout_json" unitsRoot)" || return 1
  api_unit_root="$(output_layout_get "$layout_json" apiUnitRoot)" || return 1
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/aggregate-test-viewpoints-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  docs="$tmp/docs"
  manifest="$tmp/test-viewpoint-manifest.json"
  html="$docs/$units_root/テスト観点表/テスト観点表.html"
  portal="$tmp/portal"
  manifest_only="$tmp/manifest-only.html"
  has_visible_viewpoint_row() {
    local file="$1" unit_key="$2" viewpoint="$3" screen_key="$4" category="$5"
    awk -v unit_key="$unit_key" -v viewpoint="$viewpoint" -v screen_key="$screen_key" -v category="$category" '
      BEGIN { RS = "</tr>"; found = 0 }
      index($0, "data-unit-key=\"" unit_key "\"") &&
      index($0, "<td>" viewpoint "</td>") &&
      index($0, "<code>" screen_key "</code>") &&
      index($0, ">" category "</span>") { found = 1 }
      END { exit(found ? 0 : 1) }
    ' "$file"
  }
  # フィクスチャの書き込み先は宣言（output-layout.json）から解決する。
  # 旧配置（画面/）を直書きすると、宣言経由で別の場所を読む本番の処理と
  # 食い違い、検査が常に空振りする（3dd2e4f 相当の再発防止）。
  mkdir -p "$docs/$screen_unit_root/screen-orders/詳細設計" "$(dirname "$html")" "$portal" "$tmp/repo"
  cat > "$docs/$screen_unit_root/screen-orders/詳細設計/単体テスト観点表.md" <<'EOF'
# 単体
| 観点 | 期待結果 |
| --- | --- |
| 入力必須 | 必須項目が表示される |
EOF
  cat > "$docs/$screen_unit_root/screen-orders/詳細設計/結合テスト観点表.md" <<'EOF'
# 結合
| 観点 | 期待結果 |
| --- | --- |
| 登録遷移 | 登録後に一覧へ戻る |
EOF
  if ! bash "$script_path" "$docs" "$manifest" >/dev/null 2>&1 \
    || ! bash "$script_dir/../unit-list/validate-test-viewpoint-manifest.sh" "$manifest" >/dev/null 2>&1 \
    || ! bash "$script_dir/../unit-list/build-unit-list.sh" "$manifest" "$html" --unit-kind test_viewpoint >/dev/null 2>&1 \
    || ! bash "$script_dir/../build-portal.sh" "$tmp/repo" "$docs" "$portal" >/dev/null 2>&1; then
    echo "self-test FAIL: テスト観点表の集約→検証→HTML→ポータル連結が失敗" >&2
    return 1
  fi
  printf '<script type="application/json">%s</script>\n' "$(jq -c . "$manifest")" > "$manifest_only"
  if jq -e '.summary.totalCount == 2 and ([.units[].testType] | sort == ["integration", "unit"])' "$manifest" >/dev/null 2>&1 \
    && has_visible_viewpoint_row "$html" "screen-orders-unit-1" "入力必須" "screen-orders" "単体" \
    && has_visible_viewpoint_row "$html" "screen-orders-integration-1" "登録遷移" "screen-orders" "結合" \
    && ! has_visible_viewpoint_row "$manifest_only" "screen-orders-unit-1" "入力必須" "screen-orders" "単体" \
    && grep -q '一覧/テスト観点表/テスト観点表.html' "$portal/index.html"; then
    echo "self-test PASS: テスト観点表の集約→検証→HTML→ポータル連結（既存正本パス維持）"
  else
    echo "self-test FAIL: テスト観点表の連結結果または正本パスが不正" >&2
    return 1
  fi

  # --- 新配置優先: 同じ画面に旧観点表も残る場合、新しい2設計書だけを各1回集約する ---
  mkdir -p "$docs/$screen_unit_root/screen-orders/テスト設計"
  cat > "$docs/$screen_unit_root/screen-orders/テスト設計/画面単体テスト設計書.md" <<'EOF'
## §1 テスト観点
### 単体
| 観点 | 期待結果 |
| --- | --- |
| 新単体観点 | 関数単位で検証できる |
EOF
  cat > "$docs/$screen_unit_root/screen-orders/テスト設計/画面テスト設計書.md" <<'EOF'
## §1 テスト観点
### 画面
| 観点 | 期待結果 |
| --- | --- |
| 新画面観点 | 画面操作を検証できる |
EOF
  if bash "$script_path" "$docs" "$manifest" >/dev/null 2>&1 \
    && bash "$script_dir/../unit-list/validate-test-viewpoint-manifest.sh" "$manifest" >/dev/null 2>&1 \
    && jq -e '.summary.totalCount == 2
      and ([.units[].unitKey] | unique | length) == 2
      and ([.units[].viewpoint] | sort == ["新単体観点", "新画面観点"])
      and all(.units[]; .testType == "unit")' "$manifest" >/dev/null 2>&1; then
    echo "self-test PASS: 新配置を優先し、統合済み設計書を重複集約せず旧観点表をfallbackにする"
  else
    echo "self-test FAIL: 新配置優先または旧観点表fallbackの集約が不正" >&2
    return 1
  fi

  # --- 0件ケース: per-screen観点表が1件も無いoutput_dirでも集約→検証→HTML生成が完走すること ---
  local zero_docs zero_manifest zero_html
  zero_docs="$tmp/zero-docs"
  zero_manifest="$tmp/zero-manifest.json"
  zero_html="$zero_docs/$units_root/テスト観点表/テスト観点表.html"
  mkdir -p "$zero_docs"
  if ! bash "$script_path" "$zero_docs" "$zero_manifest" >/dev/null 2>&1 \
    || ! bash "$script_dir/../unit-list/validate-test-viewpoint-manifest.sh" "$zero_manifest" >/dev/null 2>&1 \
    || ! bash "$script_dir/../unit-list/build-unit-list.sh" "$zero_manifest" "$zero_html" --unit-kind test_viewpoint >/dev/null 2>&1; then
    echo "self-test FAIL: 0件のoutput_dirで集約→検証→HTML生成が失敗" >&2
    return 1
  fi
  if jq -e '.summary.totalCount == 0' "$zero_manifest" >/dev/null 2>&1 \
    && [ -f "$zero_html" ]; then
    echo "self-test PASS: 0件のoutput_dirでも集約→検証→HTML生成が完走（空状態ページ生成）"
  else
    echo "self-test FAIL: 0件ケースのmanifestまたはHTML出力が不正" >&2
    return 1
  fi

  local override_docs override_manifest
  override_docs="$tmp/override-docs"
  override_manifest="$tmp/override-test-viewpoint-manifest.json"
  mkdir -p "$override_docs/スクリーン/screen-orders/詳細設計" \
    "$override_docs/画面/screen-decoy/詳細設計" \
    "$override_docs/archive/スクリーン/screen-archive-decoy/詳細設計" \
    "$override_docs/スクリーン/archive/スクリーン/screen-nested/詳細設計"
  cp -R "$docs/$screen_unit_root/screen-orders/詳細設計/." "$override_docs/スクリーン/screen-orders/詳細設計/"
  cp -R "$docs/$screen_unit_root/screen-orders/詳細設計/." "$override_docs/画面/screen-decoy/詳細設計/"
  cp -R "$docs/$screen_unit_root/screen-orders/詳細設計/." "$override_docs/archive/スクリーン/screen-archive-decoy/詳細設計/"
  cp -R "$docs/$screen_unit_root/screen-orders/詳細設計/." "$override_docs/スクリーン/archive/スクリーン/screen-nested/詳細設計/"
  cat > "$override_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "スクリーン" } }
JSON
  if bash "$script_path" "$override_docs" "$override_manifest" >/dev/null 2>&1 \
    && jq -e '.summary.totalCount == 2 and ([.units[].screenKey] | unique == ["screen-orders"])' "$override_manifest" >/dev/null 2>&1; then
    echo "self-test PASS: output_dir直下のscreenUnitRootだけを探索し既定root・nested同名rootのdecoyを除外"
  else
    echo "self-test FAIL: screenUnitRoot上書きの探索またはdecoy除外が不正" >&2
    return 1
  fi

  local prefix_docs prefix_manifest
  prefix_docs="$tmp/prefix-root-docs"
  prefix_manifest="$tmp/prefix-root-test-viewpoint-manifest.json"
  mkdir -p "$prefix_docs/screen-root/screen-alpha/詳細設計"
  cp -R "$docs/$screen_unit_root/screen-orders/詳細設計/." "$prefix_docs/screen-root/screen-alpha/詳細設計/"
  cat > "$prefix_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "screen-root" } }
JSON
  if bash "$script_path" "$prefix_docs" "$prefix_manifest" >/dev/null 2>&1 \
    && jq -e '.summary.totalCount == 2 and ([.units[].screenKey] | unique == ["screen-alpha"])' "$prefix_manifest" >/dev/null 2>&1; then
    echo "self-test PASS: screen-接頭辞のscreenUnitRootでも直下unit名をscreenKeyにする"
  else
    echo "self-test FAIL: screenUnitRoot名をscreenKeyとして誤抽出" >&2
    return 1
  fi

  # --- 非画面種別(API等)のテスト設計書「§1 テスト観点」の集約 ---
  local api_docs api_manifest
  api_docs="$tmp/api-docs"
  api_manifest="$tmp/api-test-viewpoint-manifest.json"
  mkdir -p "$api_docs/$api_unit_root/api-login/テスト設計"
  cat > "$api_docs/$api_unit_root/api-login/テスト設計/APIテスト設計書.md" <<'EOF'
## §1 テスト観点

観点はAPI基本設計書の外部仕様・業務仕様・エラーと例外の各章から起こす。

| キー | 観点 | 由来する基本設計書の章 |
|---|---|---|
| 認証-トークン期限切れ | 期限切れトークンで401を返す | 外部仕様 |

キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

## §2 テストケース一覧

| キー | ケースの名前 | 対応する観点のキー | 区分 |
|---|---|---|---|
EOF
  cat > "$api_docs/$api_unit_root/api-login/テスト設計/API単体テスト設計書.md" <<'EOF'
## §1 テスト観点

| キー | 関数・メソッド名 | 観点 | 由来する詳細設計書の章 |
|---|---|---|---|
| 認証関数-期限切れ | validateToken | 期限切れを判定する | §6 エラー処理 |
EOF
  if bash "$script_path" "$api_docs" "$api_manifest" >/dev/null 2>&1 \
    && bash "$script_dir/../unit-list/validate-test-viewpoint-manifest.sh" "$api_manifest" >/dev/null 2>&1 \
    && jq -e '.summary.totalCount == 2
      and ([.units[].unitKey] | unique | length) == 2
      and any(.units[]; .category == "外部仕様" and .viewpoint == "期限切れトークンで401を返す")
      and any(.units[]; .category == "§6 エラー処理" and .viewpoint == "期限切れを判定する")' "$api_manifest" >/dev/null 2>&1; then
    echo "self-test PASS: API外部契約・関数単位の由来章を重複キーなしで集約"
  else
    echo "self-test FAIL: 非画面種別(API)のテスト観点集約が不正" >&2
    return 1
  fi

  # --- 画面と非画面(API)の混在 ---
  local mixed_docs mixed_manifest
  mixed_docs="$tmp/mixed-docs"
  mixed_manifest="$tmp/mixed-test-viewpoint-manifest.json"
  mkdir -p "$mixed_docs/$screen_unit_root/screen-orders/詳細設計" "$mixed_docs/$api_unit_root/api-login/テスト設計"
  cp "$docs/$screen_unit_root/screen-orders/詳細設計/単体テスト観点表.md" "$mixed_docs/$screen_unit_root/screen-orders/詳細設計/"
  cp "$api_docs/$api_unit_root/api-login/テスト設計/"*テスト設計書.md "$mixed_docs/$api_unit_root/api-login/テスト設計/"
  if bash "$script_path" "$mixed_docs" "$mixed_manifest" >/dev/null 2>&1 \
    && jq -e '.summary.totalCount == 3 and ([.units[] | select(.screenKey == "api-login")] | length) == 2' "$mixed_manifest" >/dev/null 2>&1; then
    echo "self-test PASS: 画面と非画面(API)のテスト観点が両方集約される"
  else
    echo "self-test FAIL: 画面と非画面の混在集約が不正" >&2
    return 1
  fi

  # --- 非画面種別のフォルダが存在しないときはエラーにならず画面だけを集約 ---
  local noapi_docs noapi_manifest
  noapi_docs="$tmp/noapi-docs"
  noapi_manifest="$tmp/noapi-test-viewpoint-manifest.json"
  mkdir -p "$noapi_docs/$screen_unit_root/screen-orders/詳細設計"
  cp "$docs/$screen_unit_root/screen-orders/詳細設計/単体テスト観点表.md" "$noapi_docs/$screen_unit_root/screen-orders/詳細設計/"
  if bash "$script_path" "$noapi_docs" "$noapi_manifest" >/dev/null 2>&1 \
    && jq -e '.summary.totalCount == 1 and .units[0].screenKey == "screen-orders"' "$noapi_manifest" >/dev/null 2>&1; then
    echo "self-test PASS: 非画面種別のフォルダ不在でもエラーにならず画面だけを集約"
  else
    echo "self-test FAIL: 非画面種別フォルダ不在時の処理が不正" >&2
    return 1
  fi
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ "$#" -lt 2 ]; then
  usage
  exit 1
fi

output_dir="$1"
output_file="$2"

if [ ! -d "$output_dir" ]; then
  echo "ERROR: output_dir not found: $output_dir" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../output-layout.sh
source "$script_dir/../output-layout.sh"
layout_json="$(resolve_output_layout "$output_dir")" || exit 1
screen_unit_root="$(output_layout_get "$layout_json" screenUnitRoot)" || exit 1
unit_test_design_dir="$(output_layout_get "$layout_json" unitTestDesignDir)" || exit 1

generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

tmp_tsv="$(mktemp "${TMPDIR:-/tmp}/aggregate-test-viewpoints.XXXXXX")"
cleanup() { rm -f "$tmp_tsv"; }
trap cleanup EXIT

awk_program='
  function trim(s) {
    gsub(/^[ \t\r]+|[ \t\r]+$/, "", s)
    return s
  }
  function unbacktick(s) {
    gsub(/^`+|`+$/, "", s)
    return s
  }
  function is_heading(s) {
    return (s ~ /^[ \t]*#{1,6}[ \t]+/)
  }
  function heading_text(s,    t) {
    t = s
    gsub(/^[ \t]*#{1,6}[ \t]+/, "", t)
    return trim(t)
  }
  function split_row(line, out,    body, n, i) {
    body = line
    gsub(/^[ \t]*\|/, "", body)
    gsub(/\|[ \t\r]*$/, "", body)
    n = split(body, out, "|")
    for (i = 1; i <= n; i++) {
      out[i] = unbacktick(trim(out[i]))
    }
    return n
  }
  function is_separator(cols, n,    i, ok) {
    ok = 1
    for (i = 1; i <= n; i++) {
      if (cols[i] !~ /^:?-+:?$/) { ok = 0 }
    }
    return ok
  }
  function flush_pending() {
    if (pending && viewpointIdx > 0 && pcount >= viewpointIdx) {
      if (pcols[1] !~ /^<.*>$/ && pcols[viewpointIdx] != "") {
        rownum++
        scopeSuffix = (documentScope != "") ? "-" documentScope : ""
        printf "%s\t%s\t%s-%s%s-%d\t%s\t%s\n", screenKey, testType, screenKey, testType, scopeSuffix, rownum, category, pcols[viewpointIdx]
      }
    }
    pending = 0
  }
  BEGIN {
    category = ""
    viewpointIdx = 0
    pending = 0
    rownum = 0
  }
  {
    line = $0
    if (is_heading(line)) {
      flush_pending()
      category = heading_text(line)
      viewpointIdx = 0
      next
    }
    if (trim(line) == "") {
      flush_pending()
      viewpointIdx = 0
      next
    }
    if (line ~ /^[ \t]*\|/) {
      n = split_row(line, cols)
      if (is_separator(cols, n)) {
        if (pending) {
          viewpointIdx = 0
          for (i = 1; i <= pcount; i++) {
            if (pcols[i] == "観点") { viewpointIdx = i; break }
          }
          if (viewpointIdx == 0) {
            for (i = 1; i <= pcount; i++) {
              if (index(pcols[i], "観点") > 0) { viewpointIdx = i; break }
            }
          }
          pending = 0
        }
        next
      } else {
        flush_pending()
        pcount = n
        for (i = 1; i <= n; i++) { pcols[i] = cols[i] }
        pending = 1
        next
      }
    } else {
      flush_pending()
      viewpointIdx = 0
      next
    }
  }
  END {
    flush_pending()
  }
'

screen_test_viewpoint_section_slice_awk='
  BEGIN { in_section = 0 }
  {
    if ($0 ~ /^## §1 テスト観点[ \t]*$/) { in_section = 1; next }
    if (in_section && $0 ~ /^##[ \t]/) { in_section = 0 }
    if (in_section) print
  }
'

while IFS= read -r -d '' file; do
  relative_file="${file#"$output_dir/$screen_unit_root"/}"
  screen_key="${relative_file%%/*}"
  case "$screen_key" in screen-*) ;; *) continue ;; esac

  case "$file" in
    */テスト設計/画面単体テスト設計書.md)
      test_type="unit"
      document_scope="function"
      ;;
    */テスト設計/画面テスト設計書.md)
      test_type="unit"
      document_scope="external"
      ;;
    */詳細設計/単体テスト観点表.md)
      [ -f "$(dirname "$(dirname "$file")")/テスト設計/画面単体テスト設計書.md" ] && continue
      test_type="unit"
      document_scope=""
      ;;
    */詳細設計/結合テスト観点表.md)
      [ -f "$(dirname "$(dirname "$file")")/テスト設計/画面テスト設計書.md" ] && continue
      test_type="integration"
      document_scope=""
      ;;
    *) continue ;;
  esac

  if [[ "$file" == */テスト設計/* ]]; then
    LC_ALL=C awk "$screen_test_viewpoint_section_slice_awk" "$file" \
      | LC_ALL=C awk -v screenKey="$screen_key" -v testType="$test_type" -v documentScope="$document_scope" "$awk_program" /dev/stdin >> "$tmp_tsv"
  else
    LC_ALL=C awk -v screenKey="$screen_key" -v testType="$test_type" -v documentScope="$document_scope" "$awk_program" "$file" >> "$tmp_tsv"
  fi
done < <(find "$output_dir/$screen_unit_root" -mindepth 3 -maxdepth 3 -type f \
  \( -path "*/screen-*/テスト設計/画面単体テスト設計書.md" -o -path "*/screen-*/テスト設計/画面テスト設計書.md" \
     -o -path "*/screen-*/詳細設計/単体テスト観点表.md" -o -path "*/screen-*/詳細設計/結合テスト観点表.md" \) \
  -print0)

# --- 非画面種別(API・テーブル・バッチ・帳票・外部連携等)のテスト設計書「§1 テスト観点」の集約 ---
# 対象種別は screenUnitRoot 以外の全 <種別>UnitRoot キーを output-layout.json から動的に導く
# (種別名をスクリプトへ直書きしないため。新種別追加時も本スクリプトの変更は不要)。
section_slice_awk='
  BEGIN { in_section = 0 }
  {
    line = $0
    if (line ~ startRe) { in_section = 1; next }
    if (in_section && line ~ /^##[ \t]/) { in_section = 0 }
    if (in_section) print
  }
'

# --- 表抽出: 節内で先頭列が指定ヘッダの表を1件検出し、指定列を転記する ---
named_table_awk='
  function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
  function unbacktick(s) { gsub(/^`+|`+$/, "", s); return s }
  function split_row(line, out,    body, n, i) {
    body = line
    gsub(/^[ \t]*\|/, "", body)
    gsub(/\|[ \t\r]*$/, "", body)
    n = split(body, out, "|")
    for (i = 1; i <= n; i++) out[i] = unbacktick(trim(out[i]))
    return n
  }
  function is_separator(cols, n,    i, ok) {
    ok = 1
    for (i = 1; i <= n; i++) if (cols[i] !~ /^:?-+:?$/) ok = 0
    return ok
  }
  BEGIN { nWant = split(wantNames, wantArr, ","); state = 0 }
  {
    line = $0
    isPipe = (line ~ /^[ \t]*\|/)
    if (isPipe) { m = split_row(line, cols) }
    if (state == 0) {
      if (isPipe && trim(cols[1]) == firstHeader) {
        headerCount = m
        for (i = 1; i <= m; i++) headerName[i] = cols[i]
        state = 1
      }
      next
    }
    if (state == 1) {
      if (isPipe && is_separator(cols, m)) { state = 2 } else { state = 0 }
      next
    }
    if (state == 2) {
      if (!isPipe || trim(line) == "") { state = 0; next }
      if (cols[1] ~ /^<.*>$/) { next }
      out = cols[1]
      for (i = 1; i <= nWant; i++) {
        idx = 0
        for (j = 1; j <= headerCount; j++) { if (headerName[j] == wantArr[i]) { idx = j; break } }
        val = (idx > 0 && idx <= m) ? cols[idx] : ""
        gsub(/\t/, " ", val)
        out = out "\t" val
      }
      print out
      next
    }
  }
'

non_screen_kind_keys="$(printf '%s' "$layout_json" | jq -r '.layout | keys[] | select(endswith("UnitRoot") and . != "screenUnitRoot")')"

while IFS= read -r root_key; do
  [ -z "$root_key" ] && continue
  kind="${root_key%UnitRoot}"
  kind_root="$(output_layout_get "$layout_json" "$root_key")" || exit 1
  [ -d "$output_dir/$kind_root" ] || continue

  while IFS= read -r -d '' file; do
    relative_file="${file#"$output_dir/$kind_root"/}"
    unit_key="${relative_file%%/*}"
    case "$unit_key" in ${kind}-*) ;; *) continue ;; esac

    case "$(basename "$file")" in
      *単体*) document_scope="function" ;;
      *APIテスト*) document_scope="api-contract" ;;
      *) document_scope="test-design" ;;
    esac

    awk -v startRe='^## §1 テスト観点[ \t]*$' "$section_slice_awk" "$file" \
      | LC_ALL=C awk -v firstHeader="キー" -v wantNames="観点,由来する基本設計書の章,由来する詳細設計書の章" "$named_table_awk" \
      | awk -v ownerKey="$unit_key" -v documentScope="$document_scope" -F'\t' '
        {
          rownum++
          sourceChapter = ($4 != "") ? $4 : $3
          printf "%s\tunit\t%s-%s-unit-%d\t%s\t%s\n", ownerKey, ownerKey, documentScope, rownum, sourceChapter, $2
        }
      ' >> "$tmp_tsv"
  done < <(find "$output_dir/$kind_root" -mindepth 3 -maxdepth 3 -type f \
    -path "*/${kind}-*/${unit_test_design_dir}/*テスト設計書.md" -print0 2>/dev/null)
done <<< "$non_screen_kind_keys"

if [ ! -s "$tmp_tsv" ]; then
  jq -n --arg generatedAt "$generated_at" '{
    unitKind: "test_viewpoint",
    generatedAt: $generatedAt,
    units: [],
    summary: { totalCount: 0, byTestType: {}, byScreen: {} }
  }' > "$output_file"
  exit 0
fi

units_json="$(jq -R -s '
  split("\n") | map(select(length > 0)) | map(split("\t")) | map({
    screenKey: .[0],
    testType: .[1],
    unitKey: .[2],
    category: .[3],
    viewpoint: .[4]
  })
' < "$tmp_tsv")"

jq -n \
  --arg generatedAt "$generated_at" \
  --argjson units "$units_json" \
  '
  {
    unitKind: "test_viewpoint",
    generatedAt: $generatedAt,
    units: $units,
    summary: {
      totalCount: ($units | length),
      byTestType: ($units | group_by(.testType) | map({key: .[0].testType, value: length}) | from_entries),
      byScreen: ($units | group_by(.screenKey) | map({key: .[0].screenKey, value: length}) | from_entries)
    }
  }
  ' > "$output_file"
