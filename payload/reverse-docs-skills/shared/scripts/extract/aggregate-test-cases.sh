#!/usr/bin/env bash
# 抽出エンジン: per-screen テスト仕様書(単体/結合/操作シナリオ, Markdown)群から
# テストケースmanifest(JSON)への横断集約。
# output_dir 配下の 画面/screen-*/テスト項目書/{単体テスト仕様書.md,結合テスト仕様書.md,操作シナリオ仕様書.md}
# をすべて走査し、テストケース単位に集約した1つのJSONを出力する。
#
# Usage: aggregate-test-cases.sh <output_dir> <output.json>
#
# 入力契約:
#   <output_dir> : 画面/screen-<ID>/テスト項目書/単体テスト仕様書.md・結合テスト仕様書.md・
#                 操作シナリオ仕様書.md を含むディレクトリツリーのルート
#                 （形式は shared/templates/リバース検証/画面/テスト項目書/*.md 準拠）
#   <output.json> : 出力先パス
#
# 出力契約:
#   {
#     unitKind: "test_case",
#     generatedAt: string(UTC ISO8601),
#     units: [{ unitKey, screenKey, testType, unitNameGuess, kind, caseKey, viewpointKey, input, steps, expected }],
#     summary: { totalCount: number, byTestType: {...}, byScreen: {...} }
#   }
#
# パース仕様:
#   - ファイル名に「単体」を含めば testType=unit、「結合」を含めば testType=integration、
#     「操作シナリオ」を含めば testType=scenario
#   - screenKey はパス中の "screen-" で始まるディレクトリ名をそのまま使う
#   - 単体/結合: 先頭列が「キー」の表を1件検出し、「対応観点キー」「入力値」
#     「期待結果（アサーション）」列（結合は追加で「操作手順」列）をそのまま転記する
#   - 操作シナリオ: 先頭列が「シナリオ名」の表(シナリオ一覧表)を検出し、
#     「対応往復検証観点キー」を viewpointKey、「前提条件」を input として転記する。
#     期待結果は各シナリオの `### <シナリオ名>` 節にある「**期待結果**」直後の
#     段落を転記する（シナリオ一覧表とシナリオ名で対応付ける）
#   - データ行の1列目が "<...>" 形式（テンプレートのプレースホルダ例示行）のものはスキップする
#   - テスト仕様書が1件も見つからない場合はエラーにせず units:[] で正常終了する(fail-safe)
#
# 終了コード:
#   0 : 正常終了(テスト仕様書未検出でも units:[] で正常出力)
#   1 : output_dir 不在、または引数不足

set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <output_dir> <output.json>" >&2
}

# --- 表抽出(単体/結合。先頭列が指定ヘッダの表を1件検出し、指定列を転記する) ---
extract_named_table_awk='
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
  BEGIN {
    nWant = split(wantNames, wantArr, ",")
    state = 0
  }
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
      if (cols[1] ~ /^<.*>$/) next
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

# --- 操作シナリオの期待結果抽出(### <シナリオ名> 節の「**期待結果**」直後の段落) ---
extract_scenario_expected_awk='
  function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
  BEGIN { scenario = ""; collecting = 0; buf = "" }
  {
    line = $0
    if (line ~ /^### /) {
      if (scenario != "" && buf != "") { printf "%s\t%s\n", scenario, buf }
      scenario = trim(substr(line, 5))
      collecting = 0
      buf = ""
      next
    }
    t = trim(line)
    if (t == "**期待結果**") { collecting = 1; buf = ""; next }
    if (collecting) {
      if (t == "") {
        if (buf != "") {
          printf "%s\t%s\n", scenario, buf
          collecting = 0
          buf = ""
        }
        # 段落開始前の空行は無視して収集を継続する
        next
      }
      buf = (buf == "") ? t : buf " " t
      next
    }
  }
  END {
    if (scenario != "" && buf != "" && collecting) { printf "%s\t%s\n", scenario, buf }
  }
'

self_test() {
  local script_path="$0" script_dir tmp docs manifest html portal
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/aggregate-test-cases-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  docs="$tmp/docs"
  manifest="$tmp/test-case-manifest.json"
  html="$docs/一覧/テストケース一覧/テストケース一覧.html"
  portal="$tmp/portal"
  has_visible_case_row() {
    local file="$1" unit_key="$2" name="$3"
    awk -v unit_key="$unit_key" -v name="$name" '
      BEGIN { RS = "</tr>"; found = 0 }
      index($0, "data-unit-key=\"" unit_key "\"") && index($0, "<td>" name "</td>") { found = 1 }
      END { exit(found ? 0 : 1) }
    ' "$file"
  }
  mkdir -p "$docs/画面/screen-orders/テスト項目書" "$docs/一覧/テストケース一覧" "$portal" "$tmp/repo"
  cat > "$docs/画面/screen-orders/テスト項目書/単体テスト仕様書.md" <<'EOF'
## テストケース一覧

| キー | 対応観点キー | 入力値 | 期待結果（アサーション） | 実装後のテストファイル参照 |
|---|---|---|---|---|
| 合計0円-登録不可 | 金額-下限境界 | `total: 0` | `isRegisterable` が `false` を返す | |
EOF
  cat > "$docs/画面/screen-orders/テスト項目書/結合テスト仕様書.md" <<'EOF'
## テストケース一覧

| キー | 対応観点キー | 操作手順 | 入力値 | 期待結果（アサーション） | 実装後のテストファイル参照 |
|---|---|---|---|---|---|
| 登録実行-一覧反映 | 登録-一覧反映 | 登録ボタンを押す | 必須項目入力済み | 一覧に新規行が追加される | |
EOF
  cat > "$docs/画面/screen-orders/テスト項目書/操作シナリオ仕様書.md" <<'EOF'
## シナリオ一覧表

| シナリオ名 | 対応往復検証観点キー | 前提条件 |
|---|---|---|
| 検索条件の絞り込み | 操作後-画面反映 | 一覧に複数件表示中 |

## シナリオごとの節

### 検索条件の絞り込み

**操作手順**

| 順序 | アクション | 対象セレクタ | 入力値 |
|---|---|---|---|
| 1 | click | `[data-testid="search"]` | — |

**期待結果**

検索実行後、一覧テーブルが即座に更新される。

**実行用 YAML（機械実行の正）**

```yaml
operations:
  - action: click
    selector: '[data-testid="search"]'
```
EOF

  if ! bash "$script_path" "$docs" "$manifest" >/dev/null 2>&1 \
    || ! bash "$script_dir/../unit-list/validate-test-case-manifest.sh" "$manifest" >/dev/null 2>&1 \
    || ! bash "$script_dir/../unit-list/build-unit-list.sh" "$manifest" "$html" --unit-kind test_case >/dev/null 2>&1 \
    || ! bash "$script_dir/../build-portal.sh" "$tmp/repo" "$docs" "$portal" >/dev/null 2>&1; then
    echo "self-test FAIL: テストケースの集約→検証→HTML→ポータル連結が失敗" >&2
    return 1
  fi

  if jq -e '.summary.totalCount == 3 and ([.units[].testType] | sort == ["integration", "scenario", "unit"])' "$manifest" >/dev/null 2>&1 \
    && has_visible_case_row "$html" "screen-orders-unit-1" "合計0円-登録不可" \
    && has_visible_case_row "$html" "screen-orders-integration-1" "登録実行-一覧反映" \
    && has_visible_case_row "$html" "screen-orders-scenario-1" "検索条件の絞り込み" \
    && grep -q '一覧/テストケース一覧/テストケース一覧.html' "$portal/index.html" \
    && [ "$(jq -r '.units[] | select(.testType == "integration") | .steps' "$manifest")" = "登録ボタンを押す" ] \
    && [ "$(jq -r '.units[] | select(.testType == "scenario") | .expected' "$manifest")" = "検索実行後、一覧テーブルが即座に更新される。" ]; then
    echo "self-test PASS: テストケースの集約→検証→HTML→ポータル連結（単体/結合/操作シナリオ）"
  else
    echo "self-test FAIL: テストケースの連結結果が不正" >&2
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

tmp_tsv="$(mktemp "${TMPDIR:-/tmp}/aggregate-test-cases.XXXXXX")"
tmp_scenario_expected="$(mktemp "${TMPDIR:-/tmp}/aggregate-test-cases-scenario.XXXXXX")"
cleanup() { rm -f "$tmp_tsv" "$tmp_scenario_expected"; }
trap cleanup EXIT

# 単体/結合: screenKey \t testType \t unitKey \t caseKey \t viewpointKey \t input \t steps \t expected
while IFS= read -r -d '' file; do
  screen_key="$(printf '%s\n' "$file" | awk -F'/' '{
    for (i = 1; i <= NF; i++) { if ($i ~ /^screen-/) { print $i; exit } }
  }')"
  [ -z "$screen_key" ] && continue

  base="$(basename "$file")"
  case "$base" in
    *単体*)
      test_type="unit"
      want_names="対応観点キー,入力値,期待結果（アサーション）"
      has_steps=0
      ;;
    *結合*)
      test_type="integration"
      want_names="対応観点キー,操作手順,入力値,期待結果（アサーション）"
      has_steps=1
      ;;
    *) continue ;;
  esac

  awk -v firstHeader="キー" -v wantNames="$want_names" "$extract_named_table_awk" "$file" \
    | awk -v screenKey="$screen_key" -v testType="$test_type" -v hasSteps="$has_steps" -F'\t' '
    {
      rownum++
      caseKey = $1
      if (hasSteps == 1) {
        viewpointKey = $2; steps = $3; input = $4; expected = $5
      } else {
        viewpointKey = $2; steps = ""; input = $3; expected = $4
      }
      printf "%s\t%s\t%s-%s-%d\t%s\t%s\t%s\t%s\t%s\n", screenKey, testType, screenKey, testType, rownum, caseKey, viewpointKey, input, steps, expected
    }
  ' >> "$tmp_tsv"
done < <(find "$output_dir" \
  \( -path "*/画面/screen-*/テスト項目書/単体テスト仕様書.md" -o -path "*/画面/screen-*/テスト項目書/結合テスト仕様書.md" \) \
  -print0)

# 操作シナリオ: シナリオ一覧表 + 各節の期待結果段落を screenKey ごとに突合する
while IFS= read -r -d '' file; do
  screen_key="$(printf '%s\n' "$file" | awk -F'/' '{
    for (i = 1; i <= NF; i++) { if ($i ~ /^screen-/) { print $i; exit } }
  }')"
  [ -z "$screen_key" ] && continue

  tmp_top="$(mktemp "${TMPDIR:-/tmp}/aggregate-test-cases-top.XXXXXX")"
  tmp_expected="$(mktemp "${TMPDIR:-/tmp}/aggregate-test-cases-exp.XXXXXX")"
  awk -v firstHeader="シナリオ名" -v wantNames="対応往復検証観点キー,前提条件" "$extract_named_table_awk" "$file" > "$tmp_top"
  awk "$extract_scenario_expected_awk" "$file" > "$tmp_expected"

  scenario_rownum=0
  while IFS=$'\t' read -r scene_name viewpoint_key precondition; do
    [ -z "$scene_name" ] && continue
    expected="$(awk -F'\t' -v s="$scene_name" '$1 == s { print $2; exit }' "$tmp_expected")"
    scenario_rownum=$((scenario_rownum + 1))
    printf '%s\tscenario\t%s-scenario-%d\t%s\t%s\t%s\t%s\t%s\n' \
      "$screen_key" "$screen_key" "$scenario_rownum" "$scene_name" "$viewpoint_key" "$precondition" "" "$expected" >> "$tmp_tsv"
  done < "$tmp_top"
  rm -f "$tmp_top" "$tmp_expected"
done < <(find "$output_dir" -path "*/画面/screen-*/テスト項目書/操作シナリオ仕様書.md" -print0)

if [ ! -s "$tmp_tsv" ]; then
  jq -n --arg generatedAt "$generated_at" '{
    unitKind: "test_case",
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
    caseKey: .[3],
    unitNameGuess: .[3],
    kind: .[1],
    viewpointKey: .[4],
    input: .[5],
    steps: .[6],
    expected: .[7]
  })
' < "$tmp_tsv")"

jq -n \
  --arg generatedAt "$generated_at" \
  --argjson units "$units_json" \
  '
  {
    unitKind: "test_case",
    generatedAt: $generatedAt,
    units: $units,
    summary: {
      totalCount: ($units | length),
      byTestType: ($units | group_by(.testType) | map({key: .[0].testType, value: length}) | from_entries),
      byScreen: ($units | group_by(.screenKey) | map({key: .[0].screenKey, value: length}) | from_entries)
    }
  }
  ' > "$output_file"
