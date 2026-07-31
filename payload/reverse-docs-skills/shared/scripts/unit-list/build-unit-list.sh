#!/usr/bin/env bash
# 種別別一覧スキル群(generating-<種別>-list-for-reverse-docs)共通エンジン: 種別対応HTML一覧生成ディスパッチャ。
# unit_kind=screen なら build-screen-list.sh、unit_kind=feature なら build-feature-list.sh に委譲、他種別は汎用テンプレートから生成する。
#
# Usage: build-unit-list.sh <manifest.json> <output-html-path> [--unit-kind <kind>]
#
# unit_kind=screen の場合:
#   同ディレクトリの build-screen-list.sh に <manifest.json> <output-html-path> をそのまま渡して
#   委譲する。従来の画面一覧.HTML生成と完全に同じ挙動になり、exit codeもそのまま返す。
#
# unit_kind=screen 以外の場合:
#   1. validate-manifest.sh <manifest.json> --unit-kind <kind> で検証(PASSしない限り生成しない)
#   2. shared/templates/unit-list/unit-list-template.html を土台に、jqでマニフェストJSONをパースして
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
#   ファイルを列挙する。message 専用の詳細契約は shared/references/manifest-schema-extensions.md に記載する。
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
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-unit-list-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/routes"
  cat > "$tmp/src/routes/users.ts" <<'EOF'
export function usersRoute() {}
EOF

  extract_manifest_json() {
    sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' "$1" | sed '1d;$d'
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
  if bash "$script_path" "$manifest_a" "$out_a" --unit-kind api >/dev/null 2>&1; then
    local embedded_a="$tmp/embedded-a.json"
    local expected_a="$tmp/expected-a.json"
    extract_manifest_json "$out_a" | jq -c -S . > "$embedded_a" 2>/dev/null || true
    jq -c -S . "$manifest_a" > "$expected_a"
    if diff -q "$embedded_a" "$expected_a" >/dev/null 2>&1; then
      echo "  [PASS] ケースa: バックスラッシュ(\\d+)を含むidentifierでも埋め込みJSONが原本と完全一致"
    else
      echo "  [FAIL] ケースa: バックスラッシュを含むidentifierで埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースa: 生成コマンド自体が失敗した" >&2
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
  if bash "$script_path" "$manifest_b" "$out_b" --unit-kind api >/dev/null 2>&1; then
    local embedded_b="$tmp/embedded-b.json"
    local expected_b="$tmp/expected-b.json"
    extract_manifest_json "$out_b" | jq -c -S . > "$embedded_b" 2>/dev/null || true
    jq -c -S . "$manifest_b" > "$expected_b"
    if diff -q "$embedded_b" "$expected_b" >/dev/null 2>&1; then
      if grep -Fq 'data-unit-key="&#39;&quot; onmouseover=&quot;alert(1)&#39;"' "$out_b" \
        && ! grep -Fq 'onmouseover="alert(1)' "$out_b"; then
        echo "  [PASS] ケースb: 引用符を含むunitKeyを属性値として安全にエスケープし、埋め込みJSONも原本と完全一致"
      else
        echo "  [FAIL] ケースb: 引用符を含むunitKeyで属性注入を防止できていない" >&2
        rc=1
      fi
    else
      echo "  [FAIL] ケースb: 山括弧+マーカー文字列衝突で埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースb: 生成コマンド自体が失敗した" >&2
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
  jq -cS . "$message_manifest" > "$tmp/message-original.json"
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
    units:[{unitKey:"screen-login-unit-1",screenKey:"screen-login",testType:"unit",category:"入力",viewpoint:"必須入力"}],
    summary:{totalCount:1,byTestType:{unit:1},byScreen:{"screen-login":1}}
  }' > "$viewpoint_manifest"
  if ! bash "$script_path" "$viewpoint_manifest" "$viewpoint_out" --unit-kind test_viewpoint >/dev/null 2>&1 \
    || ! grep -q '<code>screen-login</code>' "$viewpoint_out" \
    || ! grep -q 'href="../../index.html"' "$viewpoint_out"; then
    derived_ok=0
  fi
  extract_manifest_json "$viewpoint_out" | jq -cS . > "$tmp/viewpoint-embedded.json" 2>/dev/null || derived_ok=0
  jq -cS . "$viewpoint_manifest" > "$tmp/viewpoint-original.json"
  diff -q "$tmp/viewpoint-embedded.json" "$tmp/viewpoint-original.json" >/dev/null 2>&1 || derived_ok=0

  local test_case_manifest="$tmp/test-case.json" test_case_out="$tmp/test-case.html"
  jq -n '{
    unitKind:"test_case", generatedAt:"2026-01-01T00:00:00Z",
    units:[{unitKey:"screen-login-unit-1",screenKey:"screen-login",testType:"unit",unitNameGuess:"合計0円-登録不可",kind:"unit",caseKey:"合計0円-登録不可",viewpointKey:"金額-下限境界",input:"total: 0",steps:"",expected:"isRegisterableがfalseを返す"}],
    summary:{totalCount:1,byTestType:{unit:1},byScreen:{"screen-login":1}}
  }' > "$test_case_manifest"
  if ! bash "$script_path" "$test_case_manifest" "$test_case_out" --unit-kind test_case >/dev/null 2>&1 \
    || ! grep -q '<code>screen-login</code>' "$test_case_out" \
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
      {unitKey:"screen-login-unit-1",screenKey:"screen-login",testType:"unit",unitNameGuess:"合計0円-登録不可",kind:"unit",caseKey:"合計0円-登録不可",viewpointKey:"金額-下限境界",input:"total: 0",steps:"",expected:"isRegisterableがfalseを返す"},
      {unitKey:"screen-login-integration-1",screenKey:"screen-login",testType:"integration",unitNameGuess:"登録実行-一覧反映",kind:"integration",caseKey:"登録実行-一覧反映",viewpointKey:"登録-一覧反映",input:"必須項目入力済み",steps:"登録ボタンを押す",expected:"一覧に新規行が追加される"},
      {unitKey:"screen-login-scenario-1",screenKey:"screen-login",testType:"scenario",unitNameGuess:"検索条件の絞り込み",kind:"scenario",caseKey:"検索条件の絞り込み",viewpointKey:"操作後-画面反映",input:"一覧に複数件表示中",steps:"",expected:"検索実行後、一覧テーブルが即座に更新される。"}
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
      {unitKey:"screen-login-unit-1",screenKey:"screen-login",testType:"unit",unitNameGuess:"合計0円-登録不可",kind:"unit",caseKey:"合計0円-登録不可",viewpointKey:"金額-下限境界",input:"total: 0",steps:"",expected:"isRegisterableがfalseを返す"},
      {unitKey:"screen-login-integration-1",screenKey:"screen-login",testType:"integration",unitNameGuess:"登録実行-一覧反映",kind:"integration",caseKey:"登録実行-一覧反映",viewpointKey:"登録-一覧反映",input:"必須項目入力済み",steps:"登録ボタンを押す",expected:"一覧に新規行が追加される"}
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

  if bash "$script_path" "$ext_manifest" "$ext_out" --unit-kind screen >/dev/null 2>&1; then
    extract_manifest_json() { sed -n '/<script type="application\/json" id="screen-manifest">/,/<\/script>/p' "$1" | sed '1d;$d'; }
    local embedded_keys expected_keys
    extract_manifest_json "$ext_out" | jq -r '.screens[0] | keys | sort | join(",")' > "$tmp/embedded-screen-keys.txt" 2>/dev/null || echo "FAIL" > "$tmp/embedded-screen-keys.txt"
    jq -r '.screens[0] | keys | sort | join(",")' "$ext_manifest" > "$tmp/expected-screen-keys.txt"
    if ! diff -q "$tmp/embedded-screen-keys.txt" "$tmp/expected-screen-keys.txt" >/dev/null 2>&1; then
      roundtrip_ok=0
      echo "  [FAIL] 1-123: 拡張マニフェストの埋め込みキー集合が入力と不一致" >&2
    fi

    if bash "$script_dir/restore-screen-manifest.sh" "$ext_out" "$tmp/restored-ext.json" >/dev/null 2>&1; then
      jq -S . "$ext_manifest" > "$tmp/ext-sorted.json"
      jq -S . "$tmp/restored-ext.json" > "$tmp/restored-ext-sorted.json"
      if ! diff -q "$tmp/ext-sorted.json" "$tmp/restored-ext-sorted.json" >/dev/null 2>&1; then
        roundtrip_ok=0
        echo "  [FAIL] 1-123: 復元したマニフェストが拡張マニフェスト原本と不一致(往復非同一)" >&2
      fi
    else
      roundtrip_ok=0
      echo "  [FAIL] 1-123: restore-screen-manifest.shが拡張マニフェスト埋め込みHTMLからの復元に失敗した" >&2
    fi
  else
    roundtrip_ok=0
    echo "  [FAIL] 1-123: 派生フィールド付き拡張マニフェストでの生成コマンド自体が失敗した" >&2
  fi

  if [ "$roundtrip_ok" -eq 1 ]; then
    echo "  [PASS] 1-123: 派生フィールド付き拡張マニフェストでも埋め込みキー集合が入力と一致し、復元したマニフェストが原本と完全一致(往復同一性)"
  else
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

MANIFEST="${1:?Usage: build-unit-list.sh <manifest.json> <output-html-path> [--unit-kind <kind>] [--portal-dir <path>] [--project-name <name>] [--axes <file>] [--split-by <axisKey>] [--catalog <file>] [--sites <file>] [--site-key <key>]}"
OUTPUT_HTML="${2:?Usage: build-unit-list.sh <manifest.json> <output-html-path> [--unit-kind <kind>] [--portal-dir <path>] [--project-name <name>] [--axes <file>] [--split-by <axisKey>] [--catalog <file>] [--sites <file>] [--site-key <key>]}"
shift 2 || true

UNIT_KIND_ARG=""
PORTAL_DIR_ARG=""
PROJECT_NAME_ARG=""
AXES_FILE=""
SPLIT_BY=""
CATALOG_FILE=""
SITES_FILE=""
SITE_KEY=""
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
cleanup_axes_tmp() {
  [ -n "$AXES_TMP_FILE" ] && rm -f "$AXES_TMP_FILE"
}
trap cleanup_axes_tmp EXIT

AXES_PASS_FILE="$AXES_FILE"
if [ -z "$AXES_PASS_FILE" ]; then
  axes_resolved_for_pass="$(resolve_unit_axes "$MANIFEST" "$AXES_FILE")" || exit 1
  AXES_TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/build-unit-list-axes.XXXXXX")"
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

TEMPLATE="$SCRIPT_DIR/../../templates/unit-list/unit-list-template.html"
TOKENS_CSS_FILE="$SCRIPT_DIR/../../templates/tokens.css"
if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found: $TEMPLATE" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_HTML")"

# --- HTMLエスケープ(& < > " '。& を最初に処理する) ---
html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
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

# render_template — 共通関数を source（shared/scripts/render-template.sh）
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
  printf '<td><span class="badge %s">%s</span></td>\n' "$kind_class" "$kind_label"
  printf '</tr>\n'
}

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

# 基本列（静的theadと要手動確認テーブルで共有する3列）
BASE_COLUMNS="unitNameGuess:${label_esc}名 identifier:識別子 kind:区分"
base_col_count="$(printf '%s\n' $BASE_COLUMNS | wc -l | tr -d ' ')"

if [ -z "$unit_rows" ]; then
  unit_rows="<tr><td colspan=\"${base_col_count}\">なし</td></tr>"
fi

if [ -z "$unresolved_rows" ]; then
  unresolved_section='<p class="note">なし</p>'
  unresolved_class="empty"
else
  unresolved_section="$(cat <<EOF
<table class="units" id="unresolved-table" data-unit-table>
<thead>
<tr>
<th data-key="unitNameGuess">${label_esc}名</th><th data-key="identifier">識別子</th><th data-key="kind">区分</th>
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

# application/json のraw text要素では文字列中の </script> が要素を閉じるため、
# JSON値を変えずにHTML構文上の危険文字だけをJSONエスケープへ正規化する。
# <, >, & はJSON構文では文字列中にしか現れないため、この変換後も jq での比較は原本と同値になる。
unit_manifest_json="$(jq -c . "$MANIFEST" | sed 's/</\\u003c/g; s/>/\\u003e/g; s/\&/\\u0026/g')"

# --- ポータルへの相対パス算出(--portal-dir 未指定時は正本レイアウトの既定値) ---
# 正本レイアウト: <output_dir>/index.html と <output_dir>/一覧/<種別>一覧/<種別>一覧.html。
# 一覧HTMLから見たポータルは ../../index.html を既定とする。
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
  "{{GENERATED_AT}}" "$(html_escape "$generated_at")"
  "{{UNIT_COUNT}}" "$tile_unit_count"
  "{{UNRESOLVED_COUNT}}" "$tile_unresolved_count"
  "<!--EXTRA_TILES-->" "$extra_tiles"
  "<!--EXTRA_DIAGNOSTICS-->" "$extra_diagnostics_html"
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
catalog_path="${CATALOG_FILE:-$SCRIPT_DIR/../../templates/../references/portal-catalog.json}"
if type shell_injection_args >/dev/null 2>&1; then
  shell_injection_args "$SCRIPT_DIR/../../templates" "$catalog_path" "$portal_relative" "$PROJECT_NAME_ARG" "$generated_at" "" "shared/scripts/unit-list/build-unit-list.sh" "list" "${SITES_FILE:-}" "${SITE_KEY:-}" "$(dirname "$OUTPUT_HTML")"
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

printf '%s\n' "$out" > "$OUTPUT_HTML"

echo "OK: wrote $OUTPUT_HTML" >&2
