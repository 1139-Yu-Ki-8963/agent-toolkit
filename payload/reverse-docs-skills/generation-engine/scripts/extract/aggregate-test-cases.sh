#!/usr/bin/env bash
# 抽出エンジン: per-screen テスト設計書(単体/画面/操作シナリオ, Markdown)群から
# テストケースmanifest(JSON)への横断集約。
# output_dir 配下の <screenUnitRoot>/screen-*/テスト設計/{画面単体テスト設計書.md,画面テスト設計書.md,操作シナリオ仕様書.md}
# を優先して走査し、旧テスト項目書配下は新配置がない場合だけ後方互換として集約する。
#
# Usage: aggregate-test-cases.sh <output_dir> <output.json>
#
# 入力契約:
#   <output_dir> : <screenUnitRoot>/screen-<ID>/テスト設計/画面単体テスト設計書.md・画面テスト設計書.md・
#                 操作シナリオ仕様書.mdを含むディレクトリツリーのルート。新配置がない既存生成物では
#                 テスト項目書配下の単体・結合・操作シナリオ仕様書を後方互換として読む
#   <output.json> : 出力先パス
#
# 出力契約:
#   {
#     unitKind: "test_case",
#     generatedAt: string(UTC ISO8601),
#     units: [{ unitKey, screenKey, sourceKind, testType, unitNameGuess, kind, caseKey, viewpointKey, input, steps, expected, screenTestCaseKey }],
#     summary: {
#       totalCount: number,
#       byTestType: {unit, integration, scenario}(3種固定キー。検出0件も0で出力し、キーは脱落させない),
#       byScreen: {...},
#       scannedByTestType: {unit, integration, scenario}(3種固定キー。走査対象として実在した仕様書ファイルの件数),
#       excludedExampleRows: {unit, integration, scenario}(3種固定キー。記入例プレースホルダ行として除外した件数)
#     }
#   }
#
# パース仕様:
#   - 新体系の画面単体テスト設計書・画面テスト設計書はいずれも1画面単位のためtestType=unit、
#     操作シナリオ仕様書はtestType=scenarioとして扱う。既存生成物の旧結合テスト仕様書だけは
#     後方互換のtestType=integrationを維持する
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
    excluded = 0
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
      if (cols[1] ~ /^<.*>$/) { excluded++; next }
      out = cols[1]
      for (i = 1; i <= nWant; i++) {
        idx = 0
        for (j = 1; j <= headerCount; j++) {
          if (headerName[j] == wantArr[i] ||
            (wantArr[i] == "対応する観点のキー" && headerName[j] == "対応観点キー")) {
            idx = j
            break
          }
        }
        val = (idx > 0 && idx <= m) ? cols[idx] : ""
        gsub(/\t/, " ", val)
        out = out "\t" val
      }
      print out
      next
    }
  }
  END {
    printf "%d\n", excluded > "/dev/stderr"
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

extract_new_scenario_expected_awk='
  function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
  function split_row(line, out,    body, n, i) {
    body = line
    gsub(/^[ \t]*\|/, "", body)
    gsub(/\|[ \t\r]*$/, "", body)
    n = split(body, out, "|")
    for (i = 1; i <= n; i++) out[i] = trim(out[i])
    return n
  }
  function is_separator(cols, n,    i, ok) {
    ok = 1
    for (i = 1; i <= n; i++) if (cols[i] !~ /^:?-+:?$/) ok = 0
    return ok
  }
  function flush() { if (scenario != "" && expected != "") print scenario "\t" expected }
  BEGIN { scenario = ""; expected = ""; state = 0; expectedIdx = 0 }
  {
    line = $0
    if (line ~ /^### /) {
      flush()
      scenario = trim(substr(line, 5))
      expected = ""
      state = 0
      expectedIdx = 0
      next
    }
    if (line ~ /^#### 操作と期待結果[ \t]*$/) { state = 1; next }
    if (state == 1 && line ~ /^[ \t]*\|/) {
      n = split_row(line, cols)
      if (is_separator(cols, n)) { state = (expectedIdx > 0) ? 2 : 0; next }
      for (i = 1; i <= n; i++) if (cols[i] == "期待結果") expectedIdx = i
      next
    }
    if (state == 2 && line ~ /^[ \t]*\|/) {
      n = split_row(line, cols)
      if (expectedIdx > 0 && expectedIdx <= n && cols[expectedIdx] != "") expected = cols[expectedIdx]
      next
    }
    if (line ~ /^#### /) state = 0
  }
  END { flush() }
'

extract_new_scenario_yaml_contract_awk='
  function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
  function value_after_colon(s) {
    sub(/^[^:]*:[ \t]*/, "", s)
    s = trim(s)
    return s
  }
  function flush() {
    if (key != "") print key "\t" name "\t" viewpoint "\t" test_case
  }
  BEGIN { in_yaml = 0; key = ""; name = ""; viewpoint = ""; test_case = "" }
  /^```yaml[ \t]*$/ { in_yaml = 1; next }
  in_yaml && /^```[ \t]*$/ { flush(); in_yaml = 0; key = ""; next }
  in_yaml {
    line = $0
    if (line ~ /^[ \t]*-[ \t]+key:/) {
      flush()
      key = value_after_colon(line)
      name = ""; viewpoint = ""; test_case = ""
    } else if (line ~ /^[ \t]+name:/) {
      name = value_after_colon(line)
    } else if (line ~ /^[ \t]+roundtrip_viewpoint_key:/) {
      viewpoint = value_after_colon(line)
    } else if (line ~ /^[ \t]+screen_test_case_key:/) {
      test_case = value_after_colon(line)
    }
  }
  END { if (in_yaml) flush() }
'

self_test() {
  local script_path="$0" script_dir tmp docs manifest html portal
  local layout_json screen_unit_root api_unit_root units_root
  if [ -d "${TMPDIR:-/tmp}" ]; then
    TMPDIR="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
    export TMPDIR
  fi
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  # shellcheck source=../output-layout.sh
  source "$script_dir/../output-layout.sh"
  layout_json="$(resolve_output_layout "")" || return 1
  screen_unit_root="$(output_layout_get "$layout_json" screenUnitRoot)" || return 1
  api_unit_root="$(output_layout_get "$layout_json" apiUnitRoot)" || return 1
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/aggregate-test-cases-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  docs="$tmp/docs"
  manifest="$tmp/test-case-manifest.json"
  # 1-244: 「テストケース」は screen/api/table/... の8種別（kindLabels/kindDirNames、
  # 1-208で新設）に属さない集約カテゴリであり、output_layout_get の {labelDir} 解決
  # （kindLabels の逆引き）には対応しない。実際に build-portal.sh（portal-catalog.mjs
  # の resolveDefaultRootPrefix）がこのHTMLを発見・連結する先は、portal-catalog.json
  # の test-case-list blueprint が持つ discovery.glob の既定接頭辞（defaultRoots.
  # unitsRoot="project-portal/一覧"、旧配置）を output-layout.json の現行 unitsRoot
  # （1-208で"project-portal/lists"へ英数字化済み）へ動的に置換した経路であり、
  # 接頭辞だけが新配置、日本語のサブディレクトリ名・ファイル名は旧glob由来のまま
  # 残る（1-209でportal-catalog.json自体の日本語ディレクトリ名は対象外と確定済み）。
  # unitListHtml の新配置テンプレート（project-portal/lists/{labelDir}/{label}一覧.html、
  # 1-208新設）とは無関係で、labelDir解決に失敗するため使えない。unitsRoot が今後も
  # 変わりうるため、値は直書きせず output_layout_get から取得する。
  units_root="$(output_layout_get "$layout_json" unitsRoot)" || return 1
  html="$docs/${units_root}/テストケース一覧/テストケース一覧.html"
  portal="$tmp/portal"
  has_visible_case_row() {
    local file="$1" unit_key="$2" name="$3"
    awk -v unit_key="$unit_key" -v name="$name" '
      BEGIN { RS = "</tr>"; found = 0 }
      index($0, "data-unit-key=\"" unit_key "\"") && index($0, "<td>" name "</td>") { found = 1 }
      END { exit(found ? 0 : 1) }
    ' "$file"
  }
  # フィクスチャの書き込み先は宣言（output-layout.json）から解決する。
  # 旧配置（画面/）を直書きすると、宣言経由で別の場所を読む本番の処理と
  # 食い違い、検査が常に空振りする（3dd2e4f 相当の再発防止）。
  mkdir -p "$docs/$screen_unit_root/screen-orders/テスト項目書" "$(dirname "$html")" "$portal" "$tmp/repo"
  cat > "$docs/$screen_unit_root/screen-orders/テスト項目書/単体テスト仕様書.md" <<'EOF'
## テストケース一覧

| キー | 対応観点キー | 入力値 | 期待結果（アサーション） | 実装後のテストファイル参照 |
|---|---|---|---|---|
| 合計0円-登録不可 | 金額-下限境界 | `total: 0` | `isRegisterable` が `false` を返す | |
EOF
  cat > "$docs/$screen_unit_root/screen-orders/テスト項目書/結合テスト仕様書.md" <<'EOF'
## テストケース一覧

| キー | 対応観点キー | 操作手順 | 入力値 | 期待結果（アサーション） | 実装後のテストファイル参照 |
|---|---|---|---|---|---|
| 登録実行-一覧反映 | 登録-一覧反映 | 登録ボタンを押す | 必須項目入力済み | 一覧に新規行が追加される | |
EOF
  cat > "$docs/$screen_unit_root/screen-orders/テスト項目書/操作シナリオ仕様書.md" <<'EOF'
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
    && grep -qF "${units_root}/テストケース一覧/テストケース一覧.html" "$portal/index.html" \
    && [ "$(jq -r '.units[] | select(.testType == "integration") | .steps' "$manifest")" = "登録ボタンを押す" ] \
    && [ "$(jq -r '.units[] | select(.testType == "scenario") | .expected' "$manifest")" = "検索実行後、一覧テーブルが即座に更新される。" ]; then
    echo "self-test PASS: テストケースの集約→検証→HTML→ポータル連結（単体/結合/操作シナリオ）"
  else
    echo "self-test FAIL: テストケースの連結結果が不正" >&2
    return 1
  fi

  # --- 新配置優先: 旧仕様書が同居しても新しい2設計書とシナリオだけを各1回集約する ---
  mkdir -p "$docs/$screen_unit_root/screen-orders/テスト設計"
  cat > "$docs/$screen_unit_root/screen-orders/テスト設計/画面単体テスト設計書.md" <<'EOF'
## §2 テストケース一覧

| キー | 対応観点キー | 入力値・操作 | 期待結果（アサーション） |
|---|---|---|---|
| 新単体ケース | 新単体観点 | amount: 1 | trueを返す |
EOF
  cat > "$docs/$screen_unit_root/screen-orders/テスト設計/画面テスト設計書.md" <<'EOF'
## §2 テストケース一覧

| キー | 対応観点キー | 操作手順 | 入力値 | 期待結果（アサーション） |
|---|---|---|---|---|
| 新画面ケース | 新画面観点 | 保存を押す | 必須項目入力済み | 完了表示される |
EOF
  cat > "$docs/$screen_unit_root/screen-orders/テスト設計/操作シナリオ仕様書.md" <<'EOF'
## シナリオ一覧表

| シナリオキー | シナリオ名 | 開始状態 | 操作数 | 対応往復検証観点キー | 対応画面テストケースキー |
|---|---|---|---|---|---|
| 新検索 | 新検索シナリオ | 初期表示済み | 2 | 新画面観点 | 新画面ケース |

## シナリオ別仕様

### 新検索シナリオ

#### 操作と期待結果

| 順序 | 操作 | 対象 | 値 | 期待結果 |
|---|---|---|---|---|
| 1 | fill | 検索欄 | 検索語 | 入力値が表示される |
| 2 | click | 検索ボタン |  | 検索結果が表示される |

## 機械実行用YAML

```yaml
scenarios:
  - key: 新検索
    name: 新検索シナリオ
    roundtrip_viewpoint_key: 新画面観点
    screen_test_case_key: 新画面ケース
```
EOF
  if bash "$script_path" "$docs" "$manifest" >/dev/null 2>&1 \
    && bash "$script_dir/../unit-list/validate-test-case-manifest.sh" "$manifest" >/dev/null 2>&1 \
    && jq -e '.summary.totalCount == 3
      and ([.units[].unitKey] | unique | length) == 3
      and ([.units[].caseKey] | sort == ["新単体ケース", "新検索シナリオ", "新画面ケース"])
      and (.units[] | select(.caseKey == "新単体ケース") | .input == "amount: 1")
      and (.units[] | select(.caseKey == "新画面ケース") | .testType == "unit" and .steps == "保存を押す")
      and (.units[] | select(.caseKey == "新検索シナリオ") | .expected == "検索結果が表示される" and .screenTestCaseKey == "新画面ケース")' "$manifest" >/dev/null 2>&1; then
    echo "self-test PASS: 新配置を優先し、§2テストケースとシナリオ別期待結果を旧仕様書と重複なく集約"
  else
    echo "self-test FAIL: 新配置優先または画面テスト設計書・操作シナリオの集約が不正" >&2
    return 1
  fi

  local mismatch_docs mismatch_manifest mismatch_scenario
  mismatch_docs="$tmp/scenario-mismatch-docs"
  mismatch_manifest="$tmp/scenario-mismatch-manifest.json"
  cp -R "$docs" "$mismatch_docs"
  mismatch_scenario="$mismatch_docs/$screen_unit_root/screen-orders/テスト設計/操作シナリオ仕様書.md"
  sed 's/screen_test_case_key: 新画面ケース/screen_test_case_key: 不一致ケース/' "$mismatch_scenario" > "$mismatch_scenario.next"
  mv "$mismatch_scenario.next" "$mismatch_scenario"
  if bash "$script_path" "$mismatch_docs" "$mismatch_manifest" >/dev/null 2>&1; then
    echo "self-test FAIL: 操作シナリオの一覧表とYAMLのケースキー不一致を受理" >&2
    return 1
  else
    echo "self-test PASS: 操作シナリオの一覧表とYAMLのキー不一致を拒否"
  fi

  # --- 追加ケース: 仕様書は実在するが確定行0件の種別がある場合 ---
  local tmp2 docs2 manifest2
  tmp2="$(mktemp -d "${TMPDIR:-/tmp}/aggregate-test-cases-self-test2.XXXXXX")"
  docs2="$tmp2/docs"
  manifest2="$tmp2/test-case-manifest.json"
  mkdir -p "$docs2/$screen_unit_root/screen-orders/テスト項目書"
  cat > "$docs2/$screen_unit_root/screen-orders/テスト項目書/単体テスト仕様書.md" <<'EOF'
## テストケース一覧

| キー | 対応観点キー | 入力値 | 期待結果（アサーション） | 実装後のテストファイル参照 |
|---|---|---|---|---|
| 合計0円-登録不可 | 金額-下限境界 | `total: 0` | `isRegisterable` が `false` を返す | |
EOF
  cat > "$docs2/$screen_unit_root/screen-orders/テスト項目書/結合テスト仕様書.md" <<'EOF'
## テストケース一覧

| キー | 対応観点キー | 操作手順 | 入力値 | 期待結果（アサーション） | 実装後のテストファイル参照 |
|---|---|---|---|---|---|
| 登録実行-一覧反映 | 登録-一覧反映 | 登録ボタンを押す | 必須項目入力済み | 一覧に新規行が追加される | |
EOF
  cat > "$docs2/$screen_unit_root/screen-orders/テスト項目書/操作シナリオ仕様書.md" <<'EOF'
## シナリオ一覧表

| シナリオ名 | 対応往復検証観点キー | 前提条件 |
|---|---|---|
| <シナリオ名> | <観点キー> | <前提条件> |
EOF

  if ! bash "$script_path" "$docs2" "$manifest2" >/dev/null 2>&1 \
    || ! bash "$script_dir/../unit-list/validate-test-case-manifest.sh" "$manifest2" >/dev/null 2>&1; then
    echo "self-test FAIL: 確定行0件種別ケースの集約・検証が失敗" >&2
    rm -rf "$tmp2"
    return 1
  fi

  if jq -e '.summary.byTestType.scenario == 0
    and .summary.scannedByTestType.scenario == 1
    and .summary.byTestType.unit >= 1
    and .summary.byTestType.integration >= 1' "$manifest2" >/dev/null 2>&1; then
    echo "self-test PASS: 仕様書実在・確定行0件種別のキー保持（scannedByTestTypeで区別）"
  else
    echo "self-test FAIL: 確定行0件種別のキーが脱落、またはscannedByTestTypeが不正" >&2
    rm -rf "$tmp2"
    return 1
  fi
  rm -rf "$tmp2"

  local override_docs override_manifest
  override_docs="$tmp/override-docs"
  override_manifest="$tmp/override-test-case-manifest.json"
  mkdir -p "$override_docs/スクリーン/screen-orders/テスト項目書" \
    "$override_docs/画面/screen-decoy/テスト項目書" \
    "$override_docs/archive/スクリーン/screen-archive-decoy/テスト項目書" \
    "$override_docs/スクリーン/archive/スクリーン/screen-nested/テスト項目書"
  cp -R "$docs/$screen_unit_root/screen-orders/テスト項目書/." "$override_docs/スクリーン/screen-orders/テスト項目書/"
  cp -R "$docs/$screen_unit_root/screen-orders/テスト項目書/." "$override_docs/画面/screen-decoy/テスト項目書/"
  cp -R "$docs/$screen_unit_root/screen-orders/テスト項目書/." "$override_docs/archive/スクリーン/screen-archive-decoy/テスト項目書/"
  cp -R "$docs/$screen_unit_root/screen-orders/テスト項目書/." "$override_docs/スクリーン/archive/スクリーン/screen-nested/テスト項目書/"
  cat > "$override_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "スクリーン" } }
JSON
  if bash "$script_path" "$override_docs" "$override_manifest" >/dev/null 2>&1 \
    && jq -e '.summary.totalCount == 3 and ([.units[].screenKey] | unique == ["screen-orders"])' "$override_manifest" >/dev/null 2>&1; then
    echo "self-test PASS: output_dir直下のscreenUnitRootだけを探索し既定root・nested同名rootのdecoyを除外"
  else
    echo "self-test FAIL: screenUnitRoot上書きの探索またはdecoy除外が不正" >&2
    return 1
  fi

  local prefix_docs prefix_manifest
  prefix_docs="$tmp/prefix-root-docs"
  prefix_manifest="$tmp/prefix-root-test-case-manifest.json"
  mkdir -p "$prefix_docs/screen-root/screen-alpha/テスト項目書"
  cp -R "$docs/$screen_unit_root/screen-orders/テスト項目書/." "$prefix_docs/screen-root/screen-alpha/テスト項目書/"
  cat > "$prefix_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "screen-root" } }
JSON
  if bash "$script_path" "$prefix_docs" "$prefix_manifest" >/dev/null 2>&1 \
    && jq -e '.summary.totalCount == 3 and ([.units[].screenKey] | unique == ["screen-alpha"])' "$prefix_manifest" >/dev/null 2>&1; then
    echo "self-test PASS: screen-接頭辞のscreenUnitRootでも直下unit名をscreenKeyにする"
  else
    echo "self-test FAIL: screenUnitRoot名をscreenKeyとして誤抽出" >&2
    return 1
  fi

  # --- 非画面種別(API等)のテスト設計書「§2 テストケース一覧」の集約 ---
  local api_docs api_manifest
  api_docs="$tmp/api-docs"
  api_manifest="$tmp/api-test-case-manifest.json"
  mkdir -p "$api_docs/$api_unit_root/api-login/テスト設計"
  cat > "$api_docs/$api_unit_root/api-login/テスト設計/APIテスト設計書.md" <<'EOF'
## §1 テスト観点

| キー | 観点 | 由来する基本設計書の章 |
|---|---|---|
| 認証-トークン期限切れ | 期限切れトークンで401を返す | 外部仕様 |

## §2 テストケース一覧

| キー | ケースの名前 | 対応観点キー | 区分 |
|---|---|---|---|
| 認証-期限切れ拒否 | 期限切れトークンでの拒否 | 認証-トークン期限切れ | 異常系 |
EOF
  cat > "$api_docs/$api_unit_root/api-login/テスト設計/API単体テスト設計書.md" <<'EOF'
## §2 テストケース一覧

| キー | ケースの名前 | 対応する観点のキー | 区分 |
|---|---|---|---|
| 認証関数-期限切れ判定 | 期限切れを判定する | 認証関数-期限切れ | 異常系 |
EOF
  if bash "$script_path" "$api_docs" "$api_manifest" >/dev/null 2>&1 \
    && bash "$script_dir/../unit-list/validate-test-case-manifest.sh" "$api_manifest" >/dev/null 2>&1 \
    && jq -e '.summary.totalCount == 2
      and ([.units[].unitKey] | unique | length) == 2
      and any(.units[]; .caseKey == "認証-期限切れ拒否" and .viewpointKey == "認証-トークン期限切れ")
      and any(.units[]; .caseKey == "認証関数-期限切れ判定" and .viewpointKey == "認証関数-期限切れ")
      and all(.units[]; .screenKey == "api-login" and .sourceKind == "api" and .testType == "unit" and .input == "" and .steps == "" and .expected == "")' "$api_manifest" >/dev/null 2>&1; then
    echo "self-test PASS: API外部契約・関数単位の二文書を重複キーなしで集約"
  else
    echo "self-test FAIL: 非画面種別(API)のテストケース集約が不正" >&2
    return 1
  fi

  # --- 画面と非画面(API)の混在 ---
  local mixed_docs mixed_manifest
  mixed_docs="$tmp/mixed-docs"
  mixed_manifest="$tmp/mixed-test-case-manifest.json"
  mkdir -p "$mixed_docs/$screen_unit_root/screen-orders/テスト項目書" "$mixed_docs/$api_unit_root/api-login/テスト設計"
  cp -R "$docs/$screen_unit_root/screen-orders/テスト項目書/." "$mixed_docs/$screen_unit_root/screen-orders/テスト項目書/"
  cp "$api_docs/$api_unit_root/api-login/テスト設計/"*テスト設計書.md "$mixed_docs/$api_unit_root/api-login/テスト設計/"
  if bash "$script_path" "$mixed_docs" "$mixed_manifest" >/dev/null 2>&1 \
    && jq -e '.summary.totalCount == 5
      and ([.units[] | select(.screenKey == "api-login" and .sourceKind == "api")] | length) == 2
      and ([.units[] | select(.screenKey == "screen-orders" and .sourceKind == "screen")] | length) == 3' "$mixed_manifest" >/dev/null 2>&1; then
    echo "self-test PASS: 画面と非画面(API)のテストケースが両方集約される"
  else
    echo "self-test FAIL: 画面と非画面の混在集約が不正" >&2
    return 1
  fi

  # --- 非画面種別のフォルダが存在しないときはエラーにならず画面だけを集約 ---
  local noapi_docs noapi_manifest
  noapi_docs="$tmp/noapi-docs"
  noapi_manifest="$tmp/noapi-test-case-manifest.json"
  mkdir -p "$noapi_docs/$screen_unit_root/screen-orders/テスト項目書"
  cp -R "$docs/$screen_unit_root/screen-orders/テスト項目書/." "$noapi_docs/$screen_unit_root/screen-orders/テスト項目書/"
  if bash "$script_path" "$noapi_docs" "$noapi_manifest" >/dev/null 2>&1 \
    && jq -e '.summary.totalCount == 3 and ([.units[].screenKey] | unique == ["screen-orders"])' "$noapi_manifest" >/dev/null 2>&1; then
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

tmp_tsv="$(mktemp "${TMPDIR:-/tmp}/aggregate-test-cases.XXXXXX")"
tmp_scenario_expected="$(mktemp "${TMPDIR:-/tmp}/aggregate-test-cases-scenario.XXXXXX")"
tmp_excl="$(mktemp "${TMPDIR:-/tmp}/aggregate-test-cases-excl.XXXXXX")"
cleanup() { rm -f "$tmp_tsv" "$tmp_scenario_expected" "$tmp_excl"; }
trap cleanup EXIT

# 種別別の走査対象仕様書件数・記入例除外行数(3種固定キー・0初期化)
scanned_unit=0
scanned_integration=0
scanned_scenario=0
excluded_unit=0
excluded_integration=0
excluded_scenario=0

screen_test_section_slice_awk='
  BEGIN { in_section = 0 }
  {
    if ($0 ~ /^## §2 テストケース一覧[ \t]*$/) { in_section = 1; next }
    if (in_section && $0 ~ /^##[ \t]/) { in_section = 0 }
    if (in_section) print
  }
'

# テストケース: ownerKey \t testType \t unitKey \t caseKey \t viewpointKey \t input \t steps \t expected \t screenTestCaseKey \t sourceKind
while IFS= read -r -d '' file; do
  relative_file="${file#"$output_dir/$screen_unit_root"/}"
  screen_key="${relative_file%%/*}"
  case "$screen_key" in screen-*) ;; *) continue ;; esac

  case "$file" in
    */テスト設計/画面単体テスト設計書.md)
      test_type="unit"
      document_scope="function"
      want_names="対応観点キー,入力値・操作,期待結果（アサーション）"
      has_steps=0
      is_new_design=1
      ;;
    */テスト設計/画面テスト設計書.md)
      test_type="unit"
      document_scope="external"
      want_names="対応観点キー,操作手順,入力値,期待結果（アサーション）"
      has_steps=1
      is_new_design=1
      ;;
    */テスト項目書/単体テスト仕様書.md)
      [ -f "$(dirname "$(dirname "$file")")/テスト設計/画面単体テスト設計書.md" ] && continue
      test_type="unit"
      document_scope=""
      want_names="対応観点キー,入力値,期待結果（アサーション）"
      has_steps=0
      is_new_design=0
      ;;
    */テスト項目書/結合テスト仕様書.md)
      [ -f "$(dirname "$(dirname "$file")")/テスト設計/画面テスト設計書.md" ] && continue
      test_type="integration"
      document_scope=""
      want_names="対応観点キー,操作手順,入力値,期待結果（アサーション）"
      has_steps=1
      is_new_design=0
      ;;
    *) continue ;;
  esac

  case "$test_type" in
    unit) scanned_unit=$((scanned_unit + 1)) ;;
    integration) scanned_integration=$((scanned_integration + 1)) ;;
  esac

  tmp_rows="$(mktemp "${TMPDIR:-/tmp}/aggregate-test-cases-rows.XXXXXX")"
  if [ "$is_new_design" -eq 1 ]; then
    LC_ALL=C awk "$screen_test_section_slice_awk" "$file" \
      | LC_ALL=C awk -v firstHeader="キー" -v wantNames="$want_names" "$extract_named_table_awk" /dev/stdin > "$tmp_rows" 2>"$tmp_excl"
  else
    LC_ALL=C awk -v firstHeader="キー" -v wantNames="$want_names" "$extract_named_table_awk" "$file" > "$tmp_rows" 2>"$tmp_excl"
  fi
  awk -v screenKey="$screen_key" -v testType="$test_type" -v documentScope="$document_scope" -v hasSteps="$has_steps" -F'\t' '
    {
      rownum++
      caseKey = $1
      if (hasSteps == 1) {
        viewpointKey = $2; steps = $3; input = $4; expected = $5
      } else {
        viewpointKey = $2; steps = ""; input = $3; expected = $4
      }
      scopeSuffix = (documentScope != "") ? "-" documentScope : ""
      printf "%s\t%s\t%s-%s%s-%d\t%s\t%s\t%s\t%s\t%s\t\tscreen\n", screenKey, testType, screenKey, testType, scopeSuffix, rownum, caseKey, viewpointKey, input, steps, expected
    }
  ' "$tmp_rows" >> "$tmp_tsv"
  rm -f "$tmp_rows"
  excl_n="$(cat "$tmp_excl" 2>/dev/null || true)"
  [ -z "$excl_n" ] && excl_n=0
  case "$test_type" in
    unit) excluded_unit=$((excluded_unit + excl_n)) ;;
    integration) excluded_integration=$((excluded_integration + excl_n)) ;;
  esac
done < <(find "$output_dir/$screen_unit_root" -mindepth 3 -maxdepth 3 -type f \
  \( -path "*/screen-*/テスト設計/画面単体テスト設計書.md" -o -path "*/screen-*/テスト設計/画面テスト設計書.md" \
     -o -path "*/screen-*/テスト項目書/単体テスト仕様書.md" -o -path "*/screen-*/テスト項目書/結合テスト仕様書.md" \) \
  -print0 2>/dev/null)

# 操作シナリオ: シナリオ一覧表 + 各節の期待結果 + YAML契約を screenKey ごとに突合する
scenario_contract_error=0
while IFS= read -r -d '' file; do
  relative_file="${file#"$output_dir/$screen_unit_root"/}"
  screen_key="${relative_file%%/*}"
  case "$screen_key" in screen-*) ;; *) continue ;; esac

  if [[ "$file" == */テスト項目書/操作シナリオ仕様書.md ]] \
    && [ -f "$(dirname "$(dirname "$file")")/テスト設計/操作シナリオ仕様書.md" ]; then
    continue
  fi

  scanned_scenario=$((scanned_scenario + 1))

  tmp_top="$(mktemp "${TMPDIR:-/tmp}/aggregate-test-cases-top.XXXXXX")"
  tmp_expected="$(mktemp "${TMPDIR:-/tmp}/aggregate-test-cases-exp.XXXXXX")"
  tmp_yaml="$(mktemp "${TMPDIR:-/tmp}/aggregate-test-cases-yaml.XXXXXX")"
  scenario_format="legacy"
  if [[ "$file" == */テスト設計/操作シナリオ仕様書.md ]]; then
    LC_ALL=C awk -v firstHeader="シナリオキー" -v wantNames="シナリオ名,対応往復検証観点キー,対応画面テストケースキー,開始状態" "$extract_named_table_awk" "$file" > "$tmp_top" 2>"$tmp_excl"
    LC_ALL=C awk "$extract_new_scenario_expected_awk" "$file" > "$tmp_expected"
    LC_ALL=C awk "$extract_new_scenario_yaml_contract_awk" "$file" > "$tmp_yaml"
    scenario_format="new"
  else
    LC_ALL=C awk -v firstHeader="シナリオ名" -v wantNames="対応往復検証観点キー,前提条件" "$extract_named_table_awk" "$file" > "$tmp_top" 2>"$tmp_excl"
    LC_ALL=C awk "$extract_scenario_expected_awk" "$file" > "$tmp_expected"
  fi
  excl_n="$(cat "$tmp_excl" 2>/dev/null || true)"
  [ -z "$excl_n" ] && excl_n=0
  excluded_scenario=$((excluded_scenario + excl_n))

  scenario_rownum=0
  while IFS=$'\t' read -r scenario_key scene_name viewpoint_key screen_test_case_key precondition; do
    if [ "$scenario_format" = "legacy" ]; then
      precondition="$viewpoint_key"
      screen_test_case_key=""
      viewpoint_key="$scene_name"
      scene_name="$scenario_key"
    else
      yaml_row="$(LC_ALL=C awk -F'\t' -v k="$scenario_key" '$1 == k { print; exit }' "$tmp_yaml")"
      IFS=$'\t' read -r yaml_key yaml_name yaml_viewpoint_key yaml_screen_test_case_key <<< "$yaml_row"
      if [ -z "$yaml_row" ] \
        || [ "$yaml_name" != "$scene_name" ] \
        || [ "$yaml_viewpoint_key" != "$viewpoint_key" ] \
        || [ "$yaml_screen_test_case_key" != "$screen_test_case_key" ]; then
        echo "ERROR: 操作シナリオの一覧表とYAMLが一致しません: $file ($scenario_key)" >&2
        scenario_contract_error=1
        continue
      fi
    fi
    [ -z "$scene_name" ] && continue
    expected="$(LC_ALL=C awk -F'\t' -v s="$scene_name" '$1 == s { print $2; exit }' "$tmp_expected")"
    scenario_rownum=$((scenario_rownum + 1))
    printf '%s\tscenario\t%s-scenario-%d\t%s\t%s\t%s\t%s\t%s\t%s\tscreen\n' \
      "$screen_key" "$screen_key" "$scenario_rownum" "$scene_name" "$viewpoint_key" "$precondition" "" "$expected" "$screen_test_case_key" >> "$tmp_tsv"
  done < "$tmp_top"
  rm -f "$tmp_top" "$tmp_expected" "$tmp_yaml"
done < <(find "$output_dir/$screen_unit_root" -mindepth 3 -maxdepth 3 -type f \
  \( -path "*/screen-*/テスト設計/操作シナリオ仕様書.md" -o -path "*/screen-*/テスト項目書/操作シナリオ仕様書.md" \) -print0 2>/dev/null)

if [ "$scenario_contract_error" -ne 0 ]; then
  exit 1
fi

# --- 非画面種別(API・テーブル・バッチ・帳票・外部連携等)のテスト設計書「§2 テストケース一覧」の集約 ---
# 対象種別は screenUnitRoot 以外の全 <種別>UnitRoot キーを output-layout.json から動的に導く
# (種別名をスクリプトへ直書きしないため。新種別追加時も本スクリプトの変更は不要)。
# §2 テストケース一覧は キー・ケースの名前・対応する観点のキー・区分の4列のみを持ち、
# 入力値・操作手順・期待結果（アサーション）に相当する列を持たない(§3〜§4に分散する構成)。
# そのため input・steps・expected は空文字で埋める(既存スキーマは変更せず、既存の必須文字列型を満たす)。
section_slice_awk='
  BEGIN { in_section = 0 }
  {
    line = $0
    if (line ~ startRe) { in_section = 1; next }
    if (in_section && line ~ /^##[ \t]/) { in_section = 0 }
    if (in_section) print
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

    scanned_unit=$((scanned_unit + 1))

    case "$(basename "$file")" in
      *単体*) document_scope="function" ;;
      *APIテスト*) document_scope="api-contract" ;;
      *) document_scope="test-design" ;;
    esac

    LC_ALL=C awk -v startRe='^## §2 テストケース一覧[ \t]*$' "$section_slice_awk" "$file" \
      | LC_ALL=C awk -v firstHeader="キー" -v wantNames="対応する観点のキー" "$extract_named_table_awk" 2>"$tmp_excl" \
      | awk -v ownerKey="$unit_key" -v documentScope="$document_scope" -v sourceKind="$kind" -F'\t' '
        {
          rownum++
          printf "%s\tunit\t%s-%s-unit-%d\t%s\t%s\t\t\t\t\t%s\n", ownerKey, ownerKey, documentScope, rownum, $1, $2, sourceKind
        }
      ' >> "$tmp_tsv"
    excl_n="$(cat "$tmp_excl" 2>/dev/null || true)"
    [ -z "$excl_n" ] && excl_n=0
    excluded_unit=$((excluded_unit + excl_n))
  done < <(find "$output_dir/$kind_root" -mindepth 3 -maxdepth 3 -type f \
    -path "*/${kind}-*/${unit_test_design_dir}/*テスト設計書.md" -print0 2>/dev/null)
done <<< "$non_screen_kind_keys"

if [ ! -s "$tmp_tsv" ]; then
  jq -n \
    --arg generatedAt "$generated_at" \
    --argjson scannedByTestType "{\"unit\":$scanned_unit,\"integration\":$scanned_integration,\"scenario\":$scanned_scenario}" \
    --argjson excludedExampleRows "{\"unit\":$excluded_unit,\"integration\":$excluded_integration,\"scenario\":$excluded_scenario}" \
    '{
      unitKind: "test_case",
      generatedAt: $generatedAt,
      units: [],
      summary: {
        totalCount: 0,
        byTestType: { unit: 0, integration: 0, scenario: 0 },
        byScreen: {},
        scannedByTestType: $scannedByTestType,
        excludedExampleRows: $excludedExampleRows
      }
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
    expected: .[7],
    screenTestCaseKey: .[8],
    sourceKind: .[9]
  })
' < "$tmp_tsv")"

jq -n \
  --arg generatedAt "$generated_at" \
  --argjson units "$units_json" \
  --argjson scannedByTestType "{\"unit\":$scanned_unit,\"integration\":$scanned_integration,\"scenario\":$scanned_scenario}" \
  --argjson excludedExampleRows "{\"unit\":$excluded_unit,\"integration\":$excluded_integration,\"scenario\":$excluded_scenario}" \
  '
  {
    unitKind: "test_case",
    generatedAt: $generatedAt,
    units: $units,
    summary: {
      totalCount: ($units | length),
      byTestType: ({unit: 0, integration: 0, scenario: 0} + ($units | group_by(.testType) | map({key: .[0].testType, value: length}) | from_entries)),
      byScreen: ($units | group_by(.screenKey) | map({key: .[0].screenKey, value: length}) | from_entries),
      scannedByTestType: $scannedByTestType,
      excludedExampleRows: $excludedExampleRows
    }
  }
  ' > "$output_file"
