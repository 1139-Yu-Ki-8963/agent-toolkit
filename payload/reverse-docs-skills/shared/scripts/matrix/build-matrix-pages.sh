#!/usr/bin/env bash
# マトリクス・対応表4ページ + AI設定資産ページの決定的ビルドスクリプト。
# page-type からテンプレートを解決し、data.json のメタ情報マーカー置換と
# manifest JSON の埋め込みのみを行う(描画はテンプレート内 JS が担うため、
# 本スクリプトは行 HTML の組み立てをしない)。
#
# Usage: build-matrix-pages.sh <page-type> <data.json> <output-html-path>
#        build-matrix-pages.sh --self-test
#
# page-type とテンプレート・埋め込みマーカー・必須トップレベルキーの対応:
#   permission-screen   shared/templates/matrix/permission-screen-matrix-template.html
#                       マーカー: MATRIX_JSON / 必須キー: roles, screens
#   permission-function shared/templates/matrix/permission-function-matrix-template.html
#                       マーカー: MATRIX_JSON / 必須キー: roles, functions
#   crud                shared/templates/matrix/crud-matrix-template.html
#                       マーカー: MATRIX_JSON / 必須キー: tables, features
#   traceability        shared/templates/matrix/traceability-template.html
#                       マーカー: MATRIX_JSON / 必須キー: screens, apis, tables
#   ai-assets           shared/templates/ai-assets/ai-assets-template.html
#                       マーカー: ASSETS_JSON / 必須キー: rules, skills, subagents, hooks
#
# 必須キーは各テンプレート内 JS が実際に参照するトップレベルキーと一致させている
# (テンプレートのヘッダコメント・JS 実装が契約の正本。二重管理・ドリフト禁止)。
#
# 共通マーカー(全テンプレート):
#   GENERATED_AT (波括弧記法) : data.json の generatedAt。無ければ実行時刻(UTC ISO8601)
#   DATA_SOURCE (波括弧記法)  : data.json の dataSource。無ければ空欄表示「—」
#
# 出力: <output-html-path> に単一ファイル自己完結の HTML を書き出す。
#   data.json の内容は <script type="application/json" id="matrix-manifest"> に
#   そのまま埋め込む(埋め込み JSON は原本と完全一致させる)。

## 設計判断
##
## **必要性**: マトリクス・対応表4ページ + AI設定資産ページの生成を、Claudeによる手作業の
## プレースホルダ置換ではなくスクリプト(build-matrix-pages.sh)による決定的生成に
## 固定する。テンプレートのヘッダコメントが手作業置換を明示的に禁止しており、
## page-type別のテンプレート解決・必須キー検証・単一パス置換(マーカー文字列衝突の
## 誤爆対策)という複数の分岐を伴う処理は、都度の手作業では再現性を保証できない。
## 5 page-type × 再生成のたびに繰り返し利用されるためスクリプト化が必要。
##
## **代替案を採用しなかった理由**:
## - Bash ツール直叩き(Claudeが都度プレースホルダ置換): テンプレート側が手作業置換を
##   禁止する契約。手作業組み立てによるデータ混入・エスケープ漏れを根絶する目的に反する
## - 既存 Makefile ターゲット拡張: 本リポジトリのスキル群はリポジトリ非依存で任意
##   プロジェクトを対象とするため、対象プロジェクトのMakefileに依存させられない
## - package.json scripts 追加: 同上。対象プロジェクトがNode.js製とは限らない
##
## **保守責任者**: 人手（ユーザー）。テンプレートのマーカー・manifest JSON構造の
## 変更時に本スクリプトの必須キー表・self-testフィクスチャを同時更新する
##
## **廃棄条件**: マトリクス・対応表・AI設定資産ページの生成が別基盤（テンプレートエンジン等）
## へ移行した時、または対応テンプレート群が廃止された時

set -euo pipefail

# --- --self-test モード ---
# 5 page-type それぞれの最小フィクスチャで生成を実行し、出力 HTML 内の埋め込み JSON が
# 原本フィクスチャと完全一致することを diff で検証する。build-unit-list.sh の self-test と
# 同じ誤爆対策観点として、マーカー文字列衝突・バックスラッシュを含む値もフィクスチャに含める。
# さらに build-matrix-data.sh の実出力を入力とする連結ケースで、独立フィクスチャでは
# 検出できない両スクリプト間のスキーマドリフトを検証する。
self_test() {
  local script_path="$0"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-matrix-pages-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  # 注: permission-function / ai-assets テンプレートはヘッダコメント内にも
  # script タグ文字列を含むため、行全体一致(^...$)でタグ行のみに絞る
  extract_manifest_json() {
    sed -n '/^<script type="application\/json" id="matrix-manifest">$/,/^<\/script>$/p' "$1" | sed '1d;$d'
  }

  # 1ケース分の生成+埋め込み一致検証
  run_case() {
    local label="$1" page_type="$2" fixture="$3"
    local out="$tmp/out-$page_type.html"
    local embedded="$tmp/embedded-$page_type.json"
    local expected="$tmp/expected-$page_type.json"
    if ! bash "$script_path" "$page_type" "$fixture" "$out" >/dev/null 2>&1; then
      echo "  [FAIL] $label: 生成コマンド自体が失敗した" >&2
      rc=1
      return
    fi
    extract_manifest_json "$out" | jq -c -S . > "$embedded" 2>/dev/null || true
    jq -c -S . "$fixture" > "$expected"
    if diff -q "$embedded" "$expected" >/dev/null 2>&1; then
      echo "  [PASS] $label: 埋め込みJSONが原本フィクスチャと完全一致"
    else
      echo "  [FAIL] $label: 埋め込みJSONが原本フィクスチャと不一致(誤爆の疑い)" >&2
      rc=1
    fi
  }

  # --- permission-screen: 権限×画面(permissions null = 権限未設定も含む) ---
  jq -n '{
    generatedAt: "2026-01-01T00:00:00Z",
    dataSource: "画面一覧マニフェスト + 権限定義",
    roles: ["管理者", "一般"],
    screens: [
      {screenId: "login", screenName: "ログイン", route: "/login",
       permissions: {"管理者": true, "一般": true}},
      {screenId: "audit-log", screenName: "監査ログ", route: "/admin/audit",
       permissions: null}
    ]
  }' > "$tmp/fixture-permission-screen.json"
  run_case "permission-screen" "permission-screen" "$tmp/fixture-permission-screen.json"

  # --- permission-function: マーカー文字列衝突をあえて含む(誤爆検証) ---
  jq -n \
    --arg functionName 'ユーザー編集{{GENERATED_AT}}<!--MATRIX_JSON--><!--ASSETS_JSON-->{{DATA_SOURCE}}' \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      dataSource: "機能一覧マニフェスト",
      roles: [{key: "admin", name: "管理者"}],
      functions: [
        {functionKey: "user-edit", functionName: $functionName,
         category: "ユーザー管理", permissions: {admin: "CRUD"}}
      ]
    }' > "$tmp/fixture-permission-function.json"
  run_case "permission-function(マーカー文字列衝突入り)" "permission-function" "$tmp/fixture-permission-function.json"

  # --- crud: 機能×テーブル ---
  jq -n '{
    generatedAt: "2026-01-01T00:00:00Z",
    dataSource: "機能一覧マニフェスト + テーブル一覧マニフェスト",
    tables: [{physicalName: "users", logicalName: "ユーザー"}],
    features: [{featureId: "user-manage", featureName: "ユーザー管理",
                cells: {users: "CRUD"}}]
  }' > "$tmp/fixture-crud.json"
  run_case "crud" "crud" "$tmp/fixture-crud.json"

  # --- traceability: 画面→API→テーブル連鎖 ---
  jq -n '{
    generatedAt: "2026-01-01T00:00:00Z",
    dataSource: "画面一覧・API一覧・テーブル一覧マニフェスト",
    screens: [{screenId: "login", screenName: "ログイン", route: "/login",
               apis: ["auth-login"]}],
    apis: [{apiId: "auth-login", apiName: "ログインAPI",
            endpoint: "POST /api/login", tables: ["users"]}],
    tables: [{tableId: "users", tableName: "users", logicalName: "ユーザー"}]
  }' > "$tmp/fixture-traceability.json"
  run_case "traceability" "traceability" "$tmp/fixture-traceability.json"

  # --- ai-assets: バックスラッシュ(正規表現風 \d+)を含む値で誤爆検証 ---
  jq -n \
    --arg summary 'APIパス GET /api/users/\d+ を検査する' \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      dataSource: ".claude/rules + .claude/settings.json + .claude/skills",
      rules: [{ruleName: "naming-guard", layer: "always", enforcement: "block",
               tags: ["[NAMING-BLOCK]"], summary: $summary}],
      skills: [{skillName: "sample-skill", category: "生成",
                trigger: "一覧生成時", summary: "一覧を生成する"}],
      subagents: [{name: "worker-sonnet", classification: "実行系",
                   verdict: "不可", mainTools: "Write/Edit"}],
      hooks: [{script: "check-naming.sh", timing: "PreToolUse", matcher: "Bash",
               tags: ["[NAMING-BLOCK]"], behavior: "block",
               summary: "英語typeコミットをblockする"}]
    }' > "$tmp/fixture-ai-assets.json"
  run_case "ai-assets(バックスラッシュ入り)" "ai-assets" "$tmp/fixture-ai-assets.json"

  # --- 連結ケース: build-matrix-data.sh の実出力を入力として 3 ページ生成 ---
  # 両スクリプトが独立フィクスチャで単体 PASS してもスキーマドリフトで連結が壊れる
  # 盲点を塞ぐ(2026-07 実測: crud / traceability が必須キー不一致で生成失敗)。
  # build-matrix-data.sh の通常モードはマニフェストの JSON 妥当性のみ検査するため、
  # ソースファイル実体なしの最小マニフェストで連結できる。
  local data_script chain_dir
  data_script="$(cd "$(dirname "$script_path")/../extract" 2>/dev/null && pwd)/build-matrix-data.sh"
  chain_dir="$tmp/chain"
  if [ ! -f "$data_script" ]; then
    echo "  [FAIL] 連結ケース: build-matrix-data.sh が見つからない: $data_script" >&2
    rc=1
  else
    mkdir -p "$chain_dir"
    jq -n '{
      generatedAt: "2026-01-01T00:00:00Z", sourceDir: "/nonexistent",
      strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
      detectionSummary: {screenCount: 2, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
      screens: [
        {screenKey: "user-admin", kind: "route", route: "/admin/users", entryFile: "a.tsx",
         confidence: "high", permissions: ["admin"], relatedApis: ["users-list"], sourceHash: "abcdef123456"},
        {screenKey: "home", kind: "route", route: "/", entryFile: "b.tsx", confidence: "high"}
      ]
    }' > "$chain_dir/screen-manifest.json"
    jq -n '{
      generatedAt: "2026-01-01T00:00:00Z", sourceDir: "/nonexistent", unitKind: "api",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [
        {unitKey: "users-list", kind: "endpoint", identifier: "GET /api/users", sourceFile: "api.py",
         confidence: "high", method: "GET", targetTables: ["users"]}
      ]
    }' > "$chain_dir/api-manifest.json"
    jq -n '{
      generatedAt: "2026-01-01T00:00:00Z", sourceDir: "/nonexistent", unitKind: "table",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 2, unresolvedCount: 0},
      units: [
        {unitKey: "users", kind: "table", identifier: "users", sourceFile: "001.sql", confidence: "high"},
        {unitKey: "audit-logs", kind: "table", identifier: "audit_logs", sourceFile: "002.sql", confidence: "high"}
      ]
    }' > "$chain_dir/table-manifest.json"
    jq -n '{
      generatedAt: "2026-01-01T00:00:00Z", sourceDir: "/nonexistent", unitKind: "feature",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [
        {unitKey: "user-management", kind: "feature", identifier: "user-management", sourceFile: "f.py",
         confidence: "high", relatedApis: ["users-list"]}
      ]
    }' > "$chain_dir/feature-manifest.json"
    if ! bash "$data_script" "$chain_dir/data" \
        --screen-manifest "$chain_dir/screen-manifest.json" \
        --api-manifest "$chain_dir/api-manifest.json" \
        --table-manifest "$chain_dir/table-manifest.json" \
        --feature-manifest "$chain_dir/feature-manifest.json" >/dev/null 2>&1; then
      echo "  [FAIL] 連結ケース: build-matrix-data.sh の実行自体が失敗した" >&2
      rc=1
    else
      run_case "連結(permission-screen): data実出力から生成" "permission-screen" "$chain_dir/data/permission-matrix.json"
      run_case "連結(crud): data実出力から生成" "crud" "$chain_dir/data/crud-matrix.json"
      run_case "連結(traceability): data実出力から生成" "traceability" "$chain_dir/data/traceability.json"
    fi
  fi

  # --- 検証の負ケース: 必須キー欠落は非0 exitすること ---
  jq -n '{generatedAt: "2026-01-01T00:00:00Z", dataSource: "x", tables: []}' \
    > "$tmp/fixture-crud-missing.json"
  if bash "$script_path" crud "$tmp/fixture-crud-missing.json" "$tmp/out-missing.html" >/dev/null 2>&1; then
    echo "  [FAIL] 負ケース: features欠落のcrudデータが検証を素通りした" >&2
    rc=1
  else
    echo "  [PASS] 負ケース: features欠落のcrudデータを非0 exitで拒否"
  fi

  # --- 検証の負ケース: 未知のpage-typeは非0 exitすること ---
  if bash "$script_path" unknown-type "$tmp/fixture-crud.json" "$tmp/out-unknown.html" >/dev/null 2>&1; then
    echo "  [FAIL] 負ケース: 未知のpage-typeが素通りした" >&2
    rc=1
  else
    echo "  [PASS] 負ケース: 未知のpage-typeを非0 exitで拒否"
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

USAGE="Usage: build-matrix-pages.sh <page-type> <data.json> <output-html-path>
  page-type: permission-screen | permission-function | crud | traceability | ai-assets"

PAGE_TYPE="${1:?$USAGE}"
DATA_JSON="${2:?$USAGE}"
OUTPUT_HTML="${3:?$USAGE}"

if [ $# -gt 3 ]; then
  echo "ERROR: unknown argument: $4" >&2
  echo "$USAGE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

if [ ! -f "$DATA_JSON" ]; then
  echo "ERROR: data.json not found: $DATA_JSON" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/../../templates"

# --- page-type からテンプレート・JSON埋め込みマーカー・必須トップレベルキーを解決 ---
case "$PAGE_TYPE" in
  permission-screen)
    TEMPLATE="$TEMPLATES_DIR/matrix/permission-screen-matrix-template.html"
    JSON_MARKER="<!--MATRIX_JSON-->"
    REQUIRED_KEYS="roles screens"
    ;;
  permission-function)
    TEMPLATE="$TEMPLATES_DIR/matrix/permission-function-matrix-template.html"
    JSON_MARKER="<!--MATRIX_JSON-->"
    REQUIRED_KEYS="roles functions"
    ;;
  crud)
    TEMPLATE="$TEMPLATES_DIR/matrix/crud-matrix-template.html"
    JSON_MARKER="<!--MATRIX_JSON-->"
    REQUIRED_KEYS="tables features"
    ;;
  traceability)
    TEMPLATE="$TEMPLATES_DIR/matrix/traceability-template.html"
    JSON_MARKER="<!--MATRIX_JSON-->"
    REQUIRED_KEYS="screens apis tables"
    ;;
  ai-assets)
    TEMPLATE="$TEMPLATES_DIR/ai-assets/ai-assets-template.html"
    JSON_MARKER="<!--ASSETS_JSON-->"
    REQUIRED_KEYS="rules skills subagents hooks"
    ;;
  *)
    echo "ERROR: unknown page-type: $PAGE_TYPE" >&2
    echo "$USAGE" >&2
    exit 1
    ;;
esac

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found: $TEMPLATE" >&2
  exit 1
fi

# --- data.json の最低限の検証(JSONオブジェクトであること + 必須トップレベルキー存在) ---
if ! jq -e 'type == "object"' "$DATA_JSON" >/dev/null 2>&1; then
  echo "ERROR: data.json がJSONオブジェクトとしてパースできません: $DATA_JSON" >&2
  exit 1
fi

for key in $REQUIRED_KEYS; do
  if ! jq -e --arg k "$key" 'has($k)' "$DATA_JSON" >/dev/null 2>&1; then
    echo "ERROR: data.json に必須トップレベルキー '$key' がありません(page-type: $PAGE_TYPE, 必須キー: $REQUIRED_KEYS): $DATA_JSON" >&2
    exit 1
  fi
done

# --- HTMLエスケープ(& < > のみ。& を最初に処理する) ---
html_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# render_template — 共通関数を source(shared/scripts/render-template.sh)
source "$(cd "$(dirname "$0")/.." && pwd)/render-template.sh"

# --- メタ情報を data.json から抽出 ---
generated_at="$(jq -r '.generatedAt // ""' "$DATA_JSON")"
if [ -z "$generated_at" ]; then
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi
data_source="$(jq -r '.dataSource // ""' "$DATA_JSON")"
[ -z "$data_source" ] && data_source="—"
project_name="$(jq -r '.projectName // ""' "$DATA_JSON")"

matrix_json="$(cat "$DATA_JSON")"

mkdir -p "$(dirname "$OUTPUT_HTML")"

# --- テンプレートへの注入(単一パス方式。render_template()参照) ---
# JSON埋め込みマーカーはテンプレート内で物理的に最後に出現するため、
# 単一パスのdocument-order走査により自動的に最後に処理される
# (JSON内容に他マーカー文字列が偶然含まれた場合の誤爆を避けるため)
out="$(render_template "$(cat "$TEMPLATE")" \
  "{{GENERATED_AT}}" "$(html_escape "$generated_at")" \
  "{{DATA_SOURCE}}" "$(html_escape "$data_source")" \
  "{{PROJECT_NAME}}" "$(html_escape "$project_name")" \
  "$JSON_MARKER" "$matrix_json")"

printf '%s\n' "$out" > "$OUTPUT_HTML"

echo "OK: wrote $OUTPUT_HTML" >&2
