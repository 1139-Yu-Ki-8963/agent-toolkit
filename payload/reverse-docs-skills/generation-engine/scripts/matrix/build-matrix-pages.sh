#!/usr/bin/env bash
# マトリクス・対応表4ページ + AI設定資産ページの決定的ビルドスクリプト。
# page-type からテンプレートを解決し、data.json のメタ情報マーカー置換、
# matrix 4ページへのtokens.css正本全文注入、manifest JSON の埋め込みを行う
# (描画はテンプレート内 JS が担うため、
# 本スクリプトは行 HTML の組み立てをしない)。
#
# Usage: build-matrix-pages.sh <page-type> <data.json> <output-html-path> [--delete-on-empty]
#        build-matrix-pages.sh --self-test
#
# page-type とテンプレート・埋め込みマーカー・必須トップレベルキーの対応:
#   permission-screen   delivery-payload/templates/matrix/permission-screen-matrix-template.html
#                       マーカー: MATRIX_JSON / 必須キー: roles, screens
#   permission-function delivery-payload/templates/matrix/permission-function-matrix-template.html
#                       マーカー: MATRIX_JSON / 必須キー: roles, functions
#   crud                delivery-payload/templates/matrix/crud-matrix-template.html
#                       マーカー: MATRIX_JSON / 必須キー: tables, features
#   traceability        delivery-payload/templates/matrix/traceability-template.html
#                       マーカー: MATRIX_JSON / 必須キー: screens, apis, tables
#   confirmation-survey  delivery-payload/templates/matrix/confirmation-survey-template.html
#                       マーカー: MATRIX_JSON / 必須キー: questions
#                       (必須キーが0件でも空状態ページを生成する唯一の例外。
#                        改善課題1-169: 欠落0件は良い状態であり、その旨を示す
#                        ページ自体は常に公開する)
#   ai-assets           delivery-payload/templates/ai-assets/ai-assets-template.html
#                       マーカー: ASSETS_JSON / 必須キー: rules, skills, subagents, hooks
#
# 必須キーは各テンプレート内 JS が実際に参照するトップレベルキーと一致させている
# (テンプレートのヘッダコメント・JS 実装が契約の正本。二重管理・ドリフト禁止)。
#
# 共通マーカー(全テンプレート):
#   GENERATED_AT (波括弧記法) : data.json の generatedAt。無ければ実行時刻(UTC ISO8601)
#   DATA_SOURCE (波括弧記法)  : data.json の dataSource。無ければ空欄表示「—」
# matrix 4テンプレート共通:
#   TOKENS_CSS (CSSコメント記法): delivery-payload/templates/tokens.css の全文
#
# 出力: <output-html-path> に単一ファイル自己完結の HTML を書き出す。
#   data.json の内容は <script type="application/json" id="matrix-manifest"> に
#   そのまま埋め込む(埋め込み JSON は原本と完全一致させる)。
#
# 生成条件: 必須キーが揃っていても、その値(配列)がすべて0件なら空白の表だけの
#   ページを公開しないため生成をスキップする(exit 0・既存ページは保持)。
#   --delete-on-empty を明示した場合だけ既存ページを削除し(exit 2)、呼び出し側へ
#   破壊的な結果を伝える。
#   一部キーのみ0件の場合はページを生成し、テンプレート内JSが欠けた成分を示す
#   空状態コールアウトを表示する(写真指摘1-101)。
#   例外: confirmation-survey は必須キー(questions)が0件でも常にページを生成する
#   (改善課題1-169: 確認事項が0件という状態そのものが利用者に伝えるべき結果のため)。

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
    local label="$1" page_type="$2" fixture="$3" builder="${4:-$script_path}"
    local out="$tmp/out-$page_type.html"
    local embedded="$tmp/embedded-$page_type.json"
    local expected="$tmp/expected-$page_type.json"
    if ! _gt_out1="$(bash "$builder" "$page_type" "$fixture" "$out" 2>&1)"; then
      echo "  [FAIL] $label: 生成コマンド自体が失敗した" >&2
      printf '%s\n' "$_gt_out1" | sed 's/^/    /' >&2
      rc=1
      return
    fi
    extract_manifest_json "$out" | jq -c -S . > "$embedded" 2>/dev/null || true
    jq -c -S . "$fixture" > "$expected"
    if _gt_out2="$(diff -q "$embedded" "$expected" 2>&1)"; then
      echo "  [PASS] $label: 埋め込みJSONが原本フィクスチャと完全一致"
    else
      echo "  [FAIL] $label: 埋め込みJSONが原本フィクスチャと不一致(誤爆の疑い)" >&2
      printf '%s\n' "$_gt_out2" | sed 's/^/    /' >&2
      rc=1
    fi
    if [ "$page_type" != "ai-assets" ]; then
      local canonical_tokens
      canonical_tokens="$(cd "$(dirname "$builder")/../../../delivery-payload/templates" 2>/dev/null && pwd)/tokens.css"
      if [ -f "$canonical_tokens" ] \
        && python3 -c 'import pathlib,sys; h=pathlib.Path(sys.argv[1]).read_text(); t=pathlib.Path(sys.argv[2]).read_text(); raise SystemExit(0 if t in h else 1)' "$out" "$canonical_tokens" \
        && ! grep -q '/\* TOKENS_CSS \*/' "$out"; then
        echo "  [PASS] $label: tokens.css正本全文を注入"
      else
        echo "  [FAIL] $label: tokens.css注入が不完全" >&2
        rc=1
      fi
      if grep -q 'height: 100vh' "$out" \
        && grep -qE 'overflow:[[:space:]]*hidden' "$out" \
        && grep -qE 'overflow-y:[[:space:]]*auto' "$out" \
        && grep -q '<main class="pt-main is-fixed">' "$out"; then
        echo "  [PASS] $label: 固定viewportと独立縦スクロール領域(共通シェルpt-main)を生成"
      else
        echo "  [FAIL] $label: viewport/overflow/scroll layout契約が不完全" >&2
        rc=1
      fi
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

  # --- 1-170: permission-screen に3値(measured/inferred/confirmed)混在のvalueProvenanceを含めて
  #     出力HTMLへバッジCSSクラスが出現することを確認する ---
  jq -n '{
    generatedAt: "2026-01-01T00:00:00Z",
    dataSource: "画面一覧マニフェスト + 権限定義",
    roles: ["管理者", "一般"],
    screens: [
      {screenId: "login", screenName: "ログイン", route: "/login",
       permissions: {"管理者": true, "一般": true},
       valueProvenance: {permissions: "measured"}},
      {screenId: "user-admin", screenName: "ユーザー管理", route: "/admin/users",
       permissions: {"管理者": true, "一般": false},
       valueProvenance: {permissions: "inferred"}},
      {screenId: "reports", screenName: "レポート", route: "/reports",
       permissions: {"管理者": true, "一般": true},
       valueProvenance: {permissions: "confirmed"}}
    ]
  }' > "$tmp/fixture-permission-screen-provenance.json"
  local prov_out="$tmp/out-permission-screen-provenance.html"
  # 注: CSS内の.prov-measured等はデータに関わらず常に出現するため、それだけでは
  # 描画ロジックの存在を証明しない。JS側の実装固有の文字列(呼び出し・分岐条件・
  # クラス連結式)を grep することで、ロジックが削除されれば必ず FAIL するようにする。
  # 1-170再検証: 3値(measured/inferred/confirmed)すべてにバッジを描画する仕様に変更した。
  # inferred限定の条件分岐(if (provenance === 'inferred'))が復活していないことを確認しつつ、
  # 推定値だけを視覚的に目立たせる設計意図(背景塗り+太字のprov-inferred CSS)が
  # 維持されていることも合わせて確認する。
  if bash "$script_path" permission-screen "$tmp/fixture-permission-screen-provenance.json" "$prov_out" >/dev/null 2>&1 \
    && grep -Fq 'permissionsProvenance(s)' "$prov_out" \
    && grep -Fq "'prov-badge prov-' + provenance" "$prov_out" \
    && grep -Fq 'var provBadge = buildProvBadge(provenance);' "$prov_out" \
    && grep -Fq 'if (provBadge) tdScreen.appendChild(provBadge);' "$prov_out" \
    && ! grep -Fq "if (provenance === 'inferred')" "$prov_out" \
    && grep -Fq '.prov-badge.prov-inferred { color: var(--stamp); border-color: var(--stamp); background: var(--stamp-soft); font-weight: 700; }' "$prov_out" \
    && grep -Fq '.prov-badge.prov-measured { color: var(--accent); border-color: var(--accent); }' "$prov_out" \
    && grep -Fq '.prov-badge.prov-confirmed { color: var(--green); border-color: var(--green); }' "$prov_out"; then
    echo "  [PASS] 1-170: permission-screen出力でmeasured/inferred/confirmedの3値すべてにバッジ描画ロジックが無条件で適用され(inferred限定の条件分岐は撤去)、推定値のみ背景塗り+太字で視覚的に目立たせる設計意図(CSS)が維持されている"
  else
    echo "  [FAIL] 1-170: permission-screen出力で3値統一バッジ描画または推定値強調のCSSが確認できない" >&2
    rc=1
  fi
  local prov_embedded="$tmp/embedded-permission-screen-provenance.json"
  local prov_expected="$tmp/expected-permission-screen-provenance.json"
  extract_manifest_json "$prov_out" | jq -c -S . > "$prov_embedded" 2>/dev/null || true
  jq -c -S . "$tmp/fixture-permission-screen-provenance.json" > "$prov_expected"
  if _gt_out3="$(diff -q "$prov_embedded" "$prov_expected" 2>&1)"; then
    echo "  [PASS] 1-170: valueProvenance付きpermission-screenの埋め込みJSONが原本フィクスチャと完全一致"
  else
    echo "  [FAIL] 1-170: valueProvenance付きpermission-screenの埋め込みJSONが原本フィクスチャと不一致" >&2
    printf '%s\n' "$_gt_out3" | sed 's/^/    /' >&2
    rc=1
  fi

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

  # --- 改善課題1-85: 空の必須軸は既存ページを既定で保持し、明示時だけ削除する ---
  local empty_crud="$tmp/fixture-crud-empty.json"
  local empty_crud_out="$tmp/out-crud-empty.html"
  local empty_crud_skip_log="$tmp/crud-empty-skip.log"
  local empty_crud_delete_log="$tmp/crud-empty-delete.log"
  local empty_crud_generate_rc=0 empty_crud_skip_rc=0 empty_crud_delete_rc=0
  jq -n '{generatedAt: "2026-01-01T00:00:00Z", dataSource: "self-test", tables: [], features: []}' \
    > "$empty_crud"
  bash "$script_path" crud "$tmp/fixture-crud.json" "$empty_crud_out" >/dev/null 2>&1 || empty_crud_generate_rc=$?
  bash "$script_path" crud "$empty_crud" "$empty_crud_out" \
    >"$empty_crud_skip_log" 2>&1 || empty_crud_skip_rc=$?
  if bash -c "[ $empty_crud_skip_rc -eq 0 ] && [ -f '$empty_crud_out' ] && grep -Fq 'SKIP:' '$empty_crud_skip_log' && grep -Fq '$empty_crud_out' '$empty_crud_skip_log'"; then
    echo "  [PASS] 改善課題1-85: 空crudは既定で既存ページを保持し、SKIPと対象ファイル名を出力してexit 0"
  else
    echo "  [FAIL] 改善課題1-85: 空crudの既定保持、SKIP出力、またはexit 0を確認できない" >&2
    rc=1
  fi
  bash "$script_path" crud "$empty_crud" "$empty_crud_out" --delete-on-empty \
    >"$empty_crud_delete_log" 2>&1 || empty_crud_delete_rc=$?
  if bash -c "[ $empty_crud_delete_rc -eq 2 ] && [ ! -e '$empty_crud_out' ] && grep -Fq 'DELETE:' '$empty_crud_delete_log' && grep -Fq '$empty_crud_out' '$empty_crud_delete_log'"; then
    echo "  [PASS] 改善課題1-85: --delete-on-emptyは既存ページを削除し、DELETEと対象ファイル名を出力してexit 2"
  else
    echo "  [FAIL] 改善課題1-85: 明示削除、DELETE出力、またはexit 2を確認できない" >&2
    rc=1
  fi
  if bash -c "[ $empty_crud_generate_rc -eq 0 ] && [ -f '$tmp/out-crud.html' ]"; then
    echo "  [PASS] 改善課題1-85: 非空crudは従来どおり生成してexit 0"
  else
    echo "  [FAIL] 改善課題1-85: 非空crudの生成またはexit 0を確認できない" >&2
    rc=1
  fi

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

  # --- 1-203: 一覧からの?q=相互参照を検索窓へ引き継ぎ、絞り込みを実行する実装を保持する ---
  local traceability_out="$tmp/out-traceability.html"
  if [ -f "$traceability_out" ] \
     && node - "$traceability_out" <<'NODE'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync(process.argv[2], 'utf8');
const startMarker = '/* --- 検索絞り込み(現在モードの行に適用) --- */';
const endMarker = '  })();';
const start = html.indexOf(startMarker);
const end = html.indexOf(endMarker, start);
assert.notEqual(start, -1, '検索絞り込みの実JS断片を開始できない');
assert.notEqual(end, -1, '検索絞り込みの実JS断片を終端できない');
const script = '(function () {\n' + html.slice(start, end + endMarker.length);

const search = { value: '', addEventListener: function () {} };
const matchingRow = { textContent: 'Home dashboard', style: {} };
const nonMatchingRow = { textContent: 'Settings', style: {} };
const tableRow = { textContent: 'home table', style: { display: 'untouched' } };
vm.runInNewContext(script, {
  URLSearchParams: URLSearchParams,
  location: { search: '?q=home' },
  currentMode: 'screen',
  screenRows: [matchingRow, nonMatchingRow],
  tableRows: [tableRow],
  document: {
    getElementById: function (id) {
      assert.equal(id, 'matrix-search');
      return search;
    }
  }
});

assert.equal(search.value, 'home');
assert.equal(matchingRow.style.display, '');
assert.equal(nonMatchingRow.style.display, 'none');
assert.equal(tableRow.style.display, 'untouched');
console.log('TRACEABILITY_Q_HANDOFF_OK');
NODE
  then
    echo "  [PASS] 1-203: traceability出力が?q=を検索窓へ設定し絞り込みを実行する"
  else
    echo "  [FAIL] 1-203: traceability出力の?q=検索引継ぎまたは絞り込み実行が欠落" >&2
    rc=1
  fi

  # --- confirmation-survey: 横断確認事項質問票(questions 1件以上) ---
  jq -n '{
    generatedAt: "2026-01-01T00:00:00Z",
    dataSource: "test",
    questions: [
      {questionKey: "unit-1-業務名未確定", targetUnit: "unit-1",
       question: "業務名を確定してください（現在の推定名: 日次集計）",
       evidence: "batch-manifest.json: nameConfidence=inferred", answerTarget: ""}
    ]
  }' > "$tmp/fixture-confirmation-survey.json"
  run_case "confirmation-survey" "confirmation-survey" "$tmp/fixture-confirmation-survey.json"

  # --- confirmation-survey: questions 0件でも ALWAYS_GENERATE によりページを生成する
  # (改善課題1-169の検収方法2。run_case を使い回すと出力パスが page-type 単位で
  # 固定され1件目のケースと衝突するため、専用の出力パスで個別に検証する) ---
  jq -n '{generatedAt: "2026-01-01T00:00:00Z", dataSource: "test", questions: []}' \
    > "$tmp/fixture-confirmation-survey-empty.json"
  local cs_empty_out="$tmp/out-confirmation-survey-empty.html"
  local _gt_cs_empty_run
  if _gt_cs_empty_run="$(bash "$script_path" confirmation-survey "$tmp/fixture-confirmation-survey-empty.json" "$cs_empty_out" 2>&1)" \
    && [ -f "$cs_empty_out" ]; then
    echo "  [PASS] confirmation-survey(questions 0件): ALWAYS_GENERATEによりSKIPされずページを生成"
  else
    echo "  [FAIL] confirmation-survey(questions 0件): ページが生成されなかった(ALWAYS_GENERATEが機能していない)" >&2
    printf '%s\n' "$_gt_cs_empty_run" | sed 's/^/    /' >&2
    rc=1
  fi
  local cs_empty_embedded="$tmp/embedded-confirmation-survey-empty.json"
  local cs_empty_expected="$tmp/expected-confirmation-survey-empty.json"
  extract_manifest_json "$cs_empty_out" | jq -c -S . > "$cs_empty_embedded" 2>/dev/null || true
  jq -c -S . "$tmp/fixture-confirmation-survey-empty.json" > "$cs_empty_expected"
  if _gt_out4="$(diff -q "$cs_empty_embedded" "$cs_empty_expected" 2>&1)"; then
    echo "  [PASS] confirmation-survey(questions 0件): 埋め込みJSONが原本フィクスチャと完全一致"
  else
    echo "  [FAIL] confirmation-survey(questions 0件): 埋め込みJSONが原本フィクスチャと不一致" >&2
    printf '%s\n' "$_gt_out4" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- tokens.css変更追従: 隔離したbuilder一式の正本にfixture tokenを追加 ---
  # 実リポジトリでは generation-engine/scripts/matrix/ から見て
  # delivery-payload/templates/ は3階層上（../../../delivery-payload/templates）にある。
  # フィクスチャもこの深さを再現するため、scripts一式は token-fixture/shared 配下、
  # templates一式は token-fixture/delivery-payload 配下（shared の兄弟）に置く。
  local token_fixture_container token_fixture_root token_fixture_payload_root token_fixture_script token_fixture_out
  token_fixture_container="$tmp/token-fixture"
  token_fixture_root="$token_fixture_container/shared"
  token_fixture_payload_root="$token_fixture_container/delivery-payload"
  token_fixture_script="$token_fixture_root/scripts/matrix/build-matrix-pages.sh"
  token_fixture_out="$tmp/token-fixture-output.html"
  mkdir -p "$token_fixture_root/scripts/matrix" "$token_fixture_payload_root/templates/matrix" "$token_fixture_payload_root/templates/partials"
  cp "$script_path" "$token_fixture_script"
  cp "$(cd "$(dirname "$script_path")/.." && pwd)/render-template.sh" "$token_fixture_root/scripts/render-template.sh"
  cp "$(cd "$(dirname "$script_path")/.." && pwd)/shell-injection.sh" "$token_fixture_root/scripts/shell-injection.sh"
  cp "$(cd "$(dirname "$script_path")/../../../delivery-payload/templates" && pwd)/tokens.css" "$token_fixture_payload_root/templates/tokens.css"
  cp "$(cd "$(dirname "$script_path")/../../../delivery-payload/templates" && pwd)"/matrix/*.html "$token_fixture_payload_root/templates/matrix/"
  cp "$(cd "$(dirname "$script_path")/../../../delivery-payload/templates" && pwd)"/partials/*.css "$(cd "$(dirname "$script_path")/../../../delivery-payload/templates" && pwd)"/partials/*.html "$token_fixture_payload_root/templates/partials/"
  printf '\n.fixture-token-proof { color: rgb(1, 2, 3); }\n' >> "$token_fixture_payload_root/templates/tokens.css"
  local _gt_token_fixture_run
  if _gt_token_fixture_run="$(bash "$token_fixture_script" crud "$tmp/fixture-crud.json" "$token_fixture_out" 2>&1)" \
    && grep -qF '.fixture-token-proof { color: rgb(1, 2, 3); }' "$token_fixture_out"; then
    echo "  [PASS] tokens.css変更fixture: 再生成HTMLへ正本変更が反映"
  else
    echo "  [FAIL] tokens.css変更fixture: 再生成HTMLへ正本変更が未反映" >&2
    printf '%s\n' "$_gt_token_fixture_run" | sed 's/^/    /' >&2
    rc=1
  fi

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
    local _gt_chain_data_run
    if ! _gt_chain_data_run="$(bash "$data_script" "$chain_dir/data" \
        --screen-manifest "$chain_dir/screen-manifest.json" \
        --api-manifest "$chain_dir/api-manifest.json" \
        --table-manifest "$chain_dir/table-manifest.json" \
        --feature-manifest "$chain_dir/feature-manifest.json" 2>&1)"; then
      echo "  [FAIL] 連結ケース: build-matrix-data.sh の実行自体が失敗した" >&2
      printf '%s\n' "$_gt_chain_data_run" | sed 's/^/    /' >&2
      rc=1
    else
      run_case "連結(permission-screen): data実出力から生成" "permission-screen" "$chain_dir/data/permission-matrix.json"
      run_case "連結(crud): data実出力から生成" "crud" "$chain_dir/data/crud-matrix.json"
      run_case "連結(traceability): data実出力から生成" "traceability" "$chain_dir/data/traceability.json"

      # --- 改善課題1-85: 0件データ連鎖は既存の正常ページを既定で保持する ---
      local zero_chain_dir="$tmp/zero-chain"
      local zero_chain_page="$zero_chain_dir/crud.html"
      local zero_chain_before="$zero_chain_dir/crud-before.html"
      local zero_chain_data_log="$zero_chain_dir/data.log"
      local zero_chain_page_log="$zero_chain_dir/page.log"
      local zero_chain_seed_rc=0 zero_chain_data_rc=0 zero_chain_page_rc=0
      mkdir -p "$zero_chain_dir"
      jq -n '{screens: []}' > "$zero_chain_dir/screen-manifest.json"
      jq -n '{units: []}' > "$zero_chain_dir/api-manifest.json"
      jq -n '{units: []}' > "$zero_chain_dir/feature-manifest.json"
      bash "$script_path" crud "$tmp/fixture-crud.json" "$zero_chain_page" >/dev/null 2>&1 || zero_chain_seed_rc=$?
      if [ "$zero_chain_seed_rc" -eq 0 ]; then
        cp "$zero_chain_page" "$zero_chain_before"
      fi
      bash "$data_script" "$zero_chain_dir/data" \
        --screen-manifest "$zero_chain_dir/screen-manifest.json" \
        --api-manifest "$zero_chain_dir/api-manifest.json" \
        --feature-manifest "$zero_chain_dir/feature-manifest.json" \
        --roles , >"$zero_chain_data_log" 2>&1 || zero_chain_data_rc=$?
      bash "$script_path" crud "$zero_chain_dir/data/crud-matrix.json" "$zero_chain_page" \
        >"$zero_chain_page_log" 2>&1 || zero_chain_page_rc=$?
      if [ "$zero_chain_seed_rc" -eq 0 ] && [ "$zero_chain_data_rc" -eq 0 ] && [ "$zero_chain_page_rc" -eq 0 ] \
        && cmp -s "$zero_chain_before" "$zero_chain_page" \
        && grep -Fq "INFO: zero-row matrix data: $zero_chain_dir/data/crud-matrix.json (tables=0, features=0)" "$zero_chain_data_log" \
        && grep -Fq 'SKIP:' "$zero_chain_page_log" \
        && grep -Fq "$zero_chain_page" "$zero_chain_page_log"; then
        echo "  [PASS] 改善課題1-85: 0件データ連鎖はINFOを出し、既存crudページを保持してSKIP/exit 0となる"
      else
        echo "  [FAIL] 改善課題1-85: 0件データ連鎖で既存crudページの保持、INFO、SKIP、またはexit 0を確認できない" >&2
        rc=1
      fi
    fi
  fi

  # --- 検証の負ケース: 必須キー欠落は非0 exitすること ---
  jq -n '{generatedAt: "2026-01-01T00:00:00Z", dataSource: "x", tables: []}' \
    > "$tmp/fixture-crud-missing.json"
  if _gt_out6="$(bash "$script_path" crud "$tmp/fixture-crud-missing.json" "$tmp/out-missing.html" 2>&1)"; then
    echo "  [FAIL] 負ケース: features欠落のcrudデータが検証を素通りした" >&2
    printf '%s\n' "$_gt_out6" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 負ケース: features欠落のcrudデータを非0 exitで拒否"
  fi

  # --- 検証の負ケース: 未知のpage-typeは非0 exitすること ---
  if _gt_out7="$(bash "$script_path" unknown-type "$tmp/fixture-crud.json" "$tmp/out-unknown.html" 2>&1)"; then
    echo "  [FAIL] 負ケース: 未知のpage-typeが素通りした" >&2
    printf '%s\n' "$_gt_out7" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 負ケース: 未知のpage-typeを非0 exitで拒否"
  fi

  # --- 改善課題1-105: ヘッダ行高さ比率(3倍以下)と左上見出しセルのコントラスト比
  # (4.5以上)をCDP実描画で検証する(列数8以下=デフォルト水平見出しレイアウト) ---
  local header_layout_test
  header_layout_test="$(cd "$(dirname "$script_path")/.." && pwd)/tests/test-matrix-header-compact-layout.cjs"
  if [ ! -f "$header_layout_test" ]; then
    echo "  [FAIL] 改善課題1-105: ヘッダ行コンパクトレイアウト検査スクリプトが見つからない: $header_layout_test" >&2
    rc=1
  elif node "$header_layout_test"; then
    echo "  [PASS] 改善課題1-105: ヘッダ行高さ比率3倍以下・左上見出しコントラスト比4.5以上を3種すべてで満たす"
  else
    echo "  [FAIL] 改善課題1-105: ヘッダ行高さ比率またはコントラスト比が基準を満たさない" >&2
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

USAGE="Usage: build-matrix-pages.sh <page-type> <data.json> <output-html-path> [--delete-on-empty] [--portal-dir <path>] [--project-name <name>] [--generated-at <iso8601>] [--catalog <file>]
  page-type: permission-screen | permission-function | crud | traceability | confirmation-survey | ai-assets"

PAGE_TYPE="${1:?$USAGE}"
DATA_JSON="${2:?$USAGE}"
OUTPUT_HTML="${3:?$USAGE}"
shift 3

PORTAL_DIR_ARG=""
PROJECT_NAME_ARG=""
GENERATED_AT_ARG=""
CATALOG_FILE=""
DELETE_ON_EMPTY=false
while [ $# -gt 0 ]; do
  case "$1" in
    --delete-on-empty)
      DELETE_ON_EMPTY=true
      shift
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
    --generated-at)
      GENERATED_AT_ARG="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      echo "$USAGE" >&2
      exit 1
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

if [ ! -f "$DATA_JSON" ]; then
  echo "ERROR: data.json not found: $DATA_JSON" >&2
  exit 1
fi
if [ -n "$GENERATED_AT_ARG" ] \
  && [ "$(jq -r '.generatedAt // ""' "$DATA_JSON")" != "$GENERATED_AT_ARG" ]; then
  echo "ERROR: data generatedAt does not match --generated-at" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/../../../delivery-payload/templates"
TOKENS_CSS_FILE="$TEMPLATES_DIR/tokens.css"

# --- page-type からテンプレート・JSON埋め込みマーカー・必須トップレベルキーを解決 ---
ALWAYS_GENERATE=false
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
  confirmation-survey)
    TEMPLATE="$TEMPLATES_DIR/matrix/confirmation-survey-template.html"
    JSON_MARKER="<!--MATRIX_JSON-->"
    REQUIRED_KEYS="questions"
    ALWAYS_GENERATE=true
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
if [ ! -f "$TOKENS_CSS_FILE" ]; then
  echo "ERROR: tokens.css not found: $TOKENS_CSS_FILE" >&2
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

# --- 必須成分がすべて0件ならページを生成しない(空白の表だけを公開する経路を断つ。
# delivery-payload/references/manifest-schema-extensions.md「マトリクス・対応表用の新規データ
# ファイル定義」: 該当データが揃った時のみ生成する契約に従う)。既存ページは既定で
# 保持し、--delete-on-empty が明示された場合だけ削除する。一部成分のみ0件の場合はページを生成し、
# テンプレート側JSが空状態コールアウトを表示する。
# 例外: ALWAYS_GENERATE=true(confirmation-survey)は必須成分が0件でも生成する
# (改善課題1-169: 確認事項0件という状態自体を利用者に示すページを常に公開する) ---
all_required_empty=true
for key in $REQUIRED_KEYS; do
  key_length="$(jq -r --arg k "$key" '(.[$k] // []) | if type == "array" then length else 1 end' "$DATA_JSON")"
  if [ "$key_length" -gt 0 ]; then
    all_required_empty=false
    break
  fi
done
if [ "$all_required_empty" = true ] && [ "$ALWAYS_GENERATE" != true ]; then
  if [ "$DELETE_ON_EMPTY" = true ] && [ -f "$OUTPUT_HTML" ]; then
    rm -f "$OUTPUT_HTML"
    echo "DELETE: 必須成分($REQUIRED_KEYS)がすべて0件のため既存ページを削除しました(page-type: $PAGE_TYPE): $OUTPUT_HTML" >&2
    exit 2
  else
    echo "SKIP: 必須成分($REQUIRED_KEYS)がすべて0件のためページを生成せず既存ページを保持します(page-type: $PAGE_TYPE): $OUTPUT_HTML" >&2
  fi
  exit 0
fi

# --- HTMLエスケープ(& < > のみ。& を最初に処理する) ---
html_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# render_template — 共通関数を source(generation-engine/scripts/render-template.sh)
source "$(cd "$(dirname "$0")/.." && pwd)/render-template.sh"
if [ -f "$SCRIPT_DIR/../shell-injection.sh" ]; then
  . "$SCRIPT_DIR/../shell-injection.sh"
fi

# --- メタ情報を data.json から抽出 ---
generated_at="$(jq -r '.generatedAt // ""' "$DATA_JSON")"
if [ -z "$generated_at" ]; then
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi
data_source="$(jq -r '.dataSource // ""' "$DATA_JSON")"
[ -z "$data_source" ] && data_source="—"
# --project-name オプションを優先し、未指定ならdata.jsonのprojectNameへフォールバックする
# (従来はオプションが解析されるだけで無視され、data.json側にprojectNameが無い場合は空表示になっていた)
project_name="${PROJECT_NAME_ARG:-$(jq -r '.projectName // ""' "$DATA_JSON")}"

matrix_json="$(cat "$DATA_JSON")"

mkdir -p "$(dirname "$OUTPUT_HTML")"

# --- ポータルへの相対パス算出(--portal-dir 未指定時はpage-type別の既定値) ---
if [ -n "$PORTAL_DIR_ARG" ]; then
  back_link="$(python3 -c "import os; print(os.path.relpath('$PORTAL_DIR_ARG', '$(dirname "$OUTPUT_HTML")'))" 2>/dev/null || echo ".")/index.html"
else
  case "$PAGE_TYPE" in
    ai-assets)
      back_link="../index.html"
      ;;
    *)
      back_link="../../index.html"
      ;;
  esac
fi

# --- テンプレートへの注入(単一パス方式。render_template()参照) ---
# JSON埋め込みマーカーはテンプレート内で物理的に最後に出現するため、
# 単一パスのdocument-order走査により自動的に最後に処理される
# (JSON内容に他マーカー文字列が偶然含まれた場合の誤爆を避けるため)
render_args=( \
  "{{GENERATED_AT}}" "$(html_escape "$generated_at")" \
  "{{DATA_SOURCE}}" "$(html_escape "$data_source")" \
  "{{PROJECT_NAME}}" "$(html_escape "$project_name")" \
  "{{BACK_LINK}}" "$back_link")
render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
# 共通シェル注入（partials が存在する場合のみ）
if [ "$PAGE_TYPE" = "ai-assets" ]; then
  shell_active_category="ai"
else
  shell_active_category="cross"
fi
catalog_path="${CATALOG_FILE:-$SCRIPT_DIR/../../../delivery-payload/references/portal-catalog.json}"
if type shell_injection_args >/dev/null 2>&1; then
  shell_injection_args "$TEMPLATES_DIR" "$catalog_path" "$back_link" "$project_name" "$generated_at" "" "generation-engine/scripts/matrix/build-matrix-pages.sh" "$shell_active_category"
  if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
    render_args+=("${SHELL_RENDER_ARGS[@]}")
  fi
fi
render_args+=("$JSON_MARKER" "$matrix_json")
out="$(render_template "$(cat "$TEMPLATE")" "${render_args[@]}")"

printf '%s\n' "$out" > "$OUTPUT_HTML"

echo "OK: wrote $OUTPUT_HTML" >&2
