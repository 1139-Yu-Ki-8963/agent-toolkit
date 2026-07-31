#!/usr/bin/env bash
# 抽出エンジン: 単体/結合テスト観点表(Markdown)群からテスト観点manifest(JSON)への横断集約。
# output_dir 配下の 画面/screen-*/詳細設計/{単体テスト観点表.md,結合テスト観点表.md} を
# すべて走査し、各テーブル行の「章見出し(カテゴリ)」と「観点」列を抽出して1つのJSONに集約する。
#
# Usage: aggregate-test-viewpoints.sh <output_dir> <output.json>
#
# 入力契約:
#   <output_dir> : 画面/screen-<ID>/詳細設計/単体テスト観点表.md および 結合テスト観点表.md を
#                 含むディレクトリツリーのルート
#                 （形式は shared/templates/リバース検証/画面/詳細設計/単体テスト観点表.md 準拠）
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
#   - ファイル名に「単体」を含めば testType=unit、「結合」を含めば testType=integration
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
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/aggregate-test-viewpoints-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  docs="$tmp/docs"
  manifest="$tmp/test-viewpoint-manifest.json"
  html="$docs/一覧/テスト観点表/テスト観点表.html"
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
  mkdir -p "$docs/画面/screen-orders/詳細設計" "$docs/一覧/テスト観点表" "$portal" "$tmp/repo"
  cat > "$docs/画面/screen-orders/詳細設計/単体テスト観点表.md" <<'EOF'
# 単体
| 観点 | 期待結果 |
| --- | --- |
| 入力必須 | 必須項目が表示される |
EOF
  cat > "$docs/画面/screen-orders/詳細設計/結合テスト観点表.md" <<'EOF'
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

  # --- 0件ケース: per-screen観点表が1件も無いoutput_dirでも集約→検証→HTML生成が完走すること ---
  local zero_docs zero_manifest zero_html
  zero_docs="$tmp/zero-docs"
  zero_manifest="$tmp/zero-manifest.json"
  zero_html="$zero_docs/一覧/テスト観点表/テスト観点表.html"
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
        printf "%s\t%s\t%s-%s-%d\t%s\t%s\n", screenKey, testType, screenKey, testType, rownum, category, pcols[viewpointIdx]
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

while IFS= read -r -d '' file; do
  screen_key="$(printf '%s\n' "$file" | awk -F'/' '{
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^screen-/) { print $i; exit }
    }
  }')"
  [ -z "$screen_key" ] && continue

  base="$(basename "$file")"
  case "$base" in
    *単体*) test_type="unit" ;;
    *結合*) test_type="integration" ;;
    *) continue ;;
  esac

  awk -v screenKey="$screen_key" -v testType="$test_type" "$awk_program" "$file" >> "$tmp_tsv"
done < <(find "$output_dir" \
  \( -path "*/画面/screen-*/詳細設計/単体テスト観点表.md" -o -path "*/画面/screen-*/詳細設計/結合テスト観点表.md" \) \
  -print0)

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
