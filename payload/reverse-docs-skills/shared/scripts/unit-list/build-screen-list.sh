#!/usr/bin/env bash
# generating-screen-list-for-reverse-docs: Phase 4 画面一覧.HTML 決定的生成
#
# Usage: build-screen-list.sh <manifest.json> <output-html-path>
#
# detect-screens.sh (および整合検証フェーズ) が出力するマニフェストJSONを
# 厳密な契約として扱い、shared/templates/unit-list/screen-list-template.html を土台に決定的にHTMLを
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
# 出力: <output-html-path> に単一ファイル自己完結のHTMLを書き出す。
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

# --- --self-test モード ---
# render_template()の単一パス置換が、埋め込み値中の他マーカー文字列衝突・
# バックスラッシュ・山括弧を含む自由記述フィールドでも誤爆しないことを検証する。
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
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
  if bash "$script_path" "$manifest_a" "$out_a" >/dev/null 2>&1; then
    local embedded_a="$tmp/embedded-a.json"
    local expected_a="$tmp/expected-a.json"
    extract_manifest_json "$out_a" | jq -c -S . > "$embedded_a" 2>/dev/null || true
    jq -c -S . "$manifest_a" > "$expected_a"
    if diff -q "$embedded_a" "$expected_a" >/dev/null 2>&1; then
      echo "  [PASS] ケースa: バックスラッシュ(\\d+)を含むdetectionMethodでも埋め込みJSONが原本と完全一致"
    else
      echo "  [FAIL] ケースa: バックスラッシュを含むdetectionMethodで埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースa: 生成コマンド自体が失敗した" >&2
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
    jq -c -S . "$manifest_b" > "$expected_b"
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
          testCasePath: "../../画面/screen-confirmed-home/テスト項目書/単体テスト仕様書.html"
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
    && grep -Fq "document.querySelectorAll('#screen-table tbody tr, #unresolved-table tbody tr')" "$out_findings" \
    && grep -Fq 'data-screen-key="unresolved-one"' "$out_findings" \
    && grep -Fq '"screenNameGuess":"要確認画面"' "$out_findings"; then
    echo "  [PASS] 1-41: 要手動確認テーブルも埋め込みマニフェストから画面名を再描画"
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
  if [ "$findings_ok" -eq 1 ] \
    && [ "$finding_row_count" = "2" ] \
    && grep -Fq '<strong>2</strong>検出画面数' "$out_findings" \
    && ! verify_rendered_screen_count 2 '<tr data-screen-id="one"></tr>' >/dev/null 2>&1; then
    echo "  [PASS] 1-43: 実出力表行を再計数し、欠落行を陰性fixtureで拒否"
  else
    echo "  [FAIL] 1-43: 実出力表行数ゲートが不足(rows=$finding_row_count)" >&2
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
  if bash "$script_path" "$manifest_bad_doc_url" "$out_bad_doc_url" >/dev/null 2>&1; then
    echo "  [FAIL] 設計書URL陰性: javascript: URLを生成入口で受け入れた" >&2
    rc=1
  elif ! grep -Fq 'if (isSafeRelativeUrl(href))' "$out_findings"; then
    echo "  [FAIL] 設計書URL陰性: 生成HTMLに描画時URLガードが無い" >&2
    rc=1
  else
    echo "  [PASS] 設計書URL陰性: 生成入口で拒否し描画側も安全な相対URLだけを有効化"
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

MANIFEST="${1:?Usage: build-screen-list.sh <manifest.json> <output-html-path> [--portal-dir <path>] [--project-name <name>]}"
OUTPUT_HTML="${2:?Usage: build-screen-list.sh <manifest.json> <output-html-path> [--portal-dir <path>] [--project-name <name>]}"
shift 2 || true

PORTAL_DIR_ARG=""
PROJECT_NAME_ARG=""
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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! "$SCRIPT_DIR/validate-manifest.sh" "$MANIFEST"; then
  echo "ERROR: manifestがvalidate-manifest.shの検証に失敗しました。Phase 3の整合検証を先に完了してください" >&2
  exit 1
fi

TEMPLATE="$SCRIPT_DIR/../../templates/unit-list/screen-list-template.html"
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

# 検出器と同じ4形式だけを表示境界で除去する最終防衛。マニフェストJSON自体は
# 改変せず、語中・語頭のOKを含む業務名は保持する。
strip_ok_marker() {
  printf '%s' "$1" | sed -E '
    s/[[:space:]]*\(OK\)[[:space:]]+[[:alnum:]_.-]+[[:space:]]*$//
    s/(）)OK[[:space:]]*$/\1/
    s/[[:space:]]+OK[[:space:]]*$//
    s/[[:space:]]*\(OK\)[[:space:]]*$//
  ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# render_template — 共通関数を source（shared/scripts/render-template.sh）
source "$(cd "$(dirname "$0")/.." && pwd)/render-template.sh"

# --- メタ情報・サマリ集計をマニフェストから抽出 ---
generated_at="$(jq -r '.generatedAt // ""' "$MANIFEST")"
source_dir="$(jq -r '.sourceDir // ""' "$MANIFEST")"
tile_screen_count="$(jq -r '.screens | length' "$MANIFEST")"
tile_cluster_count="$(jq -r '.detectionSummary.clusterCount // 0' "$MANIFEST")"
tile_shared_screen_count="$(jq -r '.detectionSummary.sharedScreenCount // 0' "$MANIFEST")"
tile_embedded_count="$(jq -r '.detectionSummary.embeddedCandidateCount // 0' "$MANIFEST")"
tile_unresolved_count="$(jq -r '.detectionSummary.unresolvedCount // 0' "$MANIFEST")"

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

screen_rows=""
unresolved_rows=""
while IFS= read -r row; do
  [ -z "$row" ] && continue
  row_kind="$(jq -r '.kind // ""' <<<"$row")"
  html="$(row_html "$row")"
  if [ "$row_kind" = "unresolved" ]; then
    unresolved_rows="${unresolved_rows}${html}"
  else
    screen_rows="${screen_rows}${html}"
  fi
done < <(jq -c '.screens[]' "$MANIFEST")

if [ -z "$screen_rows" ]; then
  screen_rows='<tr><td colspan="3">なし</td></tr>'
fi

if [ -z "$unresolved_rows" ]; then
  unresolved_section='<p class="note">なし</p>'
  unresolved_class="empty"
else
  unresolved_section="$(cat <<EOF
<table class="screens" id="unresolved-table">
<thead>
<tr>
<th>画面名</th><th>ルート</th><th>区分</th>
</tr>
</thead>
<tbody>
${unresolved_rows}
</tbody>
</table>
EOF
)"
  unresolved_class="has-items"
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

# application/json のraw text要素では文字列中の </script> が要素を閉じるため、
# JSON値を変えずにHTML構文上の危険文字だけをJSONエスケープへ正規化する。
screen_manifest_json="$(jq -c . "$MANIFEST" | sed 's/</\\u003c/g; s/>/\\u003e/g; s/\&/\\u0026/g')"

# --- ポータルへの相対パス算出(--portal-dir 未指定時は正本レイアウトの既定値) ---
# 正本レイアウト: <output_dir>/index.html と <output_dir>/一覧/<種別>一覧/<種別>一覧.html。
# 一覧HTMLから見たポータルは2階層上のため、未指定時は ../../index.html を既定とする。
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
  "{{TILE_CLUSTER_COUNT}}" "$tile_cluster_count"
  "{{TILE_SHARED_SCREEN_COUNT}}" "$tile_shared_screen_count"
  "{{TILE_EMBEDDED_COUNT}}" "$tile_embedded_count"
  "{{TILE_UNRESOLVED_COUNT}}" "$tile_unresolved_count"
  "<!--SCREEN_TABLE_ROWS-->" "$screen_rows"
  "<!--UNRESOLVED_SECTION-->" "$unresolved_section"
  "{{UNRESOLVED_CLASS}}" "$unresolved_class"
  "{{UNRESOLVED_CLASS}}" "$unresolved_class"
  "<!--DIAGNOSTICS-->" "$diagnostics_html"
  "{{PORTAL_RELATIVE}}" "$(html_escape "$portal_relative")"
  "{{PORTAL_RELATIVE}}" "$(html_escape "$portal_relative")"
  "<!--SCREEN_MANIFEST_JSON-->" "$screen_manifest_json"
)
# トークンCSS注入（tokens.css が存在する場合のみ）
if [ -f "$TOKENS_CSS_FILE" ]; then
  render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
fi
out="$(render_template "$(cat "$TEMPLATE")" "${render_args[@]}")"
verify_rendered_screen_count "$tile_screen_count" "$out"

printf '%s\n' "$out" > "$OUTPUT_HTML"

echo "OK: wrote $OUTPUT_HTML" >&2
