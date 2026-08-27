#!/usr/bin/env bash
# 種別別一覧スキル群(generating-<種別>-list-for-reverse-docs)共通エンジン: 種別対応HTML一覧生成ディスパッチャ。
# unit_kind=screen なら build-screen-list.sh、unit_kind=feature なら build-feature-list.sh に委譲、他種別は汎用テンプレートから生成する。
#
# Usage: build-unit-list.sh <manifest.json> <output-html-path> [--unit-kind <kind>] [--repo-root <パス>] [--source-file-root <パス>]
#   --repo-root <パス>: 元データの sourceDir を解決する基準にするディレクトリ。省略すると元データの所在から上へ辿って探す
#   --source-file-root <パス>: sourceDirを保持し、sourceFileの実在だけを対象プロジェクトルート基準で検査する
#
# unit_kind=screen の場合:
#   同ディレクトリの build-screen-list.sh に <manifest.json> <output-html-path> をそのまま渡して
#   委譲する。従来の画面一覧.HTML生成と完全に同じ挙動になり、exit codeもそのまま返す。
#
# unit_kind=screen 以外の場合:
#   1. validate-manifest.sh <manifest.json> --unit-kind <kind> で検証(PASSしない限り生成しない)
#   2. delivery-payload/templates/unit-list/unit-list-template.html を土台に、jqでマニフェストJSONをパースして
#      プレースホルダ・注入マーカーを機械的に置換し、決定的にHTMLを生成する
#
# 汎用マニフェストの入力JSONスキーマ(契約。詳細は references/kind-detection-strategies.md):
# {
#   "generatedAt": "...", "sourceDir": "...", "unitKind": "api|table|batch|report|external|message|test_viewpoint|test_case",
#   "strategy": {"extractionMethod": "...", "approvedByUser": true, ...},
#   "detectionSummary": {"method": "...", "unitCount": 0, "unresolvedCount": 0},
#   "units": [{
#     "unitKey": "...", "unitId": null, "unitNameGuess": "...", "kind": "種別固有の区分値",
#     "identifier": "...", "sourceFile": "...", "confidence": "high|medium|low",
#     "fileCount": 0, "files": [], "detectionMethod": "..."
#   }]
# }
#
# unit_kind=message の専用契約:
#   トップレベルに sourceDir(string), strategy(object), detectionSummary(object), units(array),
#   summary(object) を持つ。units[].sourceFile は単一文字列ではなく string[] とし、複数の原本
#   ファイルを列挙する。message 専用の詳細契約は delivery-payload/references/manifest-schema-extensions.md に記載する。
#
# 出力: <output-html-path> に単一HTMLを書き出す。外部依存はMaterial Symbols OutlinedのGoogle Fonts CDNだけを許可する。
#   - kind=unresolved は「要手動確認」セクションの別テーブルへ(0件なら「なし」)
#   - manifest.json の内容は <script type="application/json" id="unit-manifest"> にそのまま埋め込む
#   - EXTRA_TILES (種別内訳タイルマーカー・任意): unit_kind=test_case の場合のみ、
#     summary.byTestType(unit/integration/scenario)の3種内訳タイルを挿入する。0件も表示する。
#     他のunit_kindでは空文字列を注入し、テンプレートにマーカー文字列を残さない

set -euo pipefail

# --- --self-test モード ---
# render_template()の単一パス置換が、埋め込み値中の他マーカー文字列衝突・
# バックスラッシュ・山括弧を含む自由記述フィールドでも誤爆しないことを検証する。
# unit_kind=screen は build-screen-list.sh へ委譲する構造のため、フィクスチャは
# --unit-kind api を明示指定してscreen以外の経路を検証する。
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-unit-list-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/routes"
  cat > "$tmp/src/routes/users.ts" <<'EOF'
export function usersRoute() {}
EOF

  extract_manifest_json() {
    sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' "$1" | sed '1d;$d'
  }

  # sourceDir/sourceFileが絶対パス(1-102対応で正規化される)なマニフェストの期待値を、
  # 生成側と同じ規則(sourceDirはbasename・sourceFileはsourceDirプレフィックス除去)で
  # 正規化してから比較するためのヘルパー。相対パスの場合は無加工。
  expected_normalized_manifest() {
    jq -c -S '
      def normPath($origSd):
        if (type == "string") and startswith("/") then
          if startswith($origSd) then
            (.[($origSd | length):] | ltrimstr("/"))
          else
            (split("/") | last)
          end
        else
          .
        end;
      (.sourceDir // "") as $origSd
      | .sourceDir |= (if test("^/") then (split("/") | last) else . end)
      | .units |= (map(
          if has("sourceFile") then
            .sourceFile |= (if type == "array" then map(normPath($origSd)) else normPath($origSd) end)
          else . end
        ))
    ' "$1"
  }

  # --- ケースa: バックスラッシュ(正規表現風 \d+)を含む identifier ---
  local manifest_a="$tmp/manifest-a.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg sourceFile "$tmp/src/routes/users.ts" \
    --arg identifier 'GET /api/users/\d+' \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "api",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [
        {
          unitKey: "users-list",
          kind: "endpoint",
          identifier: $identifier,
          unitNameGuess: "ユーザー一覧(OK) API-001",
          sourceFile: $sourceFile,
          confidence: "high",
          fileCount: 1,
          detectionMethod: "manual"
        }
      ]
    }' > "$manifest_a"

  local out_a="$tmp/out-a.html"
  local _gt_out_a_run _gt_diff_a
  if _gt_out_a_run="$(bash "$script_path" "$manifest_a" "$out_a" --unit-kind api 2>&1)"; then
    local embedded_a="$tmp/embedded-a.json"
    local expected_a="$tmp/expected-a.json"
    extract_manifest_json "$out_a" | jq -c -S . > "$embedded_a" 2>/dev/null || true
    # sourceDir/sourceFileは絶対パス(1-102対応で正規化される)なので、期待値も同じ正規化を適用してから比較する
    expected_normalized_manifest "$manifest_a" > "$expected_a"
    if _gt_diff_a="$(diff -u "$expected_a" "$embedded_a" 2>&1)"; then
      echo "  [PASS] ケースa: バックスラッシュ(\\d+)を含むidentifierでも埋め込みJSONが原本と完全一致"
    else
      echo "  [FAIL] ケースa: バックスラッシュを含むidentifierで埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      printf '%s\n' "$_gt_diff_a" | sed 's/^/    /' >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースa: 生成コマンド自体が失敗した" >&2
    printf '%s\n' "$_gt_out_a_run" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- ケースb: 山括弧+実マーカー文字列そのものを含む unitNameGuess ---
  local manifest_b="$tmp/manifest-b.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg sourceFile "$tmp/src/routes/users.ts" \
    --arg unitNameGuess '<div>ユーザー一覧</div>{{MANIFEST_JSON}}<!--UNIT_TABLE_ROWS-->' \
    --arg unitKey "'\" onmouseover=\"alert(1)'" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "api",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [
        {
          unitKey: $unitKey,
          kind: "endpoint",
          identifier: "GET /api/users",
          unitNameGuess: $unitNameGuess,
          sourceFile: $sourceFile,
          confidence: "high",
          fileCount: 1,
          detectionMethod: "manual"
        }
      ]
    }' > "$manifest_b"

  local out_b="$tmp/out-b.html"
  local _gt_out_b_run _gt_diff_b
  if _gt_out_b_run="$(bash "$script_path" "$manifest_b" "$out_b" --unit-kind api 2>&1)"; then
    local embedded_b="$tmp/embedded-b.json"
    local expected_b="$tmp/expected-b.json"
    extract_manifest_json "$out_b" | jq -c -S . > "$embedded_b" 2>/dev/null || true
    # sourceDir/sourceFileは絶対パス(1-102対応で正規化される)なので、期待値も同じ正規化を適用してから比較する
    expected_normalized_manifest "$manifest_b" > "$expected_b"
    if _gt_diff_b="$(diff -u "$expected_b" "$embedded_b" 2>&1)"; then
      if grep -Fq 'data-unit-key="&#39;&quot; onmouseover=&quot;alert(1)&#39;"' "$out_b" \
        && ! grep -Fq 'onmouseover="alert(1)' "$out_b"; then
        echo "  [PASS] ケースb: 引用符を含むunitKeyを属性値として安全にエスケープし、埋め込みJSONも原本と完全一致"
      else
        echo "  [FAIL] ケースb: 引用符を含むunitKeyで属性注入を防止できていない" >&2
        rc=1
      fi
    else
      echo "  [FAIL] ケースb: 山括弧+マーカー文字列衝突で埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      printf '%s\n' "$_gt_diff_b" | sed 's/^/    /' >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースb: 生成コマンド自体が失敗した" >&2
    printf '%s\n' "$_gt_out_b_run" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- 回帰確認: 通常マニフェストの可視テーブル出力と machine gate(validate-manifest.sh)への影響なし ---
  local manifest_normal="$tmp/manifest-normal.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg sourceFile "$tmp/src/routes/users.ts" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "api",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [
        {
          unitKey: "users-list",
          kind: "endpoint",
          identifier: "GET /api/users",
          unitNameGuess: "ユーザー一覧(OK) API-001",
          sourceFile: $sourceFile,
          confidence: "high",
          fileCount: 1,
          detectionMethod: "manual"
        }
      ]
    }' > "$manifest_normal"

  local out_normal="$tmp/out-normal.html"
  local regression_ok=1
  if ! bash "$script_path" "$manifest_normal" "$out_normal" --unit-kind api >/dev/null 2>&1; then
    regression_ok=0
  elif ! grep -q '<code>GET /api/users</code>' "$out_normal"; then
    regression_ok=0
  elif ! grep -q '<td>ユーザー一覧</td>' "$out_normal" || grep -q '<td>ユーザー一覧(OK)' "$out_normal"; then
    regression_ok=0
  elif ! bash "$script_dir/validate-manifest.sh" "$manifest_normal" --unit-kind api >/dev/null 2>&1; then
    regression_ok=0
  fi

  # --- 1-82: 区分が1種類なら列を省略し、2種類以上なら表示する ---
  local kind_column_ok=1
  local normal_table
  normal_table="$(sed -n '/<table class="units" id="unit-table" data-unit-table>/,/<\/table>/p' "$out_normal")"
  if grep -Fq '<th data-key="kind">区分</th>' <<<"$normal_table" \
    || grep -Fq '<span class="badge kind-generic">endpoint</span>' <<<"$normal_table"; then
    kind_column_ok=0
  fi
  local manifest_multiple_kinds="$tmp/manifest-multiple-kinds.json" out_multiple_kinds="$tmp/out-multiple-kinds.html"
  jq '.units += [(.units[0] | .unitKey = "users-detail" | .unitNameGuess = "ユーザー詳細" | .identifier = "GET /api/users/:id" | .kind = "entrypoint")] | .detectionSummary.unitCount = 2' "$manifest_normal" > "$manifest_multiple_kinds"
  local multiple_kinds_table
  if ! bash "$script_path" "$manifest_multiple_kinds" "$out_multiple_kinds" --unit-kind api >/dev/null 2>&1; then
    kind_column_ok=0
  else
    multiple_kinds_table="$(sed -n '/<table class="units" id="unit-table" data-unit-table>/,/<\/table>/p' "$out_multiple_kinds")"
    if ! grep -Fq '<th data-key="kind">区分</th>' <<<"$multiple_kinds_table" \
      || ! grep -Fq '<span class="badge kind-generic">endpoint</span>' <<<"$multiple_kinds_table" \
      || ! grep -Fq '<span class="badge kind-generic">entrypoint</span>' <<<"$multiple_kinds_table"; then
      kind_column_ok=0
    fi
  fi
  if [ "$kind_column_ok" -eq 1 ]; then
    echo "  [PASS] 1-82: 区分列は値が2種類以上のときだけ出力される"
  else
    echo "  [FAIL] 1-82: 区分列の出力条件が不正" >&2
    rc=1
  fi

  # 4種類の末尾マーカーを除去し、語頭・語中のOKは保持する。
  local marker_manifest="$tmp/manifest-marker-forms.json" marker_out="$tmp/out-marker-forms.html"
  jq '
    .detectionSummary.unitCount = 11
    | .units = [
        ["marker-space", "GET /marker-space", "末尾空白 OK"],
        ["marker-paren", "GET /marker-paren", "半角括弧(OK)"],
        ["marker-id", "GET /marker-id", "識別子付き(OK) API-001"],
        ["marker-wide", "GET /marker-wide", "全角括弧（補足）OK"],
        ["marker-leading", "GET /marker-leading", "OK処理"],
        ["marker-middle", "GET /marker-middle", "決済OK着地"],
        ["issue1-55-a", "GET /issue1-55-a", "名称A(OK) (identA)"],
        ["issue1-55-b", "GET /issue1-55-b", "名称F(OK) identF"],
        ["issue1-55-c", "GET /issue1-55-c", "名称B(OK)"],
        ["issue1-55-d", "GET /issue1-55-d", "名称C（内訳） OK"],
        ["issue1-55-e", "GET /issue1-55-e", "名称D OK"]
      ]
      | .units |= map({
          unitKey: .[0], kind: "endpoint", identifier: .[1], unitNameGuess: .[2],
          sourceFile: $sourceFile, confidence: "high", fileCount: 1, detectionMethod: "manual"
        })
  ' --arg sourceFile "$tmp/src/routes/users.ts" "$manifest_normal" > "$marker_manifest"
  if ! bash "$script_path" "$marker_manifest" "$marker_out" --unit-kind api >/dev/null 2>&1 \
    || ! grep -q '<td>末尾空白</td>' "$marker_out" \
    || ! grep -q '<td>半角括弧</td>' "$marker_out" \
    || ! grep -q '<td>識別子付き</td>' "$marker_out" \
    || ! grep -q '<td>全角括弧（補足）</td>' "$marker_out" \
    || ! grep -q '<td>OK処理</td>' "$marker_out" \
    || ! grep -q '<td>決済OK着地</td>' "$marker_out" \
    || ! grep -q '<td>名称A</td>' "$marker_out" \
    || ! grep -q '<td>名称F</td>' "$marker_out" \
    || ! grep -q '<td>名称B</td>' "$marker_out" \
    || ! grep -q '<td>名称C（内訳）</td>' "$marker_out" \
    || ! grep -q '<td>名称D</td>' "$marker_out"; then
    regression_ok=0
  fi

  # --- 入力契約: 明示種別とmanifest.unitKindの不一致、およびgeneratedAt:nullを生成前に拒否 ---
  local contract_ok=1
  local manifest_kind_mismatch="$tmp/manifest-kind-mismatch.json"
  local manifest_generated_at_null="$tmp/manifest-generated-at-null.json"
  local screen_generated_at_null="$tmp/screen-generated-at-null.json"
  local screen_without_unit_kind="$tmp/screen-without-unit-kind.json"
  jq '.unitKind = "table"' "$manifest_normal" > "$manifest_kind_mismatch"
  jq '.generatedAt = null' "$manifest_normal" > "$manifest_generated_at_null"
  jq -n --arg sourceDir "$tmp/src" --arg entryFile "$tmp/src/routes/users.ts" '{
    generatedAt: null,
    sourceDir: $sourceDir,
    strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
    detectionSummary: {screenCount: 1, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
    screens: [{screenKey: "users", kind: "route", route: "/users", entryFile: $entryFile, detectionMethod: "manual", confidence: "high", screenType: "list", accountGroup: "common", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false}]
  }' > "$screen_generated_at_null"
  jq '.generatedAt = "2026-01-01T00:00:00Z"' "$screen_generated_at_null" > "$screen_without_unit_kind"
  if bash "$script_path" "$manifest_kind_mismatch" "$tmp/kind-mismatch.html" --unit-kind api >"$tmp/kind-mismatch.log" 2>&1 \
    || ! grep -Fq -- '--unit-kind (api) must match manifest.unitKind (table)' "$tmp/kind-mismatch.log"; then
    contract_ok=0
  fi
  if bash "$script_path" "$manifest_generated_at_null" "$tmp/generated-at-null.html" --unit-kind api >"$tmp/generated-at-null.log" 2>&1 \
    || ! grep -Fq 'generatedAt must be a non-empty string' "$tmp/generated-at-null.log"; then
    contract_ok=0
  fi
  if bash "$script_path" "$screen_generated_at_null" "$tmp/screen-generated-at-null.html" >"$tmp/screen-generated-at-null.log" 2>&1 \
    || ! grep -Fq 'generatedAt must be a non-empty string' "$tmp/screen-generated-at-null.log"; then
    contract_ok=0
  fi
  if ! bash "$script_path" "$screen_without_unit_kind" "$tmp/screen-without-unit-kind.html" --unit-kind screen >/dev/null 2>&1; then
    contract_ok=0
  fi
  if [ "$contract_ok" -eq 1 ]; then
    echo "  [PASS] 入力契約: --unit-kind不一致とgeneratedAt:nullをscreen委譲前を含めて拒否"
  else
    echo "  [FAIL] 入力契約: --unit-kind不一致またはgeneratedAt:nullを受理した" >&2
    rc=1
  fi

  if [ "$regression_ok" -eq 1 ]; then
    echo "  [PASS] 回帰確認: 末尾4形式を除去し語頭・語中OKを保持、validate-manifest.shも引き続きPASS"
  else
    echo "  [FAIL] 回帰確認: 可視テーブル内容またはvalidate-manifest.shのPASSに退行が発生した" >&2
    rc=1
  fi

  # --- 1-65: 1ユニットに役割の異なる関連資料が複数ある場合の描画契約 ---
  local related_docs_manifest="$tmp/manifest-related-docs.json" related_docs_out="$tmp/out-related-docs.html"
  jq '.units[0].designDocPath = "../docs/users-basic.html"
      | .units[0].detailDocPath = "../docs/users-detail.html"' \
    "$manifest_normal" > "$related_docs_manifest"
  local related_docs_ok=1
  if ! bash "$script_path" "$related_docs_manifest" "$related_docs_out" --unit-kind api >/dev/null 2>&1; then
    related_docs_ok=0
  elif ! sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' "$related_docs_out" \
      | sed '1d;$d' \
      | jq -e '.units[0]
        | .designDocPath == "../docs/users-basic.html"
          and .detailDocPath == "../docs/users-detail.html"' >/dev/null 2>&1; then
    related_docs_ok=0
  elif ! grep -Fq "{label: '基本', docs: [" "$related_docs_out" \
    || ! grep -Fq "{label: '詳細', docs: [" "$related_docs_out" \
    || ! LC_ALL=C grep -Fq "{label: 'API基本設計書', pathField: 'designDocPath', kind: 'basic'}" "$related_docs_out" \
    || ! LC_ALL=C grep -Fq "{label: 'API詳細設計書', pathField: 'detailDocPath', kind: 'detail'}" "$related_docs_out" \
    || ! grep -Fq 'link.href = path;' "$related_docs_out" \
    || ! grep -Fq 'link.textContent = index === 0 ? group.label : doc.shortLabel;' "$related_docs_out"; then
    related_docs_ok=0
  fi
  if [ "$related_docs_ok" -eq 1 ]; then
    echo "  [PASS] 1-65: 異なる役割の関連資料2件を役割別リンクとして描画できる契約を出力"
  else
    echo "  [FAIL] 1-65: 関連資料2件のパス・役割別ラベル・リンク描画契約が不正" >&2
    rc=1
  fi

  # --- 1-83: 資料リンクのラベルを種別ごとの文書名(design-unit-layout.json)から導く ---
  # api: 「API基本設計書」「API詳細設計書」($related_docs_out を1-65と共用して確認)
  # table: 基本=「論理データモデル」、詳細=「テーブル定義書」(1-65のapiとは異なる文書名になり食い違いが解消することを示す)
  # message: design-unit-layout.jsonに宣言が無いため既定値「基本設計書」へフォールバックする(後方互換)
  # feature: build-unit-list.shがbuild-feature-list.shへ委譲した先でも「機能設計書」が導かれる
  local doc_label_ok=1
  if ! LC_ALL=C grep -Fq "{label: 'API基本設計書', pathField: 'designDocPath', kind: 'basic'}" "$related_docs_out" \
    || ! LC_ALL=C grep -Fq "{label: 'API詳細設計書', pathField: 'detailDocPath', kind: 'detail'}" "$related_docs_out"; then
    doc_label_ok=0
  fi

  local table_manifest="$tmp/manifest-table.json" table_out="$tmp/out-table.html"
  jq -n --arg sourceDir "$tmp/src" --arg sourceFile "$tmp/src/routes/users.ts" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "table",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [
      {
        unitKey: "users",
        kind: "table",
        identifier: "users",
        unitNameGuess: "ユーザーテーブル",
        designDocPath: "../docs/users-basic.html",
        detailDocPath: "../docs/users-detail.html",
        sourceFile: $sourceFile,
        confidence: "high",
        fileCount: 1,
        detectionMethod: "manual"
      }
    ]
  }' > "$table_manifest"
  if ! bash "$script_path" "$table_manifest" "$table_out" --unit-kind table >/dev/null 2>&1; then
    doc_label_ok=0
  elif ! LC_ALL=C grep -Fq "{label: '論理データモデル', pathField: 'designDocPath', kind: 'basic'}" "$table_out" \
    || ! LC_ALL=C grep -Fq "{label: 'テーブル定義書', pathField: 'detailDocPath', kind: 'detail'}" "$table_out"; then
    doc_label_ok=0
  fi

  local message_label_manifest="$tmp/manifest-message-label.json" message_label_out="$tmp/out-message-label.html"
  jq -n --arg sourceDir "$tmp/src" '{
    generatedAt: "2026-01-01T00:00:00Z", sourceDir: $sourceDir, unitKind: "message",
    strategy: {extractionMethod: "message-definition-table", approvedByUser: false, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {method: "message-definition-table", unitCount: 1, unresolvedCount: 0},
    units: [{unitKey: "login-required", unitNameGuess: "ログインしてください", kind: "error", identifier: "login-required", confidence: "high", messageText: "必須です", messageType: "error", sourceFile: ["src/auth.ts"], usedScreen: "ログイン", designDocPath: "../docs/x.html"}],
    summary: {totalCount: 1, byType: {error: 1}}
  }' > "$message_label_manifest"
  if ! bash "$script_path" "$message_label_manifest" "$message_label_out" --unit-kind message >/dev/null 2>&1; then
    doc_label_ok=0
  elif ! LC_ALL=C grep -Fq "{label: '基本設計書', pathField: 'designDocPath', kind: 'basic'}" "$message_label_out"; then
    doc_label_ok=0
  fi

  local feature_label_manifest="$tmp/manifest-feature-label.json" feature_label_out="$tmp/out-feature-label.html"
  jq -n --arg sourceDir "$tmp/src" --arg sourceFile "$tmp/src/routes/users.ts" '{
    generatedAt: "2026-01-01T00:00:00Z", sourceDir: $sourceDir, unitKind: "feature",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [{unitKey: "user-list-view", kind: "feature", category: "ユーザー管理", identifier: "/master/users", unitNameGuess: "ユーザー一覧表示", summary: "一覧を表示する", designDocPath: "../docs/users-basic.html", sourceFile: $sourceFile, relatedScreens: [], relatedApis: [], relatedTables: [], confidence: "high", fileCount: 1, detectionMethod: "manual"}]
  }' > "$feature_label_manifest"
  if ! bash "$script_path" "$feature_label_manifest" "$feature_label_out" --unit-kind feature >/dev/null 2>&1; then
    doc_label_ok=0
  elif ! LC_ALL=C grep -Fq '機能設計書' "$feature_label_out"; then
    doc_label_ok=0
  fi

  if [ "$doc_label_ok" -eq 1 ]; then
    echo "  [PASS] 1-83: 資料リンクのラベルを種別ごとの文書名から導く(api/table/message/feature)"
  else
    echo "  [FAIL] 1-83: 種別ごとの文書名から資料リンクのラベルを導けていない" >&2
    rc=1
  fi

  # --- 派生一覧: 専用validator経路・表示列・埋め込み完全JSONを確認 ---
  local derived_ok=1
  local message_manifest="$tmp/message.json" message_out="$tmp/message.html"
  jq -n --arg sourceDir "$tmp/src" '{
    generatedAt:"2026-01-01T00:00:00Z", sourceDir:$sourceDir, unitKind:"message",
    strategy:{extractionMethod:"message-definition-table",approvedByUser:false,unitIdRegex:null,excludePatterns:[]},
    detectionSummary:{method:"message-definition-table",unitCount:1,unresolvedCount:0},
    units:[{unitKey:"login-required",unitNameGuess:"ログインしてください",kind:"error",identifier:"login-required",confidence:"high",messageText:"</script><script>alert(1)</script>",messageType:"error",sourceFile:["src/auth.ts","src/guard.ts"],usedScreen:"ログイン"}],
    summary:{totalCount:1,byType:{error:1}}
  }' > "$message_manifest"
  if ! bash "$script_path" "$message_manifest" "$message_out" --unit-kind message >/dev/null 2>&1 \
    || ! grep -q '<code>login-required</code>' "$message_out" \
    || ! grep -q 'href="../../index.html"' "$message_out" \
    || ! grep -q 'source-file' "$message_out"; then
    derived_ok=0
  fi
  extract_manifest_json "$message_out" | jq -cS . > "$tmp/message-embedded.json" 2>/dev/null || derived_ok=0
  # sourceDir/sourceFileは絶対パス(1-102対応で正規化される)なので、期待値も同じ正規化を適用してから比較する
  expected_normalized_manifest "$message_manifest" > "$tmp/message-original.json"
  diff -q "$tmp/message-embedded.json" "$tmp/message-original.json" >/dev/null 2>&1 || derived_ok=0
  if grep -Fq '</script><script>alert(1)</script>' "$message_out" \
    || ! grep -Fq '\u003c/script\u003e\u003cscript\u003ealert(1)\u003c/script\u003e' "$message_out"; then
    derived_ok=0
  fi

  # --portal-dir 明示時は既定値で上書きせず、指定先への相対リンクを維持する。
  local portal_out="$tmp/derived/message/message.html"
  mkdir -p "$(dirname "$portal_out")" "$tmp/project-portal"
  if ! bash "$script_path" "$message_manifest" "$portal_out" --unit-kind message --portal-dir "$tmp/project-portal" >/dev/null 2>&1 \
    || ! grep -q 'href="../../project-portal/index.html"' "$portal_out"; then
    derived_ok=0
  fi

  local viewpoint_manifest="$tmp/viewpoint.json" viewpoint_out="$tmp/viewpoint.html"
  jq -n '{
    unitKind:"test_viewpoint", generatedAt:"2026-01-01T00:00:00Z",
    units:[{unitKey:"api-login-unit-1",screenKey:"api-login",sourceKind:"api",testType:"unit",category:"入力",viewpoint:"必須入力"}],
    summary:{totalCount:1,byTestType:{unit:1},byScreen:{"api-login":1}}
  }' > "$viewpoint_manifest"
  if ! bash "$script_path" "$viewpoint_manifest" "$viewpoint_out" --unit-kind test_viewpoint >/dev/null 2>&1 \
    || ! grep -q '<code>api-login</code>' "$viewpoint_out" \
    || ! grep -Fq '"key":"sourceKind"' "$viewpoint_out" \
    || ! grep -Fq '"sourceKind":"api"' "$viewpoint_out" \
    || ! grep -q 'href="../../index.html"' "$viewpoint_out"; then
    derived_ok=0
  fi
  extract_manifest_json "$viewpoint_out" | jq -cS . > "$tmp/viewpoint-embedded.json" 2>/dev/null || derived_ok=0
  jq -cS . "$viewpoint_manifest" > "$tmp/viewpoint-original.json"
  diff -q "$tmp/viewpoint-embedded.json" "$tmp/viewpoint-original.json" >/dev/null 2>&1 || derived_ok=0

  local test_case_manifest="$tmp/test-case.json" test_case_out="$tmp/test-case.html"
  jq -n '{
    unitKind:"test_case", generatedAt:"2026-01-01T00:00:00Z",
    units:[{unitKey:"api-login-unit-1",screenKey:"api-login",sourceKind:"api",testType:"unit",unitNameGuess:"合計0円-登録不可",kind:"unit",caseKey:"合計0円-登録不可",viewpointKey:"金額-下限境界",input:"total: 0",steps:"",expected:"isRegisterableがfalseを返す"}],
    summary:{totalCount:1,byTestType:{unit:1},byScreen:{"api-login":1}}
  }' > "$test_case_manifest"
  if ! bash "$script_path" "$test_case_manifest" "$test_case_out" --unit-kind test_case >/dev/null 2>&1 \
    || ! grep -q '<code>api-login</code>' "$test_case_out" \
    || ! grep -Fq '"key":"sourceKind"' "$test_case_out" \
    || ! grep -Fq '"sourceKind":"api"' "$test_case_out" \
    || ! grep -q 'href="../../index.html"' "$test_case_out"; then
    derived_ok=0
  fi
  extract_manifest_json "$test_case_out" | jq -cS . > "$tmp/test-case-embedded.json" 2>/dev/null || derived_ok=0
  jq -cS . "$test_case_manifest" > "$tmp/test-case-original.json"
  diff -q "$tmp/test-case-embedded.json" "$tmp/test-case-original.json" >/dev/null 2>&1 || derived_ok=0

  # test_case以外(api/message)に未置換のEXTRA_TILESマーカーが残っていないことを確認する
  # (テンプレート冒頭のマーカー一覧コメント内には"EXTRA_TILES"という語自体が残るため、
  #  未置換を示すコメント記法込みの文字列で判定する)
  if grep -Fq '<!--EXTRA_TILES-->' "$out_normal" "$message_out"; then
    derived_ok=0
  fi

  # 種別内訳: 単体/結合/操作シナリオの3種を含むmanifestで、3表示語がすべて出現すること
  local test_case_all_manifest="$tmp/test-case-alltypes.json" test_case_all_out="$tmp/test-case-alltypes.html"
  jq -n '{
    unitKind:"test_case", generatedAt:"2026-01-01T00:00:00Z",
    units:[
      {unitKey:"screen-login-unit-1",screenKey:"screen-login",sourceKind:"screen",testType:"unit",unitNameGuess:"合計0円-登録不可",kind:"unit",caseKey:"合計0円-登録不可",viewpointKey:"金額-下限境界",input:"total: 0",steps:"",expected:"isRegisterableがfalseを返す"},
      {unitKey:"screen-login-integration-1",screenKey:"screen-login",sourceKind:"screen",testType:"integration",unitNameGuess:"登録実行-一覧反映",kind:"integration",caseKey:"登録実行-一覧反映",viewpointKey:"登録-一覧反映",input:"必須項目入力済み",steps:"登録ボタンを押す",expected:"一覧に新規行が追加される"},
      {unitKey:"screen-login-scenario-1",screenKey:"screen-login",sourceKind:"screen",testType:"scenario",unitNameGuess:"検索条件の絞り込み",kind:"scenario",caseKey:"検索条件の絞り込み",viewpointKey:"操作後-画面反映",input:"一覧に複数件表示中",steps:"",expected:"検索実行後、一覧テーブルが即座に更新される。"}
    ],
    summary:{totalCount:3,byTestType:{unit:1,integration:1,scenario:1},byScreen:{"screen-login":3}}
  }' > "$test_case_all_manifest"
  if ! bash "$script_path" "$test_case_all_manifest" "$test_case_all_out" --unit-kind test_case >/dev/null 2>&1 \
    || ! grep -Fq '>単体</span>' "$test_case_all_out" \
    || ! grep -Fq '>結合</span>' "$test_case_all_out" \
    || ! grep -Fq '>操作シナリオ</span>' "$test_case_all_out"; then
    derived_ok=0
  fi

  # 種別内訳: 操作シナリオが0件のmanifestで、0件タイルが表示されること
  local test_case_zero_manifest="$tmp/test-case-zero-scenario.json" test_case_zero_out="$tmp/test-case-zero-scenario.html"
  jq -n '{
    unitKind:"test_case", generatedAt:"2026-01-01T00:00:00Z",
    units:[
      {unitKey:"screen-login-unit-1",screenKey:"screen-login",sourceKind:"screen",testType:"unit",unitNameGuess:"合計0円-登録不可",kind:"unit",caseKey:"合計0円-登録不可",viewpointKey:"金額-下限境界",input:"total: 0",steps:"",expected:"isRegisterableがfalseを返す"},
      {unitKey:"screen-login-integration-1",screenKey:"screen-login",sourceKind:"screen",testType:"integration",unitNameGuess:"登録実行-一覧反映",kind:"integration",caseKey:"登録実行-一覧反映",viewpointKey:"登録-一覧反映",input:"必須項目入力済み",steps:"登録ボタンを押す",expected:"一覧に新規行が追加される"}
    ],
    summary:{totalCount:2,byTestType:{unit:1,integration:1,scenario:0},byScreen:{"screen-login":2}}
  }' > "$test_case_zero_manifest"
  if ! bash "$script_path" "$test_case_zero_manifest" "$test_case_zero_out" --unit-kind test_case >/dev/null 2>&1 \
    || ! grep -Fq '<div class="tile"><strong>0</strong>操作シナリオ件数</div>' "$test_case_zero_out"; then
    derived_ok=0
  fi

  if [ "$derived_ok" -eq 1 ]; then
    echo "  [PASS] 派生一覧: message/test_viewpoint/test_caseの表示値・埋め込み完全JSON・戻りリンクを維持"
  else
    echo "  [FAIL] 派生一覧: message/test_viewpoint/test_caseの完全契約出力に退行" >&2
    rc=1
  fi

  # --- 1-123: 拡張マニフェスト(派生フィールド付き)でも「埋め込み == 復元元」が成り立つこと ---
  # screen種別はbuild-screen-list.shへ委譲されるため、category/permissions/designDocStatus/
  # existingTestCount/sourceHashを付与した拡張マニフェストで検証する。
  local roundtrip_ok=1
  mkdir -p "$tmp/src/screens"
  cat > "$tmp/src/screens/Home.tsx" <<'EOF'
export default function Home() { return null }
EOF
  local ext_manifest="$tmp/screen-manifest-ext.json" ext_out="$tmp/screen-manifest-ext.html"
  jq -n --arg entryFile "$tmp/src/screens/Home.tsx" --arg sourceDir "$tmp/src" '{
    generatedAt: "2026-07-28T00:00:00Z",
    sourceDir: $sourceDir,
    strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
    detectionSummary: {screenCount: 1, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
    screens: [{
      screenKey: "home-screen", kind: "route", route: "/home", entryFile: $entryFile,
      detectionMethod: "manual", confidence: "high", screenNameGuess: "Home",
      parentScreen: null, childComponents: [], accountGroup: "common", accountSubType: "common",
      screenType: "detail", hasTemplate: true, isProcessingEndpoint: false,
      category: "一般", permissions: ["admin"], designDocStatus: "着手済",
      existingTestCount: 3, sourceHash: "a1b2c3d4e5f6"
    }]
  }' > "$ext_manifest"

  local _gt_ext_run_out
  if _gt_ext_run_out="$(bash "$script_path" "$ext_manifest" "$ext_out" --unit-kind screen 2>&1)"; then
    extract_manifest_json() { sed -n '/<script type="application\/json" id="screen-manifest">/,/<\/script>/p' "$1" | sed '1d;$d'; }
    local embedded_keys expected_keys _gt_keys_diff
    extract_manifest_json "$ext_out" | jq -r '.screens[0] | keys | sort | join(",")' > "$tmp/embedded-screen-keys.txt" 2>/dev/null || echo "FAIL" > "$tmp/embedded-screen-keys.txt"
    jq -r '.screens[0] | keys | sort | join(",")' "$ext_manifest" > "$tmp/expected-screen-keys.txt"
    if ! _gt_keys_diff="$(diff -u "$tmp/expected-screen-keys.txt" "$tmp/embedded-screen-keys.txt" 2>&1)"; then
      roundtrip_ok=0
      echo "  [FAIL] 1-123: 拡張マニフェストの埋め込みキー集合が入力と不一致" >&2
      printf '%s\n' "$_gt_keys_diff" | sed 's/^/    /' >&2
    fi

    # 埋め込みJSONのsourceDirは1-102対応でbasename化されたサニタイズ済みの値のため、
    # --repo-rootで元のsourceDir($tmp/src。正規化前の実パス)を明示して復元する。
    # これによりsourceDirは実パスへ上書きされ、entryFile-実在の検証が正しく解決できる
    # (1-102随伴修正)。entryFile自体はsourceDirプレフィックス除去済みの相対パスのままなので、
    # 期待値側も同じ規則で正規化してから比較する。
    local _gt_restore_out
    if _gt_restore_out="$(bash "$script_dir/restore-screen-manifest.sh" "$ext_out" "$tmp/restored-ext.json" --repo-root "$tmp/src" 2>&1)"; then
      jq -S '
        def normPath($origSd):
          if (type == "string") and startswith("/") then
            if startswith($origSd) then
              (.[($origSd | length):] | ltrimstr("/"))
            else
              (split("/") | last)
            end
          else
            .
          end;
        (.sourceDir // "") as $origSd
        | .screens |= (map(
            if has("entryFile") then .entryFile |= normPath($origSd) else . end
          ))
      ' "$ext_manifest" > "$tmp/ext-sorted.json"
      jq -S . "$tmp/restored-ext.json" > "$tmp/restored-ext-sorted.json"
      local _gt_roundtrip_diff
      if ! _gt_roundtrip_diff="$(diff -u "$tmp/ext-sorted.json" "$tmp/restored-ext-sorted.json" 2>&1)"; then
        roundtrip_ok=0
        echo "  [FAIL] 1-123: 復元したマニフェストが拡張マニフェスト原本と不一致(往復非同一)" >&2
        printf '%s\n' "$_gt_roundtrip_diff" | sed 's/^/    /' >&2
      fi
    else
      roundtrip_ok=0
      echo "  [FAIL] 1-123: restore-screen-manifest.shが--repo-root指定でも拡張マニフェスト埋め込みHTMLからの復元に失敗した" >&2
      printf '%s\n' "$_gt_restore_out" | sed 's/^/    /' >&2
    fi
  else
    roundtrip_ok=0
    echo "  [FAIL] 1-123: 派生フィールド付き拡張マニフェストでの生成コマンド自体が失敗した" >&2
    printf '%s\n' "$_gt_ext_run_out" | sed 's/^/    /' >&2
  fi

  if [ "$roundtrip_ok" -eq 1 ]; then
    echo "  [PASS] 1-123: 派生フィールド付き拡張マニフェストでも埋め込みキー集合が入力と一致し、復元したマニフェストが原本と完全一致(往復同一性)"
  else
    rc=1
  fi

  # --- 1-102: sourceDirが絶対パスの場合、埋め込みJSON内でbasenameへ正規化されること ---
  local abs_manifest="$tmp/manifest-abs-sourcedir.json" abs_out="$tmp/manifest-abs-sourcedir.html"
  jq -n \
    --arg sourceFile "$tmp/src/routes/users.ts" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: "/tmp/fake-absolute-repo/src",
      unitKind: "api",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [
        {
          unitKey: "users-list",
          kind: "endpoint",
          identifier: "GET /api/users",
          unitNameGuess: "ユーザー一覧",
          sourceFile: $sourceFile,
          confidence: "high",
          fileCount: 1,
          detectionMethod: "manual"
        }
      ]
    }' > "$abs_manifest"

  if bash "$script_path" "$abs_manifest" "$abs_out" --unit-kind api >/dev/null 2>&1; then
    local embedded_source_dir embedded_source_file
    # extract_manifest_json は 1-123 検証で id="screen-manifest" 用に再定義されているため、
    # ここでは unit-manifest を明示的に抽出する
    embedded_source_dir="$(sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' "$abs_out" | sed '1d;$d' | jq -r '.sourceDir' 2>/dev/null || echo "FAIL")"
    embedded_source_file="$(sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' "$abs_out" | sed '1d;$d' | jq -r '.units[0].sourceFile' 2>/dev/null || echo "FAIL")"
    # sourceFileはsourceDir("/tmp/fake-absolute-repo/src")配下でない絶対パスのため、フォールバックのbasenameになる
    if [ "$embedded_source_dir" = "src" ] && [ "$embedded_source_file" = "users.ts" ]; then
      echo "  [PASS] 1-102: 絶対パスsourceDirがbasename(src)へ、sourceDir配下でない絶対パスsourceFileがbasename(users.ts)へ正規化される"
    else
      echo "  [FAIL] 1-102: 絶対パスの正規化に失敗(embedded sourceDir=${embedded_source_dir}, sourceFile=${embedded_source_file})" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 1-102: 絶対パスsourceDirを持つマニフェストの生成コマンド自体が失敗した" >&2
    rc=1
  fi

  # --- 1-102: sourceFileがsourceDir配下の絶対パスの場合、sourceDirプレフィックスを除いた
  # 相対パスへ正規化されること(basenameへの過剰な切り詰めをしない) ---
  local prefix_manifest="$tmp/manifest-abs-sourcefile-prefix.json" prefix_out="$tmp/manifest-abs-sourcefile-prefix.html"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg sourceFile "$tmp/src/routes/users.ts" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "api",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [
        {
          unitKey: "users-list",
          kind: "endpoint",
          identifier: "GET /api/users",
          unitNameGuess: "ユーザー一覧",
          sourceFile: $sourceFile,
          confidence: "high",
          fileCount: 1,
          detectionMethod: "manual"
        }
      ]
    }' > "$prefix_manifest"

  if bash "$script_path" "$prefix_manifest" "$prefix_out" --unit-kind api >/dev/null 2>&1; then
    local embedded_source_file_prefix
    embedded_source_file_prefix="$(sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' "$prefix_out" | sed '1d;$d' | jq -r '.units[0].sourceFile' 2>/dev/null || echo "FAIL")"
    if [ "$embedded_source_file_prefix" = "routes/users.ts" ]; then
      echo "  [PASS] 1-102: sourceDir配下の絶対パスsourceFileがsourceDirプレフィックス除去(routes/users.ts)へ正規化される"
    else
      echo "  [FAIL] 1-102: sourceDir配下の絶対パスsourceFileの正規化に失敗(sourceFile=${embedded_source_file_prefix})" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 1-102: sourceDir配下の絶対パスsourceFileを持つマニフェストの生成コマンド自体が失敗した" >&2
    rc=1
  fi

  # --- 1-170: batch一覧のvalueProvenance(measured/inferred/confirmed混在)バッジ描画確認 ---
  mkdir -p "$tmp/batch-src"
  cat > "$tmp/batch-src/daily_summary.py" <<'EOF'
def run(): pass
EOF
  local batch_manifest="$tmp/batch-manifest.json"
  jq -n --arg sourceDir "$tmp/batch-src" --arg sf "$tmp/batch-src/daily_summary.py" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "batch",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 3, unresolvedCount: 1},
    units: [
      {unitKey: "daily-summary", kind: "scheduled", identifier: "daily_summary", unitNameGuess: "日次集計",
       sourceFile: $sf, confidence: "high", nameConfidence: "confirmed",
       schedule: {cron: "0 3 * * *", readable: "毎日 3:00"}, valueProvenance: {schedule: "measured"}},
      {unitKey: "weekly-report", kind: "scheduled", identifier: "weekly_report", unitNameGuess: "推定週次処理",
       sourceFile: $sf, confidence: "medium", nameConfidence: "inferred",
       schedule: {cron: "0 4 * * 1", readable: "毎週1曜 4:00"},
       confirmedSchedule: {cron: "0 5 * * 1", readable: "毎週1曜 5:00"}, valueProvenance: {schedule: "measured"}},
      {unitKey: "monthly-close", kind: "unresolved", identifier: "monthly_close", unitNameGuess: "月次締め",
       sourceFile: $sf, confidence: "high"}
    ]
  }' > "$batch_manifest"
  local batch_out="$tmp/batch-list.html"
  local _gt_batch_out_run
  if _gt_batch_out_run="$(bash "$script_path" "$batch_manifest" "$batch_out" --unit-kind batch 2>&1)"; then
    if grep -Fq 'prov-badge prov-confirmed' "$batch_out" \
      && grep -Fq 'prov-badge prov-inferred' "$batch_out" \
      && grep -Fq 'prov-badge prov-measured' "$batch_out" \
      && grep -Fq 'u.confirmedSchedule' "$batch_out" \
      && grep -Fq "nameManifest.unitKind !== 'batch'" "$batch_out"; then
      echo "  [PASS] 1-170: batch一覧に確認済/推定名称バッジとconfirmedSchedule優先解決・実測バッジの描画ロジックが出力される"
    else
      echo "  [FAIL] 1-170: batch一覧のvalueProvenance/nameConfidence関連の描画ロジックが出力に含まれない" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 1-170: batch一覧生成コマンド自体が失敗した" >&2
    printf '%s\n' "$_gt_batch_out_run" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- 空状態-印付与: 0件マニフェストの空状態行にempty-rowクラスが付く ---
  local empty_manifest="$tmp/manifest-empty.json"
  jq -n --arg sourceDir "$tmp/src" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "api",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 0, unresolvedCount: 0},
    units: []
  }' > "$empty_manifest"
  local empty_out="$tmp/out-empty.html"
  if bash "$script_path" "$empty_manifest" "$empty_out" --unit-kind api >/dev/null 2>&1; then
    if grep -Fq '<tr class="empty-row"><td colspan=' "$empty_out"; then
      echo "  [PASS] 空状態-印付与: 0件マニフェストの空状態行にempty-rowクラスが付く"
    else
      echo "  [FAIL] 空状態-印付与: 0件マニフェストの空状態行にempty-rowクラスが付かない" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 空状態-印付与: 0件マニフェストの生成コマンド自体が失敗した" >&2
    rc=1
  fi

  # --- --repo-root: 指定した基準ディレクトリで相対sourceDirを解決できること ---
  # sourceDirはmock-repo-root配下からの相対値のまま保持し、manifest自身は${tmp直}下(mock-repo-rootの外)に置く。
  # .git祖先もgeneration-engine/DESIGN.mdもmock-repo-root配下には無いため、--repo-root省略時の
  # 既定解決(マニフェスト所在ディレクトリへのフォールバック)では実在確認が失敗するはずである。
  mkdir -p "$tmp/mock-repo-root/src/routes"
  cat > "$tmp/mock-repo-root/src/routes/orders.ts" <<'EOF'
export function ordersRoute() {}
EOF
  local repo_root_manifest="$tmp/manifest-repo-root.json"
  jq -n '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: "src/routes",
    unitKind: "api",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [
      {
        unitKey: "orders-list",
        kind: "endpoint",
        identifier: "GET /api/orders",
        unitNameGuess: "注文一覧",
        sourceFile: "orders.ts",
        confidence: "high",
        fileCount: 1,
        detectionMethod: "manual"
      }
    ]
  }' > "$repo_root_manifest"
  local repo_root_out="$tmp/out-repo-root.html" repo_root_default_out="$tmp/out-repo-root-default.html"
  local _rr_out_a
  if _rr_out_a="$(bash "$script_path" "$repo_root_manifest" "$repo_root_out" --unit-kind api --repo-root "$tmp/mock-repo-root" 2>&1)"; then
    local _rr_out_b
    if _rr_out_b="$(bash "$script_path" "$repo_root_manifest" "$repo_root_default_out" --unit-kind api 2>&1)"; then
      echo "  [FAIL] --repo-root指定: 省略時も成功してしまい、--repo-rootが解決基準を変えていることを確認できない" >&2
      printf '%s\n' "$_rr_out_b" | sed 's/^/    /' >&2
      rc=1
    else
      echo "  [PASS] --repo-root指定: 指定時は成功、省略時は既定の解決基準(マニフェスト所在ディレクトリ)で失敗する"
    fi
  else
    echo "  [FAIL] --repo-root指定: 指定した基準ディレクトリでの相対sourceDir解決に失敗した" >&2
    printf '%s\n' "$_rr_out_a" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- --source-file-root: sourceDirを結合せず対象プロジェクトルートのsourceFileを検査すること ---
  mkdir -p "$tmp/source-file-root/src/api"
  printf '%s\n' 'export function users() {}' > "$tmp/source-file-root/src/api/users.ts"
  local source_file_root_manifest="$tmp/manifest-source-file-root.json"
  jq '.sourceDir = "docs/design/apis" | .units[0].sourceFile = "src/api/users.ts"' "$repo_root_manifest" > "$source_file_root_manifest"
  local source_file_root_out="$tmp/out-source-file-root.html" _sfr_out
  if _sfr_out="$(bash "$script_path" "$source_file_root_manifest" "$source_file_root_out" --unit-kind api --source-file-root "$tmp/source-file-root" 2>&1)"; then
    echo "  [PASS] --source-file-root指定: 一覧生成時の再検証へ対象プロジェクトルートを透過"
  else
    echo "  [FAIL] --source-file-root指定: 一覧生成時の再検証へ対象プロジェクトルートを透過できない" >&2
    printf '%s\n' "$_sfr_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # featureは専用生成器へ委譲するため、その先まで--source-file-rootが届くことを回帰確認する。
  local feature_source_file_root_manifest="$tmp/manifest-feature-source-file-root.json"
  jq '.unitKind = "feature" | .units[0].kind = "feature" | .units[0].category = "注文管理" | .units[0].summary = "注文一覧を表示する" | .units[0].relatedScreens = [] | .units[0].relatedApis = [] | .units[0].relatedTables = []' "$source_file_root_manifest" > "$feature_source_file_root_manifest"
  local feature_source_file_root_out="$tmp/out-feature-source-file-root.html" _feature_sfr_out
  if _feature_sfr_out="$(bash "$script_path" "$feature_source_file_root_manifest" "$feature_source_file_root_out" --unit-kind feature --source-file-root "$tmp/source-file-root" 2>&1)"; then
    echo "  [PASS] --source-file-root feature委譲: build-feature-list.shの再検証まで対象プロジェクトルートを透過"
  else
    echo "  [FAIL] --source-file-root feature委譲: build-feature-list.shの再検証まで対象プロジェクトルートを透過できない" >&2
    printf '%s\n' "$_feature_sfr_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # screenも専用生成器へ委譲するため、対象rootだけにentryFileがある条件で透過を確認する。
  mkdir -p "$tmp/source-file-root/src/screens"
  printf '%s\n' 'export default function Top() { return null; }' > "$tmp/source-file-root/src/screens/Top.tsx"
  local screen_source_file_root_manifest="$tmp/manifest-screen-source-file-root.json"
  jq -n '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: "docs/design/screens",
    strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
    detectionSummary: {screenCount: 1, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
    screens: [{
      screenKey: "top", kind: "route", route: "/", screenNameGuess: "トップ",
      entryFile: "src/screens/Top.tsx", detectionMethod: "manual", confidence: "high",
      screenType: "top", accountGroup: "common", accountSubType: "common",
      hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false
    }]
  }' > "$screen_source_file_root_manifest"
  local screen_source_file_root_out="$tmp/out-screen-source-file-root.html" _screen_sfr_out
  if _screen_sfr_out="$(bash "$script_path" "$screen_source_file_root_manifest" "$screen_source_file_root_out" --unit-kind screen --source-file-root "$tmp/source-file-root" 2>&1)"; then
    echo "  [PASS] --source-file-root screen委譲: build-screen-list.shの再検証まで対象プロジェクトルートを透過"
  else
    echo "  [FAIL] --source-file-root screen委譲: build-screen-list.shの再検証まで対象プロジェクトルートを透過できない" >&2
    printf '%s\n' "$_screen_sfr_out" | sed 's/^/    /' >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

MANIFEST="${1:?Usage: build-unit-list.sh <manifest.json> <output-html-path> [--unit-kind <kind>] [--portal-dir <path>] [--project-name <name>] [--axes <file>] [--split-by <axisKey>] [--catalog <file>] [--sites <file>] [--site-key <key>] [--repo-root <パス>]}"
OUTPUT_HTML="${2:?Usage: build-unit-list.sh <manifest.json> <output-html-path> [--unit-kind <kind>] [--portal-dir <path>] [--project-name <name>] [--axes <file>] [--split-by <axisKey>] [--catalog <file>] [--sites <file>] [--site-key <key>] [--repo-root <パス>]}"
shift 2 || true

UNIT_KIND_ARG=""
PORTAL_DIR_ARG=""
PROJECT_NAME_ARG=""
AXES_FILE=""
SPLIT_BY=""
CATALOG_FILE=""
SITES_FILE=""
SITE_KEY=""
REPO_ROOT_ARG=""
SOURCE_FILE_ROOT_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --unit-kind)
      UNIT_KIND_ARG="${2:-}"
      shift 2
      ;;
    --portal-dir)
      PORTAL_DIR_ARG="${2:-}"
      shift 2
      ;;
    --project-name)
      PROJECT_NAME_ARG="${2:-}"
      shift 2
      ;;
    --catalog)
      # ポータルカタログの JSON。省略時はリポジトリ既定を使う
      CATALOG_FILE="${2:-}"
      shift 2
      ;;
    --axes)
      AXES_FILE="${2:-}"
      shift 2
      ;;
    --split-by)
      # 一覧を指定した軸の値ごとに分割する。none で分割を無効化する
      SPLIT_BY="${2:-}"
      shift 2
      ;;
    --sites)
      # サイト定義（sites.json）。指定するとサイドバーに切替が出る
      SITES_FILE="${2:-}"
      shift 2
      ;;
    --site-key)
      # このポータルが属するサイトのキー
      SITE_KEY="${2:-}"
      shift 2
      ;;
    --repo-root)
      # 元データの sourceDir を解決する基準にするディレクトリ。省略すると元データの所在から上へ辿って探す
      REPO_ROOT_ARG="${2:-}"
      shift 2
      ;;
    --source-file-root)
      # sourceDirを保持し、sourceFileの実在だけを対象プロジェクトルート基準で検査する
      SOURCE_FILE_ROOT_ARG="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 1
fi
if [ -n "$SITES_FILE" ] && [ ! -f "$SITES_FILE" ]; then
  echo "ERROR: --sites で指定されたファイルが存在しません: $SITES_FILE" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../unit-axes.sh"

if ! jq -e '(.generatedAt | type == "string") and (.generatedAt | length > 0)' "$MANIFEST" >/dev/null; then
  echo "ERROR: generatedAt must be a non-empty string" >&2
  exit 1
fi

manifest_unit_kind="$(jq -r 'if (.unitKind | type) == "string" and (.unitKind | length) > 0 then .unitKind else empty end' "$MANIFEST")"
if [ -n "$UNIT_KIND_ARG" ]; then
  if [ "$manifest_unit_kind" != "$UNIT_KIND_ARG" ] \
    && ! { [ "$UNIT_KIND_ARG" = "screen" ] && [ -z "$manifest_unit_kind" ]; }; then
    echo "ERROR: --unit-kind ($UNIT_KIND_ARG) must match manifest.unitKind ($manifest_unit_kind)" >&2
    exit 1
  fi
  UNIT_KIND="$UNIT_KIND_ARG"
else
  UNIT_KIND="${manifest_unit_kind:-screen}"
fi

# --- 分類軸・任意列の宣言を解決し、委譲先(build-screen-list.sh/build-feature-list.sh)・
# validate-manifest.sh の全呼び出しへ同一の解決結果を透過する。呼び出し元が --axes を
# 指定していない場合、自身が解決した結果を一時ファイルへ書き出し、そのパスを渡す。
# 付け忘れるとbuildとvalidateが別々の宣言を見て二重基準になるため。
AXES_TMP_FILE=""
EMBED_MANIFEST_TMP_FILE=""
cleanup_axes_tmp() {
  [ -n "$AXES_TMP_FILE" ] && rm -f "$AXES_TMP_FILE"
  [ -n "$EMBED_MANIFEST_TMP_FILE" ] && rm -f "$EMBED_MANIFEST_TMP_FILE"
  return 0
}
trap cleanup_axes_tmp EXIT

AXES_PASS_FILE="$AXES_FILE"
if [ -z "$AXES_PASS_FILE" ]; then
  axes_resolved_for_pass="$(resolve_unit_axes "$MANIFEST" "$AXES_FILE")" || exit 1
  if ! AXES_TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/build-unit-list-axes.XXXXXX" 2>/dev/null)" || [ -z "$AXES_TMP_FILE" ]; then
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  printf '%s' "$axes_resolved_for_pass" > "$AXES_TMP_FILE"
  AXES_PASS_FILE="$AXES_TMP_FILE"
fi

# --- unit_kind=screen: build-screen-list.sh に委譲(exit codeをそのまま返す) ---
if [ "$UNIT_KIND" = "screen" ]; then
  delegate_args=("$MANIFEST" "$OUTPUT_HTML")
  [ -n "$PORTAL_DIR_ARG" ] && delegate_args+=(--portal-dir "$PORTAL_DIR_ARG")
  [ -n "$PROJECT_NAME_ARG" ] && delegate_args+=(--project-name "$PROJECT_NAME_ARG")
  [ -n "$CATALOG_FILE" ] && delegate_args+=(--catalog "$CATALOG_FILE")
  [ -n "$SITES_FILE" ] && delegate_args+=(--sites "$SITES_FILE")
  [ -n "$SITE_KEY" ] && delegate_args+=(--site-key "$SITE_KEY")
  delegate_args+=(--axes "$AXES_PASS_FILE")
  [ -n "$SPLIT_BY" ] && delegate_args+=(--split-by "$SPLIT_BY")
  [ -n "$SOURCE_FILE_ROOT_ARG" ] && delegate_args+=(--source-file-root "$SOURCE_FILE_ROOT_ARG")
  "$SCRIPT_DIR/build-screen-list.sh" "${delegate_args[@]}"
  exit $?
fi

# --- unit_kind=feature: build-feature-list.sh に委譲(exit codeをそのまま返す) ---
if [ "$UNIT_KIND" = "feature" ]; then
  delegate_args=("$MANIFEST" "$OUTPUT_HTML")
  [ -n "$PORTAL_DIR_ARG" ] && delegate_args+=(--portal-dir "$PORTAL_DIR_ARG")
  [ -n "$PROJECT_NAME_ARG" ] && delegate_args+=(--project-name "$PROJECT_NAME_ARG")
  [ -n "$CATALOG_FILE" ] && delegate_args+=(--catalog "$CATALOG_FILE")
  delegate_args+=(--axes "$AXES_PASS_FILE")
  [ -n "$SOURCE_FILE_ROOT_ARG" ] && delegate_args+=(--source-file-root "$SOURCE_FILE_ROOT_ARG")
  "$SCRIPT_DIR/build-feature-list.sh" "${delegate_args[@]}"
  exit $?
fi

# --- unit_kind=screen 以外(汎用一覧を自前で生成する経路): --split-by は未対応 ---
if [ -n "$SPLIT_BY" ]; then
  echo "ERROR: --split-by は unit_kind=screen でのみ使用できます（指定された unit_kind: ${UNIT_KIND}）" >&2
  exit 1
fi

# --- unit_kind=screen 以外: 検証してから汎用テンプレートで生成 ---
# test_viewpoint/message/test_case はスキーマ契約が異なるため専用検証スクリプトへ委譲する。
case "$UNIT_KIND" in
  test_viewpoint)
    VALIDATE_CMD=("$SCRIPT_DIR/validate-test-viewpoint-manifest.sh" "$MANIFEST")
    ;;
  message)
    VALIDATE_CMD=("$SCRIPT_DIR/validate-message-manifest.sh" "$MANIFEST")
    ;;
  test_case)
    VALIDATE_CMD=("$SCRIPT_DIR/validate-test-case-manifest.sh" "$MANIFEST")
    ;;
  *)
    VALIDATE_CMD=("$SCRIPT_DIR/validate-manifest.sh" "$MANIFEST" --unit-kind "$UNIT_KIND" --axes "$AXES_PASS_FILE")
    if [ -n "$REPO_ROOT_ARG" ]; then
      VALIDATE_CMD+=(--repo-root "$REPO_ROOT_ARG")
    fi
    if [ -n "$SOURCE_FILE_ROOT_ARG" ]; then
      VALIDATE_CMD+=(--source-file-root "$SOURCE_FILE_ROOT_ARG")
    fi
    ;;
esac

if ! "${VALIDATE_CMD[@]}"; then
  echo "ERROR: manifestが検証に失敗しました。Phase 3の整合検証を先に完了してください" >&2
  exit 1
fi

case "$UNIT_KIND" in
  screen) LABEL="画面" ;;
  api) LABEL="API" ;;
  table) LABEL="テーブル" ;;
  batch) LABEL="バッチ" ;;
  report) LABEL="帳票" ;;
  external) LABEL="外部連携" ;;
  message) LABEL="メッセージ" ;;
  test_viewpoint) LABEL="テスト観点" ;;
  test_case) LABEL="テストケース" ;;
  *) echo "ERROR: unknown unit_kind: $UNIT_KIND" >&2; exit 1 ;;
esac

# --- 1-83: 資料リンクの「基本」「詳細」ラベルを design-unit-layout.json の
# phases.basic/detail から解決する。同JSONに宣言の無い種別(message/test_viewpoint/
# test_case等)は既定値(従来どおりの固定文字列)へフォールバックする。
DESIGN_UNIT_LAYOUT_FILE="$SCRIPT_DIR/../../../delivery-payload/references/design-unit-layout.json"
doc_label_for_phase() {
  local kind="$1" phase="$2" default_label="$3" filename=""
  if [ -f "$DESIGN_UNIT_LAYOUT_FILE" ]; then
    filename="$(jq -r --arg k "$kind" --arg p "$phase" '(.kinds[$k].phases[$p][0]) // empty' "$DESIGN_UNIT_LAYOUT_FILE" 2>/dev/null)"
  fi
  if [ -n "$filename" ]; then
    printf '%s' "${filename%.md}"
  else
    printf '%s' "$default_label"
  fi
}
doc_label_basic="$(doc_label_for_phase "$UNIT_KIND" basic "基本設計書")"
doc_label_detail="$(doc_label_for_phase "$UNIT_KIND" detail "詳細設計書")"

TEMPLATE="$SCRIPT_DIR/../../../delivery-payload/templates/unit-list/unit-list-template.html"
TOKENS_CSS_FILE="$SCRIPT_DIR/../../../delivery-payload/templates/tokens.css"
if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found: $TEMPLATE" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_HTML")"

# --- HTMLエスケープ(& < > " '。& を最初に処理する) ---
html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}

# --- 1-83: JS単一引用符文字列リテラルへの埋め込み用エスケープ(\ を最初に処理する)。
# DOC_LABEL_BASIC/DOC_LABEL_DETAIL は HTML属性値ではなく <script> 内のJS文字列リテラル
# として埋め込むため、html_escape ではなくこちらを使う(html_escapeを使うと '&#39;' が
# 文字列としてそのままJSソースへ混入し構文が壊れる)。
js_escape() {
  printf '%s' "$1" | sed -e "s/\\\\/\\\\\\\\/g" -e "s/'/\\\\'/g"
}

# detect-screens.sh と同じ末尾OKマーカー規約を、種別別一覧の可視HTMLにも適用する。
# 埋め込みマニフェストは正本としてそのまま保持し、表示値だけを防衛的に正規化する。
strip_ok_marker() {
  printf '%s' "$1" | sed -E '
    s/[[:space:]]*\(OK\)[[:space:]]+\([^()]+\)[[:space:]]*$//
    s/[[:space:]]*\(OK\)[[:space:]]+[[:alnum:]_.-]+[[:space:]]*$//
    s/(）)OK[[:space:]]*$/\1/
    s/[[:space:]]+OK[[:space:]]*$//
    s/[[:space:]]*\(OK\)[[:space:]]*$//
  ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# render_template — 共通関数を source（generation-engine/scripts/render-template.sh）
source "$(cd "$(dirname "$0")/.." && pwd)/render-template.sh"
if [ -f "$SCRIPT_DIR/../shell-injection.sh" ]; then
  . "$SCRIPT_DIR/../shell-injection.sh"
fi

label_esc="$(html_escape "$LABEL")"

# --- メタ情報・サマリ集計をマニフェストから抽出 ---
generated_at="$(jq -r '.generatedAt // ""' "$MANIFEST")"
source_dir="$(jq -r '.sourceDir // ""' "$MANIFEST")"
tile_unit_count="$(jq -r '.detectionSummary.unitCount // .summary.totalCount // 0' "$MANIFEST")"
tile_unresolved_count="$(jq -r '.detectionSummary.unresolvedCount // ([.units[]? | select(.kind == "unresolved")] | length)' "$MANIFEST")"

# --- 種別内訳タイル(test_caseのみ。0件も表示する) ---
extra_tiles=""
if [ "$UNIT_KIND" = "test_case" ]; then
  tile_unit_type_count="$(jq -r '.summary.byTestType.unit // 0' "$MANIFEST")"
  tile_integration_type_count="$(jq -r '.summary.byTestType.integration // 0' "$MANIFEST")"
  tile_scenario_type_count="$(jq -r '.summary.byTestType.scenario // 0' "$MANIFEST")"
  extra_tiles="$(cat <<EOF
<div class="tile"><strong>${tile_unit_type_count}</strong>単体件数</div>
<div class="tile"><strong>${tile_integration_type_count}</strong>結合件数</div>
<div class="tile"><strong>${tile_scenario_type_count}</strong>操作シナリオ件数</div>
EOF
)"
fi

# --- 推定名称比率(1-128・batchのみ)。検出できなかった事実として比率を集計しHTMLへ必ず表示する ---
extra_diagnostics_html=""
if [ "$UNIT_KIND" = "batch" ]; then
  inferred_diagnostics_json="$(jq -c '
    (.units // []) as $u
    | ($u | length) as $total
    | ($u | map(select(.nameConfidence == "inferred")) | length) as $count
    | {count: $count, total: $total,
       ratio: (if $total > 0 then ($count / $total) else 0 end),
       threshold: 0.5,
       warning: (if $total > 0 then (($count / $total) > 0.5) else false end)}
  ' "$MANIFEST")"
  tile_inferred_count="$(jq -r '.count' <<<"$inferred_diagnostics_json")"
  tile_inferred_ratio_pct="$(jq -r '(.ratio * 1000 | round) / 10' <<<"$inferred_diagnostics_json")"
  inferred_warning="$(jq -r '.warning' <<<"$inferred_diagnostics_json")"
  extra_tiles="${extra_tiles}<div class=\"tile\"><strong>${tile_inferred_count}</strong>推定名称件数</div>"
  inferred_message="推定名称 <strong>${tile_inferred_count}</strong> / ${tile_unit_count} 件（${tile_inferred_ratio_pct}%）が業務名を断定できていません。"
  if [ "$inferred_warning" = "true" ]; then
    extra_diagnostics_html="<div class=\"pt-callout pt-callout--warning\"><span class=\"material-symbols-outlined pt-callout__icon\" aria-hidden=\"true\">warning</span>${inferred_message}</div>"
  else
    extra_diagnostics_html="<p class=\"note\">${inferred_message}</p>"
  fi
fi

# --- 1ユニット分の <tr> を生成する ---
# 行データはjqの@tsv+bash readではなく、1行1JSONオブジェクト(jq -c)を個別に
# jq -r抽出する方式を採る。@tsv+IFS=タブのreadはタブがPOSIX上「IFS空白」に
# 分類されるため、unitId等の空フィールドが連続すると先頭の空フィールドが
# 消失し列がずれる(実測済みの既知不具合)。build-screen-list.shのrow_html()と
# 同じ「1行分のJSONを丸ごと受け取りjqで各フィールドを引く」方式に統一する。
row_html() {
  local row="$1"
  local unit_id unit_key kind unit_name identifier
  local kind_class kind_label

  unit_id="$(jq -r '.unitId // empty' <<<"$row")"
  unit_key="$(jq -r '.unitKey // ""' <<<"$row")"
  kind="$(jq -r '.kind // .messageType // .category // ""' <<<"$row")"
  unit_name="$(jq -r '.unitNameGuess // .messageText // .viewpoint // ""' <<<"$row")"
  unit_name="$(strip_ok_marker "$unit_name")"
  identifier="$(jq -r '.identifier // .screenKey // .unitKey // ""' <<<"$row")"

  case "$kind" in
    unresolved) kind_class="kind-unresolved"; kind_label="要確認" ;;
    *)
      kind_class="kind-generic"
      if [ "$UNIT_KIND" = "test_case" ]; then
        case "$kind" in
          unit)        kind_label="単体" ;;
          integration) kind_label="結合" ;;
          scenario)    kind_label="操作シナリオ" ;;
          *)           kind_label="$(html_escape "$kind")" ;;
        esac
      else
        kind_label="$(html_escape "$kind")"
      fi
      ;;
  esac

  # unitId/unitKey は表示列から外したが、展開行JSのユニット特定(findUnit等)のため
  # trの data-unit-id / data-unit-key 属性として保持する(3セルの制約には抵触しない)。
  printf '<tr data-unit-id="%s" data-unit-key="%s">\n' "$(html_escape "$unit_id")" "$(html_escape "$unit_key")"
  printf '<td>%s</td>\n' "$(html_escape "$unit_name")"
  printf '<td><code>%s</code></td>\n' "$(html_escape "$identifier")"
  if [ "$show_kind_column" -eq 1 ]; then
    printf '<td><span class="badge %s">%s</span></td>\n' "$kind_class" "$kind_label"
  fi
  printf '</tr>\n'
}

kind_value_count="$(jq -r '[.units[]? | select((.kind // "") != "unresolved") | (.kind // .messageType // .category // "")] | unique | length' "$MANIFEST")"
show_kind_column=0
if [ "$kind_value_count" -ge 2 ]; then
  show_kind_column=1
fi

unit_rows=""
unresolved_rows=""
while IFS= read -r row; do
  [ -z "$row" ] && continue
  row_kind="$(jq -r '.kind // ""' <<<"$row")"
  html="$(row_html "$row")"
  if [ "$row_kind" = "unresolved" ]; then
    unresolved_rows="${unresolved_rows}${html}"
  else
    unit_rows="${unit_rows}${html}"
  fi
done < <(jq -c '.units[]' "$MANIFEST")

# 基本列（区分は値が2種類以上あるときだけ静的theadと要手動確認テーブルへ追加する）
BASE_COLUMNS="unitNameGuess:${label_esc}名 identifier:識別子"
kind_column_header=""
if [ "$show_kind_column" -eq 1 ]; then
  BASE_COLUMNS="${BASE_COLUMNS} kind:区分"
  kind_column_header='<th data-key="kind">区分</th>'
fi
base_col_count="$(printf '%s\n' $BASE_COLUMNS | wc -l | tr -d ' ')"

if [ -z "$unit_rows" ]; then
  unit_rows="<tr class=\"empty-row\"><td colspan=\"${base_col_count}\">なし</td></tr>"
fi

if [ -z "$unresolved_rows" ]; then
  unresolved_section='<p class="note">なし</p>'
  unresolved_class="empty"
else
  unresolved_section="$(cat <<EOF
<table class="units" id="unresolved-table" data-unit-table>
<thead>
<tr>
<th data-key="unitNameGuess">${label_esc}名</th><th data-key="identifier">識別子</th>${kind_column_header}
</tr>
</thead>
<tbody>
${unresolved_rows}
</tbody>
</table>
EOF
)"
  unresolved_class="has-items pt-callout pt-callout--warning"
fi

# --- sourceDir/sourceFileの絶対パス正規化(1-102): 生成HTMLへ実行環境の絶対パスを焼き込まないため、
# 埋め込み直前にsourceDirが絶対パス(/始まり)ならbasenameへ正規化した一時コピーを作り、
# 以降の埋め込み処理はこちらを参照する。units[].sourceFile(string または string[])が
# sourceDir配下の絶対パスであれば、sourceDirプレフィックスを除いた相対パスへ正規化する
# (原本ファイルへの手がかりを保つため単純basenameにはしない)。sourceDir配下でない
# 想定外の絶対パスはbasenameへフォールバックする。相対パスの場合は無加工(既存の完全一致
# 自己テストへの影響なし)。既存フィクスチャは相対パス("$tmp/src"等)のため退行しない
EMBED_MANIFEST="$MANIFEST"
_manifest_source_dir="$(jq -r '.sourceDir // ""' "$MANIFEST")"
case "$_manifest_source_dir" in
  /*)
    _normalized_source_dir="$(basename "$_manifest_source_dir")"
    # mktempのテンプレートへ直接".json"を後置する形(XXXXXX.json)は乱数展開が
    # 効かない環境があり、コミット93eb2d6793dd30f0ae8320b372c823177c8f301c
    # 「一時ファイル名の乱数展開を効かせる」で拡張子なしのmktemp+mvの2段へ改めた。
    # 単純化して1回のmktempへ戻すな。
    _embed_manifest_base="$(mktemp "${TMPDIR:-/tmp}/$(basename "$0" .sh)-normalized.XXXXXX")"
    EMBED_MANIFEST="${_embed_manifest_base}.json"
    mv "$_embed_manifest_base" "$EMBED_MANIFEST"
    EMBED_MANIFEST_TMP_FILE="$EMBED_MANIFEST"
    jq --arg sd "$_normalized_source_dir" --arg origSd "$_manifest_source_dir" '
      def normPath:
        if (type == "string") and startswith("/") then
          if startswith($origSd) then
            (.[($origSd | length):] | ltrimstr("/"))
          else
            (split("/") | last)
          end
        else
          .
        end;
      .sourceDir = $sd
      | .units |= (map(
          if has("sourceFile") then
            .sourceFile |= (if type == "array" then map(normPath) else normPath end)
          else . end
        ))
    ' "$MANIFEST" > "$EMBED_MANIFEST"
    ;;
esac

# application/json のraw text要素では文字列中の </script> が要素を閉じるため、
# JSON値を変えずにHTML構文上の危険文字だけをJSONエスケープへ正規化する。
# <, >, & はJSON構文では文字列中にしか現れないため、この変換後も jq での比較は原本と同値になる。
unit_manifest_json="$(jq -c . "$EMBED_MANIFEST" | sed 's/</\\u003c/g; s/>/\\u003e/g; s/\&/\\u0026/g')"

# --- ポータルへの相対パス算出 ---
# 正本レイアウト（delivery-payload/references/output-layout.json）: ポータルは <output_dir>/index.html、
# 一覧HTMLは <output_dir>/<unitListHtml>（例: <output_dir>/project-portal/lists/<labelDir>/<種別>一覧.html）。
# この2階層は output_dir からの深さが異なるため、呼び出し元は必ず --portal-dir <output_dir> を渡すこと。
# --portal-dir 未指定時のフォールバックは旧2階層レイアウト（<output_dir>/一覧/<種別>一覧/）を前提とした
# 後方互換値であり、現行レイアウトでは誤ったリンクになる。
if [ -n "$PORTAL_DIR_ARG" ]; then
  portal_relative="$(python3 -c "import os; print(os.path.relpath('$PORTAL_DIR_ARG', '$(dirname "$OUTPUT_HTML")'))" 2>/dev/null || echo "..")/index.html"
else
  portal_relative="../../index.html"
fi

# --- 分類軸・任意列の宣言を解決して注入用 JSON を作る ---
axes_resolved="$(resolve_unit_axes "$MANIFEST" "$AXES_FILE")" || exit 1
column_spec_json="$(unit_axes_script_safe "$(unit_axes_for_kind "$axes_resolved" "$UNIT_KIND")")"

# --- テンプレートへの注入(単一パス方式。render_template()参照) ---
# マニフェストJSONのマーカーはテンプレート内で物理的に最後に出現するため、
# 単一パスのdocument-order走査により自動的に最後に処理される
# (JSON内容に他マーカー文字列が偶然含まれた場合の誤爆を避けるため)
render_args=(
  "{{PROJECT_NAME}}" "$(html_escape "$PROJECT_NAME_ARG")"
  "{{UNIT_KIND_LABEL}}" "$label_esc"
  "{{DOC_LABEL_BASIC}}" "$(js_escape "$doc_label_basic")"
  "{{DOC_LABEL_DETAIL}}" "$(js_escape "$doc_label_detail")"
  "{{GENERATED_AT}}" "$(html_escape "$generated_at")"
  "{{UNIT_COUNT}}" "$tile_unit_count"
  "{{UNRESOLVED_COUNT}}" "$tile_unresolved_count"
  "<!--EXTRA_TILES-->" "$extra_tiles"
  "<!--EXTRA_DIAGNOSTICS-->" "$extra_diagnostics_html"
  "<!--KIND_COLUMN_HEADER-->" "$kind_column_header"
  "<!--UNIT_TABLE_ROWS-->" "$unit_rows"
  "<!--UNRESOLVED_SECTION-->" "$unresolved_section"
  "{{UNRESOLVED_CLASS}}" "$unresolved_class"
  "{{UNRESOLVED_CLASS}}" "$unresolved_class"
  "{{PORTAL_RELATIVE}}" "$portal_relative"
  "{{MANIFEST_JSON}}" "$unit_manifest_json"
  "<!--COLUMN_SPEC_JSON-->" "$column_spec_json"
)
# トークンCSS注入（tokens.css が存在する場合のみ）
if [ -f "$TOKENS_CSS_FILE" ]; then
  render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
fi
# 共通シェル注入（partials が存在する場合のみ）
catalog_path="${CATALOG_FILE:-$SCRIPT_DIR/../../../delivery-payload/references/portal-catalog.json}"
if type shell_injection_args >/dev/null 2>&1; then
  shell_injection_args "$SCRIPT_DIR/../../../delivery-payload/templates" "$catalog_path" "$portal_relative" "$PROJECT_NAME_ARG" "$generated_at" "" "generation-engine/scripts/unit-list/build-unit-list.sh" "list" "${SITES_FILE:-}" "${SITE_KEY:-}" "$(dirname "$OUTPUT_HTML")"
  if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
    render_args+=("${SHELL_RENDER_ARGS[@]}")
  fi
fi
out="$(render_template "$(cat "$TEMPLATE")" "${render_args[@]}")"

# 宣言が非空なのに column-spec が出力に無ければ、テンプレートのマーカー欠落。fail-closed。
case "$out" in
  *'id="column-spec"'*) : ;;
  *)
    echo "ERROR: column-spec が出力に注入されていません（テンプレートの <!--COLUMN_SPEC_JSON--> マーカー欠落）" >&2
    exit 1 ;;
esac

# 1-83: 未置換のDOC_LABELマーカーがHTMLへ漏れていないか(render_templateは単一パスのため
# 未登録プレースホルダは置換されずそのまま残る)。fail-closed。
case "$out" in
  *'{{DOC_LABEL_'*)
    echo "ERROR: 資料ラベルのプレースホルダが未置換のまま残っています（{{DOC_LABEL_...}}）" >&2
    exit 1 ;;
esac

printf '%s\n' "$out" > "$OUTPUT_HTML"

echo "OK: wrote $OUTPUT_HTML" >&2
