#!/usr/bin/env bash
# generating-screen-list-for-reverse-docs: Phase 4 画面一覧.HTML 決定的生成
#
# Usage: build-screen-list.sh <manifest.json> <output-html-path> [--split-by <axisKey>] [--repo-root <パス>]
#   --repo-root <パス>: 元データの sourceDir を解決する基準にするディレクトリ。省略すると元データの所在から上へ辿って探す
#
# --split-by <axisKey>: 一覧を指定した軸の値ごとに分割する。none で分割を無効化する。
#   未指定時は unit-axes.json で split.default=true な screen 軸(既定: accountGroup)が使われる。
#
# detect-screens.sh (および整合検証フェーズ) が出力するマニフェストJSONを
# 厳密な契約として扱い、delivery-payload/templates/unit-list/screen-list-template.html を土台に決定的にHTMLを
# 生成する。Claudeによる手作業のプレースホルダ置換は一切行わない(データ混入防止)。
#
# 入力JSONスキーマ(契約):
# {
#   "generatedAt": "...", "sourceDir": "...",
#   "strategy": {"screenIdRegex": "...またはnull", "viewSwitchPattern": "...またはnull"},
#   "detectionSummary": {
#     "method": "...", "screenCount": 0, "clusterCount": 0,
#     "sharedScreenCount": 0, "embeddedCandidateCount": 0, "unresolvedCount": 0
#   },
#   "screens": [{
#     "screenKey": "...", "screenId": null, "kind": "route|embedded-view|unresolved",
#     "screenNameGuess": "...", "route": "...", "detectionMethod": "...",
#     "confidence": "high|medium|low",
#     "entryFile": "...", "fileCount": 0, "files": [],
#     "sharedWith": [], "clusterId": null, "embeddedIn": null, "routeDupCount": 1,
#     "screenType": "list|detail|form|confirm|complete|error|top|processing_endpoint",
#     "accountGroup": "user|admin|editor|report|common",
#     "accountSubType": "common", "hasTemplate": true, "parentScreen": null,
#     "childComponents": [{"screenKey":"...","componentType":"modal|popup|iframe"}], "isProcessingEndpoint": false
#   }]
# }
#
# 出力: <output-html-path> に単一HTMLを書き出す。外部依存はMaterial Symbols OutlinedのGoogle Fonts CDNだけを許可する。
#   - kind=route / kind=embedded-view は通常テーブルへ
#   - kind=unresolved は「要手動確認」セクションの別テーブルへ(0件なら「なし」)
#   - screen-manifest.json の内容は <script type="application/json"> にそのまま埋め込む

## 設計判断
##
## **必要性**: 画面一覧.HTMLの生成をClaudeによる手作業のプレースホルダ置換から
## スクリプトによる決定的生成に置き換える。手作業組み立てはentryFile=None等の
## データ混入・列ズレ・JSONエスケープ漏れを起こしやすく、実際に発生した。
## jqによるJSONパース・11列テーブルのHTMLエスケープ・kind別振り分け・
## sharedWith集計・routeDupCount注記という複数の決定的処理をひとまとまりの
## スクリプトに固定することで、生成物を再現可能かつレビュー可能にする。
##
## **代替案を採用しなかった理由**:
## - Bash ツール直叩き(Claudeが都度プレースホルダ置換): 本タスクの発端そのもの。
##   手作業組み立てによるデータ混入(entryFile=None等)を根絶する目的で本スクリプトが必要
## - 既存 Makefile ターゲット拡張: 本スキルはリポジトリ非依存で任意プロジェクトの
##   ソースを探索するため、対象プロジェクトのMakefileに依存させられない
## - package.json scripts 追加: 同上。対象プロジェクトがNode.js製とは限らない
##
## **保守責任者**: 人手（ユーザー）。マニフェストJSONスキーマ変更時に同時更新する
##
## **廃棄条件**: generating-screen-list-for-reverse-docs スキルが廃止された時、
## またはHTML生成が別基盤（テンプレートエンジン等）へ移行した時

set -euo pipefail

count_rendered_screen_rows() {
  local rendered="$1"
  local count
  count="$(printf '%s' "$rendered" | grep -o '<tr data-screen-id=' | wc -l | tr -d ' ' || true)"
  printf '%s\n' "${count:-0}"
}

verify_rendered_screen_count() {
  local expected="$1"
  local rendered="$2"
  local actual
  actual="$(count_rendered_screen_rows "$rendered")"
  if [ "$actual" -ne "$expected" ]; then
    echo "ERROR: manifest登録件数($expected)と実出力表行数($actual)が一致しません" >&2
    return 1
  fi
}

# 検出器と同じ4形式だけを表示境界で除去する最終防衛。マニフェストJSON自体は
# 改変せず、語中・語頭のOKを含む業務名は保持する。
# count_rendered_screen_rows() と同様の理由(--self-test は self_test() 呼び出し後に
# 本スクリプトを exit するため、後方定義のままだと自己テスト内からの直接呼び出し時点で
# 未定義になる)で、定義をここ(self-test セクション直前)へ前倒しする。
strip_ok_marker() {
  printf '%s' "$1" | sed -E '
    s/[[:space:]]*\(OK\)[[:space:]]+\([^()]+\)[[:space:]]*$//
    s/[[:space:]]*\(OK\)[[:space:]]+[[:alnum:]_.-]+[[:space:]]*$//
    s/(）)OK[[:space:]]*$/\1/
    s/[[:space:]]+OK[[:space:]]*$//
    s/[[:space:]]*\(OK\)[[:space:]]*$//
  ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# --- --self-test モード ---
# render_template()の単一パス置換が、埋め込み値中の他マーカー文字列衝突・
# バックスラッシュ・山括弧を含む自由記述フィールドでも誤爆しないことを検証する。
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0

  # unit-axes.sh の source は trap ... RETURN 設定より前に済ませる。source(.)の
  # 完了自体がRETURNトラップの発火条件になるため、後段で source するとtrap設定後に
  # 即座に発火し$tmpが未使用のまま削除される(既知のbash挙動)。
  . "$script_dir/../unit-axes.sh"

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-screen-list-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/screens"
  cat > "$tmp/src/screens/Home.tsx" <<'EOF'
export function Home() { return null; }
EOF

  extract_manifest_json() {
    sed -n '/<script type="application\/json" id="screen-manifest">/,/<\/script>/p' "$1" | sed '1d;$d'
  }

  html_escape_for_test() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
  }

  # build-screen-list.sh は manifest を unit_axes_apply_detect(自動判定) 適用後の
  # 一時ファイルへ差し替えてから埋め込むため、埋め込みJSONの比較対象も
  # 「判定適用後のmanifest」に変える(判定の有無ではなく、JSONが壊れずに一致するかを検証する)。
  # sourceDir/entryFileが絶対パスの場合は1-102対応で正規化されるため、期待値にも同じ規則を適用する。
  expected_manifest_json() {
    local mpath="$1" ax
    ax="$(resolve_unit_axes "$mpath")" || return 1
    unit_axes_apply_detect "$ax" screen "$mpath" \
      | jq -c -S '
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
        | .screens |= (map(
            if has("entryFile") then .entryFile |= normPath($origSd) else . end
          ))
      '
  }

  # --- ケースa: バックスラッシュ(正規表現風 \d+)を含む detectionMethod ---
  local manifest_a="$tmp/manifest-a.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg entryFile "$tmp/src/screens/Home.tsx" \
    --arg detectionMethod 'route-regex:/home/\d+' \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
      detectionSummary: {screenCount: 1, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
      screens: [
        {
          screenKey: "home-screen",
          screenNameGuess: "トップ(OK) T-001",
          kind: "route",
          route: "/home",
          entryFile: $entryFile,
          detectionMethod: $detectionMethod,
          confidence: "high",
          screenType: "top",
          accountGroup: "common",
          accountSubType: "common",
          hasTemplate: true,
          parentScreen: null,
          childComponents: [],
          isProcessingEndpoint: false
        }
      ]
    }' > "$manifest_a"

  local out_a="$tmp/out-a.html"
  local _gt_out_a_run _gt_diff_out_a
  if _gt_out_a_run="$(bash "$script_path" "$manifest_a" "$out_a" 2>&1)"; then
    local embedded_a="$tmp/embedded-a.json"
    local expected_a="$tmp/expected-a.json"
    extract_manifest_json "$out_a" | jq -c -S . > "$embedded_a" 2>/dev/null || true
    expected_manifest_json "$manifest_a" > "$expected_a"
    if _gt_diff_out_a="$(diff -u "$expected_a" "$embedded_a" 2>&1)"; then
      echo "  [PASS] ケースa: バックスラッシュ(\\d+)を含むdetectionMethodでも埋め込みJSONが原本と完全一致"
    else
      echo "  [FAIL] ケースa: バックスラッシュを含むdetectionMethodで埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      printf '%s\n' "$_gt_diff_out_a" | sed 's/^/    /' >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースa: 生成コマンド自体が失敗した" >&2
    printf '%s\n' "$_gt_out_a_run" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- ケースb: 山括弧+実マーカー文字列そのものを含む diagnostics ---
  local manifest_b="$tmp/manifest-b.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg entryFile "$tmp/src/screens/Home.tsx" \
    --arg diag '</script><script>alert(1)</script><span>要確認</span>{{GENERATED_AT}}<!--SCREEN_MANIFEST_JSON-->' \
    --arg screenKey "'\" onmouseover=\"alert(1)'" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
      detectionSummary: {screenCount: 1, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
      screens: [
        {
          screenKey: $screenKey,
          kind: "route",
          route: "/home",
          entryFile: $entryFile,
          detectionMethod: "manual",
          confidence: "high",
          screenType: "top",
          accountGroup: "common",
          accountSubType: "common",
          hasTemplate: true,
          parentScreen: null,
          childComponents: [],
          isProcessingEndpoint: false
        }
      ],
      diagnostics: [$diag]
    }' > "$manifest_b"

  local out_b="$tmp/out-b.html"
  local build_b_error=""
  if build_b_error="$(bash "$script_path" "$manifest_b" "$out_b" 2>&1)"; then
    local embedded_b="$tmp/embedded-b.json"
    local expected_b="$tmp/expected-b.json"
    extract_manifest_json "$out_b" | jq -c -S . > "$embedded_b" 2>/dev/null || true
    expected_manifest_json "$manifest_b" > "$expected_b"
    if diff -q "$embedded_b" "$expected_b" >/dev/null 2>&1; then
      if grep -Fq '</script><script>alert(1)</script>' "$out_b" \
        || ! grep -Fq '\u003c/script\u003e\u003cscript\u003ealert(1)\u003c/script\u003e' "$out_b" \
        || ! grep -Fq 'data-screen-key="&#39;&quot; onmouseover=&quot;alert(1)&#39;"' "$out_b" \
        || grep -Fq 'onmouseover="alert(1)' "$out_b"; then
        echo "  [FAIL] ケースb: 危険文字を含むdiagnosticsのapplication/json埋め込みが安全化されていない" >&2
        rc=1
      else
        echo "  [PASS] ケースb: 危険文字+実マーカー文字列衝突を含むdiagnosticsでも埋め込みJSONが原本と完全一致"
      fi
    else
      echo "  [FAIL] ケースb: 山括弧+マーカー文字列衝突で埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースb: 生成コマンド自体が失敗した: $build_b_error" >&2
    rc=1
  fi

  # --- 回帰確認: 通常マニフェストの可視テーブル出力と machine gate(validate-manifest.sh)への影響なし ---
  local manifest_normal="$tmp/manifest-normal.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg entryFile "$tmp/src/screens/Home.tsx" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
      detectionSummary: {screenCount: 1, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
      screens: [
        {
          screenKey: "home-screen",
          screenNameGuess: "トップ(OK) T-001",
          kind: "route",
          route: "/home",
          entryFile: $entryFile,
          detectionMethod: "manual",
          confidence: "high",
          screenType: "top",
          accountGroup: "common",
          accountSubType: "common",
          hasTemplate: true,
          parentScreen: null,
          childComponents: [],
          isProcessingEndpoint: false
        }
      ]
    }' > "$manifest_normal"

  local out_normal="$tmp/out-normal.html"
  local regression_ok=1
  if ! bash "$script_path" "$manifest_normal" "$out_normal" >/dev/null 2>&1; then
    regression_ok=0
  elif ! grep -q '<code>/home</code>' "$out_normal"; then
    regression_ok=0
  elif ! grep -q '<td class="screen-name-cell"></td>' "$out_normal" \
    || ! grep -Fq 'item.confirmedScreenName || item.screenNameGuess' "$out_normal" \
    || grep -q '<td>トップ' "$out_normal"; then
    regression_ok=0
  elif ! bash "$script_dir/validate-manifest.sh" "$manifest_normal" >/dev/null 2>&1; then
    regression_ok=0
  fi

  # 4種類の末尾マーカーを除去し、語頭・語中のOKは保持する。
  local marker_manifest="$tmp/manifest-marker-forms.json" marker_out="$tmp/out-marker-forms.html"
  jq '
    .detectionSummary.screenCount = 6
    | .screens = [
        ["marker-space", "/marker-space", "末尾空白 OK"],
        ["marker-paren", "/marker-paren", "半角括弧(OK)"],
        ["marker-id", "/marker-id", "識別子付き(OK) SCR-001"],
        ["marker-wide", "/marker-wide", "全角括弧（補足）OK"],
        ["marker-leading", "/marker-leading", "OK処理"],
        ["marker-middle", "/marker-middle", "決済OK着地"]
      ]
      | .screens |= map({
          screenKey: .[0], screenNameGuess: .[2], kind: "route", route: .[1],
          entryFile: $entryFile, detectionMethod: "manual", confidence: "high",
          screenType: "top", accountGroup: "common", accountSubType: "common",
          hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false
        })
  ' --arg entryFile "$tmp/src/screens/Home.tsx" "$manifest_normal" > "$marker_manifest"
  if ! bash "$script_path" "$marker_manifest" "$marker_out" >/dev/null 2>&1 \
    || [ "$(grep -c '<td class=\"screen-name-cell\"></td>' "$marker_out" 2>/dev/null || true)" != "6" ] \
    || ! grep -Fq 'function normalizeScreenName(value)' "$marker_out" \
    || grep -q '<td>末尾空白' "$marker_out" \
    || grep -q '<td>半角括弧' "$marker_out" \
    || grep -q '<td>識別子付き' "$marker_out" \
    || grep -q '<td>全角括弧' "$marker_out" \
    || grep -q '<td>OK処理' "$marker_out" \
    || grep -q '<td>決済OK着地' "$marker_out"; then
    regression_ok=0
  fi

  if [ "$regression_ok" -eq 1 ]; then
    echo "  [PASS] 回帰確認: 末尾4形式を除去し語頭・語中OKを保持、validate-manifest.shも引き続きPASS"
  else
    echo "  [FAIL] 回帰確認: 可視テーブル内容またはvalidate-manifest.shのPASSに退行が発生した" >&2
    rc=1
  fi

  # --- 1-55: strip_ok_marker() 直接呼び出しで括弧付き識別子形式を検証 ---
  # 画面一覧の可視セル自体はテンプレート側JSが再描画するため(screen_nameは
  # 未使用の防衛的変数)、strip_ok_marker()の実挙動は関数を直接呼び出して検証する。
  local ok_t1 ok_t2 ok_t3 ok_t4 ok_t5 ok_t6 ok_t7
  ok_t1="$(strip_ok_marker "名称A(OK) (identA)")"
  if [ "$ok_t1" = "名称A" ]; then
    echo "  [PASS] 1-55-OKマーカー除去-括弧付き識別子二重括弧"
  else
    echo "  [FAIL] 1-55-OKマーカー除去-括弧付き識別子二重括弧: got='$ok_t1'" >&2
    rc=1
  fi

  ok_t2="$(strip_ok_marker "名称F(OK) identF")"
  if [ "$ok_t2" = "名称F" ]; then
    echo "  [PASS] 1-55-OKマーカー除去-括弧付き識別子非括弧"
  else
    echo "  [FAIL] 1-55-OKマーカー除去-括弧付き識別子非括弧: got='$ok_t2'" >&2
    rc=1
  fi

  ok_t3="$(strip_ok_marker "名称B(OK)")"
  if [ "$ok_t3" = "名称B" ]; then
    echo "  [PASS] 1-55-OKマーカー除去-括弧単体"
  else
    echo "  [FAIL] 1-55-OKマーカー除去-括弧単体: got='$ok_t3'" >&2
    rc=1
  fi

  ok_t4="$(strip_ok_marker "名称C（内訳） OK")"
  if [ "$ok_t4" = "名称C（内訳）" ]; then
    echo "  [PASS] 1-55-OKマーカー除去-全角括弧補足後スペースOK"
  else
    echo "  [FAIL] 1-55-OKマーカー除去-全角括弧補足後スペースOK: got='$ok_t4'" >&2
    rc=1
  fi

  ok_t5="$(strip_ok_marker "名称D OK")"
  if [ "$ok_t5" = "名称D" ]; then
    echo "  [PASS] 1-55-OKマーカー除去-末尾スペースOK"
  else
    echo "  [FAIL] 1-55-OKマーカー除去-末尾スペースOK: got='$ok_t5'" >&2
    rc=1
  fi

  ok_t6="$(strip_ok_marker "決済OK着地")"
  if [ "$ok_t6" = "決済OK着地" ]; then
    echo "  [PASS] 1-55-OKマーカー除去-業務用語維持-着地"
  else
    echo "  [FAIL] 1-55-OKマーカー除去-業務用語維持-着地: got='$ok_t6'" >&2
    rc=1
  fi

  ok_t7="$(strip_ok_marker "OK処理")"
  if [ "$ok_t7" = "OK処理" ]; then
    echo "  [PASS] 1-55-OKマーカー除去-業務用語維持-先頭"
  else
    echo "  [FAIL] 1-55-OKマーカー除去-業務用語維持-先頭: got='$ok_t7'" >&2
    rc=1
  fi

  # --- 写真指摘 1-40〜1-44: 一覧の表示・検索・件数・戻りリンク契約 ---
  local manifest_findings="$tmp/manifest-findings.json"
  local out_findings="$tmp/arbitrary/list-output/画面一覧.html"
  local portal_findings="$tmp/portal target's"
  mkdir -p "$(dirname "$out_findings")" "$portal_findings"
  : > "$portal_findings/index.html"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg entryFile "$tmp/src/screens/Home.tsx" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
      detectionSummary: {screenCount: 2, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 1},
      screens: [
        {
          screenId: "SCR-041",
          screenKey: "confirmed-home",
          screenNameGuess: "旧推定名",
          confirmedScreenName: "確定ホーム",
          kind: "route",
          route: "/home",
          entryFile: $entryFile,
          detectionMethod: "manual",
          confidence: "high",
          screenType: "top",
          accountGroup: "common",
          accountSubType: "common",
          hasTemplate: true,
          parentScreen: null,
          childComponents: [],
          isProcessingEndpoint: false,
          designDocStatus: "着手済",
          designDocPath: "../../画面/screen-confirmed-home/基本設計/画面基本設計書.html",
          detailDocPath: "../../画面/screen-confirmed-home/詳細設計/画面詳細設計書.html",
          sequencePath: "../../画面/screen-confirmed-home/シーケンス図.html",
          testCasePath: "../../画面/screen-confirmed-home/テスト項目書/単体テスト仕様書.html",
          unitTestViewpointPath: "../../画面/screen-confirmed-home/詳細設計/単体テスト観点表.html",
          integrationTestViewpointPath: "../../画面/screen-confirmed-home/詳細設計/結合テスト観点表.html",
          integrationTestCasePath: "../../画面/screen-confirmed-home/テスト項目書/結合テスト仕様書.html",
          scenarioPath: "../../画面/screen-confirmed-home/テスト項目書/操作シナリオ仕様書.html"
        },
        {
          screenKey: "unresolved-one",
          screenNameGuess: "要確認画面",
          kind: "unresolved",
          route: "",
          entryFile: "",
          detectionMethod: "manual",
          confidence: "low",
          screenType: "top",
          accountGroup: "common",
          accountSubType: "common",
          hasTemplate: false,
          parentScreen: null,
          childComponents: [],
          isProcessingEndpoint: false
        }
      ]
    }' > "$manifest_findings"

  local findings_ok=1
  if ! bash "$script_path" "$manifest_findings" "$out_findings" \
      --portal-dir "$portal_findings" >/dev/null 2>&1; then
    findings_ok=0
  fi

  if [ "$findings_ok" -eq 1 ] \
    && grep -Fq 'confirmedScreenName' "$out_findings" \
    && grep -Fq 'class="screen-name-cell"' "$out_findings" \
    && ! grep -Fq '<td>旧推定名</td>' "$out_findings" \
    && grep -Fq "item.confirmedScreenName || item.screenNameGuess" "$out_findings"; then
    echo "  [PASS] 1-41: 確定画面名は埋め込みマニフェストを単一表示源として再描画"
  else
    echo "  [FAIL] 1-41: 確定画面名の単一表示源化が未達" >&2
    rc=1
  fi

  if [ "$findings_ok" -eq 1 ] \
    && grep -Fq 'prov-badge prov-confirmed' "$out_findings" \
    && grep -Fq 'prov-badge prov-inferred' "$out_findings" \
    && grep -Fq "if (item.confirmedScreenName)" "$out_findings"; then
    echo "  [PASS] 1-170: confirmedScreenName有無から確認済/推定バッジの描画分岐を生成"
  else
    echo "  [FAIL] 1-170: 名称の出所バッジ描画分岐が出力に含まれない" >&2
    rc=1
  fi

  if [ "$findings_ok" -eq 1 ] \
    && grep -Fq "getElementById('unresolved-table')" "$out_findings" \
    && grep -Fq '.table-area table[data-unit-table]' "$out_findings" \
    && grep -Fq 'data-screen-key="unresolved-one"' "$out_findings" \
    && grep -Fq '"screenNameGuess":"要確認画面"' "$out_findings"; then
    echo "  [PASS] 1-41: 要手動確認テーブルも画面名再描画の対象に含む"
  else
    echo "  [FAIL] 1-41: 要手動確認テーブルが画面名再描画の対象外" >&2
    rc=1
  fi

  if [ "$findings_ok" -eq 1 ] \
    && grep -Fq 'data-search-text="SCR-041 confirmed-home '"$tmp"'/src/screens/Home.tsx"' "$out_findings" \
    && grep -Fq 'placeholder="画面名・画面キー・画面ID・入口ファイル・ルートで絞り込み"' "$out_findings"; then
    echo "  [PASS] 1-42: 画面キー・画面ID・entryFileを検索索引へ追加"
  else
    echo "  [FAIL] 1-42: 画面キー・画面ID・entryFileの検索索引が不足" >&2
    rc=1
  fi

  local finding_row_count
  finding_row_count="$(grep -c '<tr data-screen-' "$out_findings" 2>/dev/null || true)"
  if _gt_out4="$([ "$findings_ok" -eq 1 ] \
    && [ "$finding_row_count" = "2" ] \
    && grep -Fq '<strong>2</strong>検出画面数' "$out_findings" \
    && ! verify_rendered_screen_count 2 '<tr data-screen-id="one"></tr>' 2>&1)"; then
    echo "  [PASS] 1-43: 実出力表行を再計数し、欠落行を陰性fixtureで拒否"
  else
    echo "  [FAIL] 1-43: 実出力表行数ゲートが不足(rows=$finding_row_count)" >&2
    printf '%s\n' "$_gt_out4" | sed 's/^/    /' >&2
    rc=1
  fi

  local expected_portal_href_raw expected_portal_href expected_portal_target resolved_portal_target
  expected_portal_href_raw="$(python3 -c '
import os
import sys

relative = os.path.relpath(
    os.path.join(os.path.abspath(sys.argv[2]), "index.html"),
    os.path.abspath(sys.argv[1]),
)
sys.stdout.write(relative.replace(os.sep, "/"))
' "$(dirname "$out_findings")" "$portal_findings")"
  expected_portal_href="$(html_escape_for_test "$expected_portal_href_raw")"
  resolved_portal_target="$(python3 -c '
import os
import sys

print(os.path.abspath(os.path.join(sys.argv[1], sys.argv[2])))
' "$(dirname "$out_findings")" "$expected_portal_href_raw")"
  expected_portal_target="$(python3 -c '
import os
import sys

print(os.path.abspath(os.path.join(sys.argv[1], "index.html")))
' "$portal_findings")"
  local portal_link_count
  portal_link_count="$(grep -Fc "href=\"$expected_portal_href\"" "$out_findings" 2>/dev/null || true)"
  if [ "$findings_ok" -eq 1 ] \
    && [ "$portal_link_count" = "2" ] \
    && [ "$resolved_portal_target" = "$expected_portal_target" ] \
    && [ -f "$resolved_portal_target" ]; then
    echo "  [PASS] 1-44: 戻りリンクを任意portalの実在indexへ解決"
  else
    echo "  [FAIL] 1-44: 任意portal出力先への戻りリンクが実在indexへ到達不能(count=$portal_link_count)" >&2
    rc=1
  fi

  # 設計書リンクはvalidatorと描画側の二層で安全な相対URLだけを許可する。
  local manifest_bad_doc_url="$tmp/manifest-bad-doc-url.json"
  local out_bad_doc_url="$tmp/out-bad-doc-url.html"
  jq '.screens[0].designDocPath = "javascript:alert(1)"' \
    "$manifest_findings" > "$manifest_bad_doc_url"
  local _gt_bad_doc_url_out
  if _gt_bad_doc_url_out="$(bash "$script_path" "$manifest_bad_doc_url" "$out_bad_doc_url" 2>&1)"; then
    echo "  [FAIL] 設計書URL陰性: javascript: URLを生成入口で受け入れた" >&2
    printf '%s\n' "$_gt_bad_doc_url_out" | sed 's/^/    /' >&2
    rc=1
  elif ! grep -Fq 'if (isSafeRelativeUrl(href))' "$out_findings"; then
    echo "  [FAIL] 設計書URL陰性: 生成HTMLに描画時URLガードが無い" >&2
    rc=1
  else
    echo "  [PASS] 設計書URL陰性: 生成入口で拒否し描画側も安全な相対URLだけを有効化"
  fi

  # --- 1-94: 展開操作前の主テーブル行にリンク要素が存在することをDOM検査で確認する ---
  # 行クリック展開ハンドラのスクリプトは一切実行しない(=展開機構自体が存在しない状態で検査する)ため、
  # リンクが見つかれば構造的に「展開前」であることが保証される。
  local dom_check_log="$tmp/dom-check-1-94.log"
  if node -e '
    const fs = require("node:fs");
    const vm = require("node:vm");
    const file = process.argv[1];
    const source = fs.readFileSync(file, "utf8");

    function extractScript(marker) {
      const start = source.indexOf("// " + marker + "_START");
      const end = source.indexOf("// " + marker + "_END");
      if (start === -1 || end === -1) return null;
      return source.slice(start, end);
    }
    const libScript = extractScript("SCREEN_DOC_LINKS_LIB");
    const colScript = extractScript("SCREEN_DOC_LINKS_COLUMN");
    if (!libScript || !colScript) {
      console.error("スクリプト抽出失敗(マーカー欠落): lib=" + !!libScript + " col=" + !!colScript);
      process.exit(1);
    }

    const manifestMatch = source.match(/<script type="application\/json" id="screen-manifest">([\s\S]*?)<\/script>/);
    if (!manifestMatch) {
      console.error("埋め込みマニフェストJSON抽出失敗");
      process.exit(1);
    }

    function makeEl(tag) {
      return {
        tagName: String(tag).toUpperCase(),
        _attrs: {},
        style: {},
        className: "",
        textContent: "",
        children: [],
        appendChild(child) { this.children.push(child); return child; },
        setAttribute(k, v) { this._attrs[k] = String(v); },
        getAttribute(k) { return Object.prototype.hasOwnProperty.call(this._attrs, k) ? this._attrs[k] : null; },
        querySelector(sel) { return sel === "thead tr" ? (this._theadTr || null) : null; },
        querySelectorAll(sel) { return sel === "tbody tr" ? (this._tbodyTrs || []) : []; }
      };
    }

    const theadTr = makeEl("tr");
    const rowA = makeEl("tr");
    rowA.setAttribute("data-screen-id", "SCR-041");
    rowA.setAttribute("data-screen-key", "confirmed-home");
    const rowB = makeEl("tr");
    rowB.setAttribute("data-screen-key", "unresolved-one");

    const table = makeEl("table");
    table._theadTr = theadTr;
    table._tbodyTrs = [rowA, rowB];

    const manifestEl = { textContent: manifestMatch[1] };

    const document = {
      getElementById(id) { return id === "screen-manifest" ? manifestEl : null; },
      querySelectorAll(sel) { return sel === ".table-area table[data-unit-table]" ? [table] : []; },
      createElement(tag) { return makeEl(tag); }
    };

    const sandbox = { document, console };
    sandbox.window = sandbox;
    vm.createContext(sandbox);
    vm.runInContext(libScript, sandbox);
    vm.runInContext(colScript, sandbox);

    const td = rowA.children[rowA.children.length - 1];
    const anchors = td ? td.children.filter(function (c) { return c.tagName === "A"; }) : [];
    const realLinks = anchors.filter(function (a) {
      return a.className.indexOf("disabled") === -1 && typeof a.href === "string" && a.href.length > 0;
    });

    if (td && realLinks.length > 0) {
      console.log("展開前の主テーブル行に有効なリンク要素が" + realLinks.length + "件存在");
      process.exit(0);
    }
    console.error("展開前の主テーブル行に有効なリンク要素が存在しない(td-children=" + (td ? td.children.length : "no-td") + ")");
    process.exit(1);
  ' "$out_findings" > "$dom_check_log" 2>&1; then
    echo "  [PASS] 1-94: 展開操作前の主テーブル行にリンク要素が存在(DOM検査): $(cat "$dom_check_log")"
  else
    echo "  [FAIL] 1-94: 展開操作前の主テーブル行にリンク要素が存在しない(DOM検査)" >&2
    sed 's/^/    /' "$dom_check_log" >&2
    rc=1
  fi

  # --- 1-125: 低信頼度が過半数の合成マニフェストで警告コールアウトと分布が出力される ---
  local manifest_lowconf_majority="$tmp/manifest-lowconf-majority.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg entryFile "$tmp/src/screens/Home.tsx" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
      detectionSummary: {screenCount: 3, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
      screens: [
        {screenKey: "screen-alpha-lowconf", kind: "route", route: "/a", entryFile: $entryFile, detectionMethod: "manual", confidence: "low", screenType: "top", accountGroup: "common", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false},
        {screenKey: "screen-beta-lowconf", kind: "route", route: "/b", entryFile: $entryFile, detectionMethod: "manual", confidence: "low", screenType: "top", accountGroup: "common", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false},
        {screenKey: "screen-gamma-highconf", kind: "route", route: "/c", entryFile: $entryFile, detectionMethod: "manual", confidence: "high", screenType: "top", accountGroup: "common", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false}
      ]
    }' > "$manifest_lowconf_majority"

  local out_lowconf_majority="$tmp/out-lowconf-majority.html"
  local _gt_lowconf_majority_out
  if _gt_lowconf_majority_out="$(bash "$script_path" "$manifest_lowconf_majority" "$out_lowconf_majority" 2>&1)"; then
    if grep -Fq '画面種別分類がフォールバック値へ偏っている可能性があります' "$out_lowconf_majority" && grep -Fq '低信頼度画面 <strong>2</strong> / 3 件' "$out_lowconf_majority"; then
      echo "  [PASS] 1-125: 低信頼度が過半数(2/3)の合成マニフェストで警告コールアウトと分布(2/3件)が出力される"
    else
      echo "  [FAIL] 1-125: 低信頼度過半数で警告コールアウトまたは分布表示が出力されない" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 1-125: 低信頼度過半数マニフェストの生成コマンド自体が失敗した" >&2
    printf '%s\n' "$_gt_lowconf_majority_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- 1-125: 低信頼度0件では警告コールアウトを出さず、分布(0件)のみ表示される ---
  local manifest_lowconf_zero="$tmp/manifest-lowconf-zero.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg entryFile "$tmp/src/screens/Home.tsx" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
      detectionSummary: {screenCount: 2, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
      screens: [
        {screenKey: "screen-delta-highconf", kind: "route", route: "/a", entryFile: $entryFile, detectionMethod: "manual", confidence: "high", screenType: "top", accountGroup: "common", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false},
        {screenKey: "screen-epsilon-highconf", kind: "route", route: "/b", entryFile: $entryFile, detectionMethod: "manual", confidence: "high", screenType: "top", accountGroup: "common", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false}
      ]
    }' > "$manifest_lowconf_zero"

  local out_lowconf_zero="$tmp/out-lowconf-zero.html"
  local _gt_lowconf_zero_out
  if _gt_lowconf_zero_out="$(bash "$script_path" "$manifest_lowconf_zero" "$out_lowconf_zero" 2>&1)"; then
    if grep -Fq '画面種別分類がフォールバック値へ偏っている可能性があります' "$out_lowconf_zero"; then
      echo "  [FAIL] 1-125: 低信頼度0件なのに警告コールアウトが出力された" >&2
      rc=1
    elif grep -Fq '低信頼度画面 <strong>0</strong> / 2 件' "$out_lowconf_zero"; then
      echo "  [PASS] 1-125: 低信頼度0件では警告を出さずに分布(0/2件)のみ表示される"
    else
      echo "  [FAIL] 1-125: 低信頼度0件の分布表示(0/2件)が出力されない" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 1-125: 低信頼度0件マニフェストの生成コマンド自体が失敗した" >&2
    printf '%s\n' "$_gt_lowconf_zero_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- 1-102: sourceDirが絶対パスの場合、埋め込みJSON内でbasenameへ正規化されること ---
  local abs_manifest="$tmp/manifest-abs-sourcedir.json" abs_out="$tmp/manifest-abs-sourcedir.html"
  jq -n \
    --arg entryFile "$tmp/src/screens/Home.tsx" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: "/tmp/fake-absolute-repo/src",
      strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
      detectionSummary: {screenCount: 1, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
      screens: [
        {
          screenKey: "home-screen",
          screenNameGuess: "トップ",
          kind: "route",
          route: "/home",
          entryFile: $entryFile,
          detectionMethod: "manual",
          confidence: "high",
          screenType: "top",
          accountGroup: "common",
          accountSubType: "common",
          hasTemplate: true,
          parentScreen: null,
          childComponents: [],
          isProcessingEndpoint: false
        }
      ]
    }' > "$abs_manifest"

  local _gt_abs_out
  if _gt_abs_out="$(bash "$script_path" "$abs_manifest" "$abs_out" 2>&1)"; then
    local embedded_source_dir embedded_entry_file
    embedded_source_dir="$(sed -n '/<script type="application\/json" id="screen-manifest">/,/<\/script>/p' "$abs_out" | sed '1d;$d' | jq -r '.sourceDir' 2>/dev/null || echo "FAIL")"
    embedded_entry_file="$(sed -n '/<script type="application\/json" id="screen-manifest">/,/<\/script>/p' "$abs_out" | sed '1d;$d' | jq -r '.screens[0].entryFile' 2>/dev/null || echo "FAIL")"
    # entryFileはsourceDir("/tmp/fake-absolute-repo/src")配下でない絶対パスのため、フォールバックのbasenameになる
    if [ "$embedded_source_dir" = "src" ] && [ "$embedded_entry_file" = "Home.tsx" ]; then
      echo "  [PASS] 1-102: 絶対パスsourceDirがbasename(src)へ、sourceDir配下でない絶対パスentryFileがbasename(Home.tsx)へ正規化される"
    else
      echo "  [FAIL] 1-102: 絶対パスの正規化に失敗(embedded sourceDir=${embedded_source_dir}, entryFile=${embedded_entry_file})" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 1-102: 絶対パスsourceDirを持つマニフェストの生成コマンド自体が失敗した" >&2
    printf '%s\n' "$_gt_abs_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- 1-102: entryFileがsourceDir配下の絶対パスの場合、sourceDirプレフィックスを除いた
  # 相対パスへ正規化されること(basenameへの過剰な切り詰めをしない) ---
  local prefix_manifest="$tmp/manifest-abs-entryfile-prefix.json" prefix_out="$tmp/manifest-abs-entryfile-prefix.html"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg entryFile "$tmp/src/screens/Home.tsx" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
      detectionSummary: {screenCount: 1, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
      screens: [
        {
          screenKey: "home-screen",
          screenNameGuess: "トップ",
          kind: "route",
          route: "/home",
          entryFile: $entryFile,
          detectionMethod: "manual",
          confidence: "high",
          screenType: "top",
          accountGroup: "common",
          accountSubType: "common",
          hasTemplate: true,
          parentScreen: null,
          childComponents: [],
          isProcessingEndpoint: false
        }
      ]
    }' > "$prefix_manifest"

  local _gt_prefix_out
  if _gt_prefix_out="$(bash "$script_path" "$prefix_manifest" "$prefix_out" 2>&1)"; then
    local embedded_entry_file_prefix
    embedded_entry_file_prefix="$(sed -n '/<script type="application\/json" id="screen-manifest">/,/<\/script>/p' "$prefix_out" | sed '1d;$d' | jq -r '.screens[0].entryFile' 2>/dev/null || echo "FAIL")"
    if [ "$embedded_entry_file_prefix" = "screens/Home.tsx" ]; then
      echo "  [PASS] 1-102: sourceDir配下の絶対パスentryFileがsourceDirプレフィックス除去(screens/Home.tsx)へ正規化される"
    else
      echo "  [FAIL] 1-102: sourceDir配下の絶対パスentryFileの正規化に失敗(entryFile=${embedded_entry_file_prefix})" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 1-102: sourceDir配下の絶対パスentryFileを持つマニフェストの生成コマンド自体が失敗した" >&2
    printf '%s\n' "$_gt_prefix_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- 空状態-印付与: 0件マニフェストの空状態行にempty-rowクラスが付く ---
  local empty_manifest="$tmp/manifest-empty.json" empty_out="$tmp/manifest-empty.html"
  jq -n --arg sourceDir "$tmp/src" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
    detectionSummary: {screenCount: 0, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
    screens: []
  }' > "$empty_manifest"
  if bash "$script_path" "$empty_manifest" "$empty_out" >/dev/null 2>&1; then
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
  # sourceDirはmock-repo-root配下からの相対値のまま保持し、manifest自身は$tmp直下(mock-repo-rootの外)に置く。
  # .git祖先もgeneration-engine/DESIGN.mdもmock-repo-root配下には無いため、--repo-root省略時の
  # 既定解決(マニフェスト所在ディレクトリへのフォールバック)では実在確認が失敗するはずである。
  mkdir -p "$tmp/mock-repo-root/screens"
  cat > "$tmp/mock-repo-root/screens/Top.tsx" <<'EOF'
export default function Top() { return null; }
EOF
  local repo_root_manifest="$tmp/manifest-repo-root.json"
  jq -n '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: "screens",
    strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
    detectionSummary: {screenCount: 1, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
    screens: [
      {
        screenKey: "top",
        kind: "route",
        route: "/",
        screenNameGuess: "トップ",
        entryFile: "Top.tsx",
        detectionMethod: "manual",
        confidence: "high",
        screenType: "top",
        accountGroup: "common",
        accountSubType: "common",
        hasTemplate: true,
        parentScreen: null,
        childComponents: [],
        isProcessingEndpoint: false
      }
    ]
  }' > "$repo_root_manifest"
  local repo_root_out="$tmp/out-repo-root.html" repo_root_default_out="$tmp/out-repo-root-default.html"
  local _rr_out_a
  if _rr_out_a="$(bash "$script_path" "$repo_root_manifest" "$repo_root_out" --repo-root "$tmp/mock-repo-root" 2>&1)"; then
    local _rr_out_b
    if _rr_out_b="$(bash "$script_path" "$repo_root_manifest" "$repo_root_default_out" 2>&1)"; then
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

MANIFEST="${1:?Usage: build-screen-list.sh <manifest.json> <output-html-path> [--portal-dir <path>] [--project-name <name>] [--generated-at <iso8601>] [--axes <file>] [--split-by <axisKey>] [--catalog <file>] [--sites <file>] [--site-key <key>] [--repo-root <パス>]}"
OUTPUT_HTML="${2:?Usage: build-screen-list.sh <manifest.json> <output-html-path> [--portal-dir <path>] [--project-name <name>] [--generated-at <iso8601>] [--axes <file>] [--split-by <axisKey>] [--catalog <file>] [--sites <file>] [--site-key <key>] [--repo-root <パス>]}"
shift 2 || true

PORTAL_DIR_ARG=""
PROJECT_NAME_ARG=""
GENERATED_AT_ARG=""
AXES_FILE=""
SPLIT_BY=""
CATALOG_FILE=""
SITES_FILE=""
SITE_KEY=""
REPO_ROOT_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
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
    --generated-at)
      GENERATED_AT_ARG="${2:-}"
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
if [ -n "$GENERATED_AT_ARG" ] \
  && [ "$(jq -r '.generatedAt // ""' "$MANIFEST")" != "$GENERATED_AT_ARG" ]; then
  echo "ERROR: manifest generatedAt does not match --generated-at" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

. "$SCRIPT_DIR/../unit-axes.sh"

# --- 分類軸の宣言を解決し、detect（宣言済みの自動判定規則）で軸の値を埋める ---
# axes_resolved は元の $MANIFEST のディレクトリを起点に解決する(sibling の
# unit-axes.json 上書きを見つけるため)。判定適用後は $MANIFEST を一時ファイルへ
# 差し替え、以降の検証(validate-manifest.sh)・行生成・埋め込みJSONはすべて
# 判定適用後の内容を参照する。既に値があるフィールドは detect 側で上書きしない。
#
# validate-manifest.sh は自前でも軸宣言を解決するが、その解決起点は渡された
# manifest のディレクトリになる(unit-axes.shのコメント参照)。$MANIFEST を
# 一時ファイルへ差し替えた後にそのまま渡すと、validate側だけ一時ディレクトリを
# 起点に再解決してしまい、sibling の unit-axes.json 上書きを見失う二重基準が
# 生まれる。resolve_unit_axes は明示ファイル指定時に再マージしない(冪等)ため、
# ここで解決済みの axes_resolved を一時ファイルへ書き出し --axes で明示的に渡す。
axes_resolved="$(resolve_unit_axes "$MANIFEST" "$AXES_FILE")" || exit 1
DETECTED_MANIFEST="$(mktemp "${TMPDIR:-/tmp}/build-screen-list-detected.XXXXXX")"
AXES_RESOLVED_FILE="$(mktemp "${TMPDIR:-/tmp}/build-screen-list-axes-resolved.XXXXXX")"
EMBED_MANIFEST_TMP_FILE=""
trap 'rm -f "$DETECTED_MANIFEST" "$AXES_RESOLVED_FILE" "$EMBED_MANIFEST_TMP_FILE"' EXIT
printf '%s' "$axes_resolved" > "$AXES_RESOLVED_FILE"
unit_axes_apply_detect "$axes_resolved" "screen" "$MANIFEST" > "$DETECTED_MANIFEST"
MANIFEST="$DETECTED_MANIFEST"

VALIDATE_SCREEN_CMD=("$SCRIPT_DIR/validate-manifest.sh" "$MANIFEST" --axes "$AXES_RESOLVED_FILE")
if [ -n "$REPO_ROOT_ARG" ]; then
  VALIDATE_SCREEN_CMD+=(--repo-root "$REPO_ROOT_ARG")
fi
if ! "${VALIDATE_SCREEN_CMD[@]}"; then
  echo "ERROR: manifestがvalidate-manifest.shの検証に失敗しました。Phase 3の整合検証を先に完了してください" >&2
  exit 1
fi

TEMPLATE="$SCRIPT_DIR/../../../delivery-payload/templates/unit-list/screen-list-template.html"
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

# strip_ok_marker() の定義は、--self-test セクションから直接呼び出すため
# count_rendered_screen_rows() の直後(self-test セクション直前)へ移動済み。

# render_template — 共通関数を source（generation-engine/scripts/render-template.sh）
source "$(cd "$(dirname "$0")/.." && pwd)/render-template.sh"
if [ -f "$SCRIPT_DIR/../shell-injection.sh" ]; then
  . "$SCRIPT_DIR/../shell-injection.sh"
fi
# unit-axes.sh は validate-manifest.sh 呼び出し前(detect適用時)に source 済み。

# --- メタ情報・サマリ集計をマニフェストから抽出 ---
generated_at="$(jq -r '.generatedAt // ""' "$MANIFEST")"
source_dir="$(jq -r '.sourceDir // ""' "$MANIFEST")"
tile_screen_count="$(jq -r '.screens | length' "$MANIFEST")"
tile_cluster_count="$(jq -r '.detectionSummary.clusterCount // 0' "$MANIFEST")"
tile_shared_screen_count="$(jq -r '.detectionSummary.sharedScreenCount // 0' "$MANIFEST")"
# クラスタ数0なのに関与画面数が0でない状態は、manifestとして不正(validate-manifest.shが拒否済み)
# ではなく、clusterId未付与のままsharedWithだけ実データが入った、というより起こりうる
# 半端な検出結果を示す。表示上は注記を出さないことで矛盾表示を防ぐが、この状態自体は
# クラスタ判定ロジック側の潜在的な見落としの可能性があるため警告として残す。
if [ "$tile_cluster_count" = "0" ] && [ "$tile_shared_screen_count" != "0" ]; then
  echo "WARN: detectionSummary.clusterCount が 0 なのに sharedScreenCount が ${tile_shared_screen_count} です(clusterId未付与のままsharedWithが実データを持つ半端な検出結果の疑い)。関与画面数の注記は出力しません。" >&2
fi
if [ "$tile_cluster_count" = "0" ]; then
  tile_cluster_summary_html="<strong>${tile_cluster_count}</strong>共有クラスタ数"
else
  tile_cluster_summary_html="<strong>${tile_cluster_count}</strong>共有クラスタ数（${tile_shared_screen_count}画面が関与）"
fi
tile_embedded_count="$(jq -r '.detectionSummary.embeddedCandidateCount // 0' "$MANIFEST")"
tile_unresolved_count="$(jq -r '.detectionSummary.unresolvedCount // 0' "$MANIFEST")"

# --- 低信頼度分布(1-125): confidence=low の画面が過半数だと種別分類がフォールバック値へ
# 寄る実害があるため、検出できなかった事実として比率を集計しHTMLへ必ず表示する(0件でも表示)。
lowconf_diagnostics_json="$(jq -c '
  (.screens // []) as $s
  | ($s | length) as $total
  | ($s | map(select(.confidence == "low")) | length) as $count
  | {count: $count, total: $total,
     ratio: (if $total > 0 then ($count / $total) else 0 end),
     threshold: 0.5,
     warning: (if $total > 0 then (($count / $total) > 0.5) else false end)}
' "$MANIFEST")"
tile_lowconf_count="$(jq -r '.count' <<<"$lowconf_diagnostics_json")"
tile_lowconf_ratio_pct="$(jq -r '(.ratio * 1000 | round) / 10' <<<"$lowconf_diagnostics_json")"
lowconf_warning="$(jq -r '.warning' <<<"$lowconf_diagnostics_json")"
lowconf_message="低信頼度画面 <strong>${tile_lowconf_count}</strong> / ${tile_screen_count} 件（${tile_lowconf_ratio_pct}%）が検出信頼度 low です。"
if [ "$lowconf_warning" = "true" ]; then
  lowconf_callout_html="<div class=\"pt-callout pt-callout--warning\"><span class=\"material-symbols-outlined pt-callout__icon\" aria-hidden=\"true\">warning</span>${lowconf_message}画面種別分類がフォールバック値へ偏っている可能性があります。</div>"
else
  lowconf_callout_html="<p class=\"note\">${lowconf_message}</p>"
fi

# --- 分類軸・任意列の宣言(axes_resolvedはdetect適用時に解決済み)から注入用 JSON を作る ---
screen_axes_json="$(unit_axes_for_kind "$axes_resolved" "screen")"
column_spec_json="$(unit_axes_script_safe "$screen_axes_json")"

# --- 一覧の分割軸を決定する ---
# 優先順: 1) --split-by 明示指定(noneなら分割なし)  2) split.default=true な screen 軸  3) 分割なし
split_axis_key=""
if [ -n "$SPLIT_BY" ]; then
  if [ "$SPLIT_BY" != "none" ]; then
    split_axis_key="$(jq -r --arg k "$SPLIT_BY" '
      [.axes[] | select(.key == $k) | select((.split.eligible // false) == true)] | .[0].key // ""
    ' <<<"$screen_axes_json")"
    if [ -z "$split_axis_key" ]; then
      echo "ERROR: --split-by で指定された軸 '$SPLIT_BY' は screen 種別に適用可能な split.eligible=true の軸として見つかりません" >&2
      exit 1
    fi
  fi
else
  split_axis_key="$(jq -r '
    [.axes[] | select((.split.default // false) == true)] | .[0].key // ""
  ' <<<"$screen_axes_json")"
fi

# --- 1画面分の <tr> を生成する ---
row_html() {
  local row="$1"
  local screen_id screen_key kind screen_name route entry_file search_text
  local kind_class kind_label

  screen_id="$(jq -r '.screenId // empty' <<<"$row")"
  screen_key="$(jq -r '.screenKey // ""' <<<"$row")"
  kind="$(jq -r '.kind // ""' <<<"$row")"
  screen_name="$(jq -r '.screenNameGuess // ""' <<<"$row")"
  screen_name="$(strip_ok_marker "$screen_name")"
  route="$(jq -r '.route // ""' <<<"$row")"
  entry_file="$(jq -r '.entryFile // ""' <<<"$row")"
  search_text="${screen_id} ${screen_key} ${entry_file}"

  case "$kind" in
    route)          kind_class="kind-route";      kind_label="ルート" ;;
    embedded-view)   kind_class="kind-embedded";   kind_label="埋め込みビュー" ;;
    unresolved)      kind_class="kind-unresolved"; kind_label="要確認" ;;
    *)               kind_class="kind-unresolved"; kind_label="$(html_escape "$kind")" ;;
  esac

  # screenId/screenKey は表示列から外したが、展開行JSのユニット特定(findUnit等)のため
  # trの data-screen-id / data-screen-key 属性として保持する(3セルの制約には抵触しない)。
  printf '<tr data-screen-id="%s" data-screen-key="%s" data-search-text="%s">\n' \
    "$(html_escape "$screen_id")" "$(html_escape "$screen_key")" "$(html_escape "$search_text")"
  # 画面名は埋め込みマニフェストを唯一の表示源とし、テンプレート側で再描画する。
  # 静的セルに推定値を複製すると、埋め込みデータ更新後も旧名が残るため空セルにする。
  printf '<td class="screen-name-cell"></td>\n'
  if [ -n "$route" ]; then
    printf '<td><code>%s</code></td>\n' "$(html_escape "$route")"
  else
    printf '<td>—</td>\n'
  fi
  printf '<td><span class="badge %s">%s</span></td>\n' "$kind_class" "$kind_label"
  printf '</tr>\n'
}

# --- 要手動確認行(常に単一テーブル。分割の対象外) ---
unresolved_rows=""
while IFS= read -r row; do
  [ -z "$row" ] && continue
  unresolved_rows="${unresolved_rows}$(row_html "$row")"
done < <(jq -c '.screens[] | select(.kind == "unresolved")' "$MANIFEST")

# 基本列（静的theadと要手動確認テーブルで共有する3列）
BASE_COLUMNS="screenNameGuess:画面名 route:ルート kind:区分"
base_col_count="$(printf '%s\n' $BASE_COLUMNS | wc -l | tr -d ' ')"

if [ -z "$unresolved_rows" ]; then
  unresolved_section='<p class="note">なし</p>'
  unresolved_class="empty"
else
  unresolved_section="$(cat <<EOF
<table class="screens" id="unresolved-table" data-unit-table>
<thead>
<tr>
<th data-key="screenNameGuess">画面名</th><th data-key="route">ルート</th><th data-key="kind">区分</th>
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

# --- 通常テーブルのthead(単一テーブル・分割テーブル共通) ---
screen_thead_html='<thead>
<tr>
<th data-key="screenNameGuess">画面名</th><th data-key="route">ルート</th><th data-key="kind">区分</th>
</tr>
</thead>'

# 分割なし(単一テーブル)のセクションHTMLを組み立てる。<div class="table-area">の開始タグから
# module-groupセクションの閉じまでを丸ごと生成する(table-areaの閉じ</div>はテンプレート側に残る)。
render_single_table_section() {
  local rows="$1"
  if [ -z "$rows" ]; then
    rows="<tr class=\"empty-row\"><td colspan=\"${base_col_count}\">なし</td></tr>"
  fi
  cat <<EOF
<div class="table-area">
<section class="module-group">
<h2>画面一覧</h2>
<div class="table-wrap">
<table class="screens" id="screen-table" data-unit-table>
${screen_thead_html}
<tbody>
${rows}
</tbody>
</table>
</div>
</section>
EOF
}

if [ -z "$split_axis_key" ]; then
  screen_rows=""
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    screen_rows="${screen_rows}$(row_html "$row")"
  done < <(jq -c '.screens[] | select(.kind != "unresolved")' "$MANIFEST")
  screen_table_sections="$(render_single_table_section "$screen_rows")"
else
  split_axis_def="$(jq -c --arg k "$split_axis_key" '.axes[] | select(.key == $k)' <<<"$screen_axes_json")"
  split_count_unit="$(jq -r '.split.countUnit // "件"' <<<"$split_axis_def")"
  split_unknown_label="$(jq -r '.split.unknownLabel // "未分類"' <<<"$split_axis_def")"
  split_declared_keys_json="$(jq -c '[(.values // [])[].key]' <<<"$split_axis_def")"

  # グループ順序: 1) 宣言values[]の並び順(該当行がある値のみ) 2) 宣言に無い値は初出順 3) 空値は別枠(hasUnknown)
  split_groups_meta="$(jq -c --arg k "$split_axis_key" --argjson declared "$split_declared_keys_json" '
    def normv: (.[$k] // null) as $v | (if ($v == null or $v == "") then null else $v end);
    (.screens | map(select(.kind != "unresolved"))) as $rows
    | ($rows | map(normv)) as $vals
    | ($declared | map(select(. as $d | ($vals | index($d)) != null))) as $orderedDeclared
    | (reduce $rows[] as $r ([];
        ($r | normv) as $v
        | if $v == null then .
          elif ($orderedDeclared | index($v)) != null then .
          elif (index($v)) != null then .
          else . + [$v] end)) as $extraOrder
    | { known: ($orderedDeclared + $extraOrder), hasUnknown: (($vals | map(select(. == null)) | length) > 0) }
  ' "$MANIFEST")"

  split_known_count="$(jq -r '.known | length' <<<"$split_groups_meta")"
  split_has_unknown="$(jq -r '.hasUnknown' <<<"$split_groups_meta")"

  if [ "$split_known_count" -eq 0 ] && [ "$split_has_unknown" != "true" ]; then
    # 分割対象行が0件(要手動確認のみ等) → 現行どおり単一テーブル(空表示)
    screen_table_sections="$(render_single_table_section "")"
  elif [ "$split_known_count" -eq 0 ]; then
    # フォールバック: 全行で分割軸の値が空・未定義 → 分割せず単一テーブル
    screen_rows=""
    while IFS= read -r row; do
      [ -z "$row" ] && continue
      screen_rows="${screen_rows}$(row_html "$row")"
    done < <(jq -c '.screens[] | select(.kind != "unresolved")' "$MANIFEST")
    screen_table_sections="$(render_single_table_section "$screen_rows")"
  else
    screen_table_sections="<div class=\"table-area\" data-split-axis=\"$(html_escape "$split_axis_key")\">"
    split_first_table=1
    while IFS= read -r split_gk; do
      [ -z "$split_gk" ] && continue
      split_group_label="$(jq -r --arg gk "$split_gk" '(.values // [])[] | select(.key == $gk) | .label' <<<"$split_axis_def")"
      [ -z "$split_group_label" ] && split_group_label="$split_gk"
      split_group_rows=""
      split_group_count=0
      while IFS= read -r row; do
        [ -z "$row" ] && continue
        split_group_count=$((split_group_count + 1))
        split_group_rows="${split_group_rows}$(row_html "$row")"
      done < <(jq -c --arg k "$split_axis_key" --arg gk "$split_gk" '.screens[] | select(.kind != "unresolved") | select((.[$k] // "") == $gk)' "$MANIFEST")
      split_id_attr=""
      if [ "$split_first_table" -eq 1 ]; then
        split_id_attr=' id="screen-table"'
        split_first_table=0
      fi
      screen_table_sections="${screen_table_sections}$(cat <<EOF
<details class="module-group" open data-split-value="$(html_escape "$split_gk")">
<summary class="cat-header"><span class="cat-name">$(html_escape "$split_group_label")</span><span class="cat-count">${split_group_count} $(html_escape "$split_count_unit")</span></summary>
<div class="table-wrap">
<table class="screens"${split_id_attr} data-unit-table>
${screen_thead_html}
<tbody>
${split_group_rows}
</tbody>
</table>
</div>
</details>
EOF
)"
    done < <(jq -r '.known[]' <<<"$split_groups_meta")

    if [ "$split_has_unknown" = "true" ]; then
      split_group_rows=""
      split_group_count=0
      while IFS= read -r row; do
        [ -z "$row" ] && continue
        split_group_count=$((split_group_count + 1))
        split_group_rows="${split_group_rows}$(row_html "$row")"
      done < <(jq -c --arg k "$split_axis_key" '.screens[] | select(.kind != "unresolved") | select((.[$k] // "") == "")' "$MANIFEST")
      split_id_attr=""
      if [ "$split_first_table" -eq 1 ]; then
        split_id_attr=' id="screen-table"'
        split_first_table=0
      fi
      screen_table_sections="${screen_table_sections}$(cat <<EOF
<details class="module-group" open data-split-value="">
<summary class="cat-header"><span class="cat-name">$(html_escape "$split_unknown_label")</span><span class="cat-count">${split_group_count} $(html_escape "$split_count_unit")</span></summary>
<div class="table-wrap">
<table class="screens"${split_id_attr} data-unit-table>
${screen_thead_html}
<tbody>
${split_group_rows}
</tbody>
</table>
</div>
</details>
EOF
)"
    fi
  fi
fi

# --- diagnostics(警告)一覧をHTML断片へ整形。空なら何も出力しない ---
diag_items=""
while IFS= read -r diag; do
  [ -z "$diag" ] && continue
  diag_items="${diag_items}<li>$(html_escape "$diag")</li>"
done < <(jq -r '(.diagnostics // [])[]' "$MANIFEST")

if [ -z "$diag_items" ]; then
  diagnostics_html=""
else
  diagnostics_html="<div class=\"diag-warn\"><strong>診断・警告</strong><ul>${diag_items}</ul></div>"
fi

# --- sourceDir/entryFileの絶対パス正規化(1-102): 生成HTMLへ実行環境の絶対パスを焼き込まないため、
# 埋め込み直前にsourceDirが絶対パス(/始まり)ならbasenameへ正規化した一時コピーを作り、
# 以降の埋め込み処理はこちらを参照する。screens[].entryFileがsourceDir配下の絶対パスであれば、
# sourceDirプレフィックスを除いた相対パスへ正規化する(原本ファイルへの手がかりを保つため
# 単純basenameにはしない)。sourceDir配下でない想定外の絶対パスはbasenameへフォールバックする。
# 相対パスの場合は無加工(既存の完全一致自己テストへの影響なし)。既存フィクスチャは
# 相対パス("$tmp/src"等)のため退行しない
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
      | .screens |= (map(
          if has("entryFile") then .entryFile |= normPath else . end
        ))
    ' "$MANIFEST" > "$EMBED_MANIFEST"
    ;;
esac

# application/json のraw text要素では文字列中の </script> が要素を閉じるため、
# JSON値を変えずにHTML構文上の危険文字だけをJSONエスケープへ正規化する。
screen_manifest_json="$(jq -c . "$EMBED_MANIFEST" | sed 's/</\\u003c/g; s/>/\\u003e/g; s/\&/\\u0026/g')"

# --- ポータルへの相対パス算出 ---
# 正本レイアウト（delivery-payload/references/output-layout.json）: ポータルは <output_dir>/index.html、
# 画面一覧HTMLは <output_dir>/<screenListHtml>（既定 <output_dir>/project-portal/lists/screens/画面一覧.html）。
# この2階層は output_dir からの深さが異なるため、呼び出し元は必ず --portal-dir <output_dir> を渡すこと。
# --portal-dir 未指定時のフォールバックは旧2階層レイアウト（<output_dir>/一覧/画面一覧/）を前提とした
# 後方互換値であり、現行レイアウトでは誤ったリンクになる。
if [ -n "$PORTAL_DIR_ARG" ]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required when --portal-dir is specified" >&2
    exit 1
  fi
  portal_relative="$(python3 -c '
import os
import sys

relative = os.path.relpath(
    os.path.join(os.path.abspath(sys.argv[2]), "index.html"),
    os.path.abspath(sys.argv[1]),
)
sys.stdout.write(relative.replace(os.sep, "/"))
' "$(dirname "$OUTPUT_HTML")" "$PORTAL_DIR_ARG")"
else
  portal_relative="../../index.html"
fi

# --- テンプレートへの注入(単一パス方式。render_template()参照) ---
# マニフェストJSONのマーカーはテンプレート内で物理的に最後に出現するため、
# 単一パスのdocument-order走査により自動的に最後に処理される
# (JSON内容に他マーカー文字列が偶然含まれた場合の誤爆を避けるため)
render_args=(
  "{{PROJECT_NAME}}" "$(html_escape "$PROJECT_NAME_ARG")"
  "{{GENERATED_AT}}" "$(html_escape "$generated_at")"
  "{{TILE_SCREEN_COUNT}}" "$tile_screen_count"
  "{{TILE_CLUSTER_SUMMARY_HTML}}" "$tile_cluster_summary_html"
  "{{TILE_EMBEDDED_COUNT}}" "$tile_embedded_count"
  "{{TILE_UNRESOLVED_COUNT}}" "$tile_unresolved_count"
  "{{TILE_LOWCONF_COUNT}}" "$tile_lowconf_count"
  "<!--LOWCONF_CALLOUT-->" "$lowconf_callout_html"
  "<!--SCREEN_TABLE_SECTIONS-->" "$screen_table_sections"
  "<!--UNRESOLVED_SECTION-->" "$unresolved_section"
  "{{UNRESOLVED_CLASS}}" "$unresolved_class"
  "{{UNRESOLVED_CLASS}}" "$unresolved_class"
  "<!--DIAGNOSTICS-->" "$diagnostics_html"
  "{{PORTAL_RELATIVE}}" "$(html_escape "$portal_relative")"
  "{{PORTAL_RELATIVE}}" "$(html_escape "$portal_relative")"
  "<!--SCREEN_MANIFEST_JSON-->" "$screen_manifest_json"
  "<!--COLUMN_SPEC_JSON-->" "$column_spec_json"
)
# トークンCSS注入（tokens.css が存在する場合のみ）
if [ -f "$TOKENS_CSS_FILE" ]; then
  render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
fi
# 共通シェル注入（partials が存在する場合のみ）
catalog_path="${CATALOG_FILE:-$SCRIPT_DIR/../../../delivery-payload/references/portal-catalog.json}"
if type shell_injection_args >/dev/null 2>&1; then
  shell_injection_args "$SCRIPT_DIR/../../../delivery-payload/templates" "$catalog_path" "$portal_relative" "$PROJECT_NAME_ARG" "$generated_at" "" "generation-engine/scripts/unit-list/build-screen-list.sh" "list" "${SITES_FILE:-}" "${SITE_KEY:-}" "$(dirname "$OUTPUT_HTML")"
  if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
    render_args+=("${SHELL_RENDER_ARGS[@]}")
  fi
fi
out="$(render_template "$(cat "$TEMPLATE")" "${render_args[@]}")"
verify_rendered_screen_count "$tile_screen_count" "$out"

# 宣言が非空なのに column-spec が出力に無ければ、テンプレートのマーカー欠落。fail-closed。
case "$out" in
  *'id="column-spec"'*) : ;;
  *)
    echo "ERROR: column-spec が出力に注入されていません（テンプレートの <!--COLUMN_SPEC_JSON--> マーカー欠落）" >&2
    exit 1 ;;
esac

printf '%s\n' "$out" > "$OUTPUT_HTML"

echo "OK: wrote $OUTPUT_HTML" >&2
