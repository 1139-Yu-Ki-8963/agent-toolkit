#!/usr/bin/env bash
# マトリクス・対応表用データ生成エンジン: 拡張済みマニフェスト群から permission-matrix.json・
# crud-matrix.json・traceability.json の 3 ファイルを決定的に導出する。
# ソースコードは読まない(拡張済みマニフェストのみを入力とする導出エンジン)。
#
# Usage: build-matrix-data.sh <output-dir> --screen-manifest <path> --api-manifest <path>
#                             [--table-manifest <path>] [--feature-manifest <path>]
#                             [--roles <comma-separated>]
#        build-matrix-data.sh --self-test
#
# 入力契約: 各マニフェストは shared/scripts/unit-list/validate-manifest.sh で PASS する
#   拡張済みマニフェスト(スキーマ正本: shared/references/manifest-schema-extensions.md)。
#   導出の根拠に使う任意フィールド:
#     screen-manifest:  screens[].permissions / relatedApis / sourceHash
#     api-manifest:     units[].method / targetTables
#     feature-manifest: units[].relatedApis
#     table-manifest:   units[].unitKey(targetTables の収載確認のみ。出力には影響しない)
#
# 出力契約: <output-dir>/permission-matrix.json・crud-matrix.json・traceability.json の
#   3 ファイル(スキーマは manifest-schema-extensions.md「マトリクス・対応表用の新規データファイル
#   定義」に完全準拠。同スキーマは shared/templates/matrix/ の各テンプレート内 JS が
#   参照するトップレベルキー・フィールド名と一致させている。二重管理・ドリフト禁止)。
#
# 導出規則: method / targetTables が存在する場合の型・値域検査は全 API units に適用する。
#   欠落 method の必須判定では kind=unresolved を除外し、次の CRUD/permission 対象だけを検査する。
#   feature-manifest 指定時は解決済み relatedApis の method を必須とし、targetTables 欠落/[]は許容する。
#   未指定時は targetTables 明示APIだけを候補とし、非空ならmethod必須、[]ならmethod欠落を許容する。
#   method は5動詞、targetTables は空白トリム後に非空の文字列配列に限る。
#   不正値または対象APIの必須値欠落があれば、出力公開前に非ゼロ終了する。
#   1. permission-matrix.json
#      - roles: --roles 指定値。未指定なら全 screens の permissions に現れるロール集合
#        + 暗黙ロール member/guest の和集合(重複除去・アルファベット順で決定的)
#      - screens[]: 全画面を出力する。screenId/screenName は screenKey、route は
#        route(無ければ空文字)。permissions フィールドを持つ画面は
#        {ロール: 真偽値} オブジェクト(空配列なら全ロール true、非空なら該当ロールを
#        含む時のみ true)。permissions 未抽出の画面は誤った全許可を出さないため
#        permissions: null(権限未設定)として出力する
#      - features[].crud: feature.relatedApis の API 群の method から C=POST / R=GET /
#        U=PUT・PATCH / D=DELETE を合成(文字は常に C→R→U→D 順)。ロール別には、その
#        API を relatedApis に持つ画面のいずれかにそのロールがアクセス可能な場合のみ
#        権限ありとする。feature-manifest 不在、または relatedApis を持つ feature が
#        0 件なら features は空配列とし、理由を stderr へ出す
#   2. crud-matrix.json: api.targetTables × api.method から C/R/U/D を合成。
#      - features[]: feature-manifest があれば feature 単位(relatedApis 経由)に集約
#        (featureId=unitKey / featureName=identifier)、無ければ API 単位(featureId に
#        api の unitKey を使い、その旨をトップレベル note フィールドに記録)。
#        上記の対象境界と値検証を満たしたAPIだけを集約する
#      - tables[]: table-manifest があれば全 units を収載順に
#        {physicalName=identifier, logicalName(あれば転記)}、無ければ features[].cells
#        に現れるテーブル名の集合(アルファベット順)
#      - cells のキーは table-manifest で解決した physicalName(未収載・不在時は
#        targetTables の unitKey をそのまま使う)
#   3. traceability.json: 画面→API→テーブルの連鎖を screens/apis/tables の 3 配列で
#      出力する(画面→テーブルの対応はテンプレート JS が screens[].apis と
#      apis[].tables から導出する)。
#      - screens[]: relatedApis を持つ画面のみ(screenId/screenName=screenKey、
#        apis=relatedApis)。sourceHash は screen の sourceHash をそのまま転記
#        (無ければキー自体を省略)
#      - apis[]: 全 API units(apiId/apiName=unitKey、endpoint=identifier、
#        tables=targetTables。無ければ空配列)
#      - tables[]: table-manifest があれば全 units を収載順に
#        {tableId=unitKey, tableName=identifier, logicalName(あれば転記)}、無ければ
#        apis[].tables に現れる unitKey の集合(アルファベット順)
#   - 3 ファイル共通: dataSource に入力マニフェストのパスを記録する
#   - table-manifest 指定時: apis の targetTables に table-manifest 未収載の unitKey が
#     あれば stderr へ警告する(出力内容は変えない)

set -euo pipefail

# ---------------------------------------------------------------------------
# --self-test モード
# 最小の拡張済みマニフェスト群(画面3・API2・テーブル2・機能1)をフィクスチャ生成し、
# (1) フィクスチャ自体が validate-manifest.sh で PASS すること
# (2) 3 ファイルの導出結果が期待値(permissions の真偽値/null・CRUD 文字列と物理名解決・
#     screens/apis/tables の連結整合・sourceHash 転記)に一致すること
# (3) feature-manifest 無しのフォールバック(API 単位 + note)と --roles 明示指定
# を jq で検証する。
# ---------------------------------------------------------------------------
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local validate="$script_dir/../unit-list/validate-manifest.sh"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-matrix-data-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  assert() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
      echo "  [PASS] $desc"
    else
      echo "  [FAIL] $desc" >&2
      rc=1
    fi
  }

  # --- フィクスチャ: ソースファイル(validate-manifest.sh の実在検査用) ---
  mkdir -p "$tmp/src/screens" "$tmp/src/api" "$tmp/src/migrations" "$tmp/src/features"
  echo 'export function UserAdmin() {}' > "$tmp/src/screens/UserAdmin.tsx"
  echo 'export function Home() {}' > "$tmp/src/screens/Home.tsx"
  echo 'def users(): pass' > "$tmp/src/api/users.py"
  echo 'CREATE TABLE users ();' > "$tmp/src/migrations/001_users.sql"
  echo 'CREATE TABLE audit_logs ();' > "$tmp/src/migrations/002_audit_logs.sql"
  echo 'def user_management(): pass' > "$tmp/src/features/user_management.py"

  # --- フィクスチャ: 画面マニフェスト(admin限定画面 + 全員可画面) ---
  local sm="$tmp/screen-manifest.json"
  jq -n --arg sourceDir "$tmp/src" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
    detectionSummary: {screenCount: 3, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
    screens: [
      {screenKey: "user-admin", kind: "route", route: "/admin/users", entryFile: "screens/UserAdmin.tsx",
       confidence: "high", screenType: "top", accountGroup: "admin", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false,
       permissions: ["admin"], relatedApis: ["users-list", "user-delete"], sourceHash: "abcdef123456"},
      {screenKey: "home", kind: "route", route: "/", entryFile: "screens/Home.tsx",
       confidence: "high", screenType: "top", accountGroup: "user", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false,
       permissions: [], relatedApis: ["users-list"]},
      {screenKey: "legacy-report", kind: "route", route: "/legacy/report", entryFile: "screens/Home.tsx",
       confidence: "low", screenType: "detail", accountGroup: "report", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false}
    ]
  }' > "$sm"

  # --- フィクスチャ: APIマニフェスト(GET + DELETE。targetTables付き) ---
  local am="$tmp/api-manifest.json"
  jq -n --arg sourceDir "$tmp/src" --arg sf "$tmp/src/api/users.py" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "api",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 2, unresolvedCount: 0},
    units: [
      {unitKey: "users-list", kind: "endpoint", identifier: "GET /api/users", sourceFile: $sf,
       confidence: "high", method: "GET", targetTables: ["users"]},
      {unitKey: "user-delete", kind: "endpoint", identifier: "DELETE /api/users/:id", sourceFile: $sf,
       confidence: "high", method: "DELETE", targetTables: ["users", "audit-logs"]}
    ]
  }' > "$am"

  # --- フィクスチャ: テーブルマニフェスト ---
  local tm="$tmp/table-manifest.json"
  jq -n --arg sourceDir "$tmp/src" --arg sf1 "$tmp/src/migrations/001_users.sql" --arg sf2 "$tmp/src/migrations/002_audit_logs.sql" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "table",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 2, unresolvedCount: 0},
    units: [
      {unitKey: "users", kind: "table", identifier: "users", sourceFile: $sf1, confidence: "high", logicalName: "ユーザー"},
      {unitKey: "audit-logs", kind: "table", identifier: "audit_logs", sourceFile: $sf2, confidence: "high"}
    ]
  }' > "$tm"

  # --- フィクスチャ: 機能マニフェスト(relatedApisでAPI 2本を束ねる) ---
  local fm="$tmp/feature-manifest.json"
  jq -n --arg sourceDir "$tmp/src" --arg sf "$tmp/src/features/user_management.py" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "feature",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [
      {unitKey: "user-management", kind: "feature", identifier: "user-management", sourceFile: $sf,
       confidence: "high", relatedApis: ["users-list", "user-delete"]}
    ]
  }' > "$fm"

  # --- フィクスチャの妥当性(validate-manifest.sh で PASS すること) ---
  assert "フィクスチャ検証: screen-manifest が validate-manifest.sh で PASS" \
    bash "$validate" "$sm" --unit-kind screen
  assert "フィクスチャ検証: api-manifest が validate-manifest.sh で PASS" \
    bash "$validate" "$am" --unit-kind api
  assert "フィクスチャ検証: table-manifest が validate-manifest.sh で PASS" \
    bash "$validate" "$tm" --unit-kind table
  assert "フィクスチャ検証: feature-manifest が validate-manifest.sh で PASS" \
    bash "$validate" "$fm" --unit-kind feature

  # --- ケースa: フル指定(feature-manifest あり) ---
  local out="$tmp/out"
  assert "ケースa: フル指定で生成コマンドが成功" \
    bash "$script_path" "$out" --screen-manifest "$sm" --api-manifest "$am" \
      --table-manifest "$tm" --feature-manifest "$fm"

  local pm="$out/permission-matrix.json" cm="$out/crud-matrix.json" tr_json="$out/traceability.json"
  assert "ケースa: 3ファイルがすべて生成される" \
    bash -c "[ -f '$pm' ] && [ -f '$cm' ] && [ -f '$tr_json' ]"
  assert "ケースa: output親配下にstaging siblingが残らない" \
    bash -c "! find '$tmp' -maxdepth 1 -type d -name '.out.matrix-staging.*' | grep -q ."

  # permission-matrix: roles・permissions真偽値/null・feature CRUD
  assert "permission-matrix: roles が検出ロール+暗黙member/guest" \
    jq -e '.roles == ["admin","guest","member"]' "$pm"
  assert "permission-matrix: 全画面(permissions未抽出含む)が screens に出力される" \
    jq -e '.screens | length == 3' "$pm"
  assert "permission-matrix: admin限定画面は admin のみ true(screenId/screenName/route 付き)" \
    jq -e '.screens[] | select(.screenId == "user-admin")
           | .screenName == "user-admin" and .route == "/admin/users"
             and .permissions == {"admin": true, "guest": false, "member": false}' "$pm"
  assert "permission-matrix: permissions空配列の画面は全ロール true" \
    jq -e '.screens[] | select(.screenId == "home") | .permissions | to_entries | all(.value == true)' "$pm"
  assert "permission-matrix: permissions未抽出の画面は permissions:null(権限未設定)" \
    jq -e '(.screens[] | select(.screenId == "legacy-report") | .permissions) == null' "$pm"
  assert "permission-matrix: feature CRUD(admin=RD/member=R/guest=R)" \
    jq -e '.features == [{"unitKey": "user-management", "crud": {"admin": "RD", "guest": "R", "member": "R"}}]' "$pm"

  # crud-matrix: tables列(物理名解決)・feature単位集約・CRUD文字の合成
  assert "crud-matrix: tables は table-manifest 全収載(physicalName=identifier/logicalName転記)" \
    jq -e '.tables == [{"physicalName": "users", "logicalName": "ユーザー"}, {"physicalName": "audit_logs"}]' "$cm"
  assert "crud-matrix: feature単位で users=RD / audit_logs=D(cells キーは物理名)" \
    jq -e '.features == [{"featureId": "user-management", "featureName": "user-management",
                          "cells": {"users": "RD", "audit_logs": "D"}}]' "$cm"
  assert "crud-matrix: feature-manifest 指定時は note を持たない" \
    jq -e 'has("note") | not' "$cm"

  # traceability: screens/apis/tables 3配列・連結整合・sourceHash転記
  assert "traceability: relatedApis を持つ画面2件が screens になる" \
    jq -e '.screens | length == 2' "$tr_json"
  assert "traceability: user-admin の連鎖(apis 2本・route・sourceHash 転記)" \
    jq -e '.screens[] | select(.screenId == "user-admin")
           | .screenName == "user-admin" and .route == "/admin/users"
             and .sourceHash == "abcdef123456"
             and .apis == ["users-list", "user-delete"]' "$tr_json"
  assert "traceability: sourceHash 無しの画面はキー自体を省略" \
    jq -e '.screens[] | select(.screenId == "home")
           | (has("sourceHash") | not) and (.apis == ["users-list"])' "$tr_json"
  assert "traceability: apis は endpoint=identifier / tables=targetTables" \
    jq -e '(.apis | length == 2)
           and ((.apis[] | select(.apiId == "user-delete"))
                == {"apiId": "user-delete", "apiName": "user-delete",
                    "endpoint": "DELETE /api/users/:id", "tables": ["users", "audit-logs"]})' "$tr_json"
  assert "traceability: tables は table-manifest 全収載(tableId=unitKey/tableName=identifier)" \
    jq -e '.tables == [{"tableId": "users", "tableName": "users", "logicalName": "ユーザー"},
                       {"tableId": "audit-logs", "tableName": "audit_logs"}]' "$tr_json"

  # --- ケースb: feature-manifest 無し(API単位フォールバック + note) ---
  local out2="$tmp/out2"
  assert "ケースb: feature-manifest 無しでも生成コマンドが成功" \
    bash "$script_path" "$out2" --screen-manifest "$sm" --api-manifest "$am"
  assert "ケースb: crud-matrix は API 単位(featureId=unitKey)+ note 記録" \
    jq -e 'has("note")
           and (.features | length == 2)
           and ((.features[] | select(.featureId == "users-list") | .cells) == {"users": "R"})
           and ((.features[] | select(.featureId == "user-delete") | .cells) == {"users": "D", "audit-logs": "D"})' \
    "$out2/crud-matrix.json"
  assert "ケースb: table-manifest 無しの tables は cells 出現テーブルの集合" \
    jq -e '.tables == [{"physicalName": "audit-logs"}, {"physicalName": "users"}]' \
    "$out2/crud-matrix.json"
  assert "ケースb: permission-matrix の features は空配列" \
    jq -e '.features == []' "$out2/permission-matrix.json"

  # --- ケースc: --roles 明示指定(トリム込み) ---
  local out3="$tmp/out3"
  assert "ケースc: --roles 指定で生成コマンドが成功" \
    bash "$script_path" "$out3" --screen-manifest "$sm" --api-manifest "$am" --roles "admin, editor"
  assert "ケースc: roles は指定値のみ(トリム済み)" \
    jq -e '.roles == ["admin", "editor"]
           and ((.screens[] | select(.screenId == "user-admin") | .permissions) == {"admin": true, "editor": false})' \
    "$out3/permission-matrix.json"

  # --- ケースd: feature-manifest の unitKey 重複(検査A) ---
  local fm_dup="$tmp/feature-manifest-dup.json"
  jq -n --arg sourceDir "$tmp/src" --arg sf "$tmp/src/features/user_management.py" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "feature",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 2, unresolvedCount: 0},
    units: [
      {unitKey: "user-management", kind: "feature", identifier: "user-management", sourceFile: $sf,
       confidence: "high", relatedApis: ["users-list"]},
      {unitKey: "user-management", kind: "feature", identifier: "user-management-dup", sourceFile: $sf,
       confidence: "high", relatedApis: ["user-delete"]}
    ]
  }' > "$fm_dup"

  local out_dup="$tmp/out-dup" dup_stderr="$tmp/dup-stderr.log" dup_rc=0
  bash "$script_path" "$out_dup" --screen-manifest "$sm" --api-manifest "$am" --feature-manifest "$fm_dup" \
    >/dev/null 2>"$dup_stderr" || dup_rc=$?
  assert "ケースd: 重複unitKeyで生成コマンドがexit 1" \
    bash -c "[ $dup_rc -eq 1 ]"
  assert "ケースd: stderrに重複するunitKeyのエラーが出力される" \
    grep -q "重複する unitKey" "$dup_stderr"
  assert "ケースd: stderrに重複したunitKey(user-management)が出力される" \
    grep -q "user-management" "$dup_stderr"

  # --- ケースe: relatedApis参照先APIがmethodを持たない(CRUD判定材料の事前検査) ---
  local am_nomethod="$tmp/api-manifest-nomethod.json"
  jq -n --arg sourceDir "$tmp/src" --arg sf "$tmp/src/api/users.py" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "api",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [
      {unitKey: "users-list", kind: "endpoint", identifier: "GET /api/users", sourceFile: $sf,
       confidence: "high", targetTables: ["users"]}
    ]
  }' > "$am_nomethod"

  local fm_nomethod="$tmp/feature-manifest-nomethod.json"
  jq -n --arg sourceDir "$tmp/src" --arg sf "$tmp/src/features/user_management.py" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "feature",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [
      {unitKey: "user-management", kind: "feature", identifier: "user-management", sourceFile: $sf,
       confidence: "high", relatedApis: ["users-list"]}
    ]
  }' > "$fm_nomethod"

  local out_nomethod="$tmp/out-nomethod" nomethod_stderr="$tmp/nomethod-stderr.log" nomethod_rc=0
  bash "$script_path" "$out_nomethod" --screen-manifest "$sm" --api-manifest "$am_nomethod" --feature-manifest "$fm_nomethod" \
    >/dev/null 2>"$nomethod_stderr" || nomethod_rc=$?
  assert "ケースe: method欠落APIのみ参照時に生成コマンドがexit 1" \
    bash -c "[ $nomethod_rc -eq 1 ]"
  assert "ケースe: stderrにCRUD判定材料不足のエラーが出力される" \
    grep -q "CRUD判定材料が不正または不足" "$nomethod_stderr"
  assert "ケースe: stderrに不足フィールド(method)が列挙される" \
    grep -q "method" "$nomethod_stderr"
  assert "ケースe: 失敗時に出力ファイルを残さない" \
    bash -c "[ ! -e '$out_nomethod/permission-matrix.json' ] && [ ! -e '$out_nomethod/crud-matrix.json' ] && [ ! -e '$out_nomethod/traceability.json' ]"

  # --- ケースf: feature参照APIのtargetTables欠落は非CRUDとして許容 ---
  local am_notables="$tmp/api-manifest-notables.json"
  jq -n --arg sourceDir "$tmp/src" --arg sf "$tmp/src/api/users.py" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "api",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [
      {unitKey: "users-list", kind: "endpoint", identifier: "GET /api/users", sourceFile: $sf,
       confidence: "high", method: "GET"}
    ]
  }' > "$am_notables"

  local out_notables="$tmp/out-notables" notables_stderr="$tmp/notables-stderr.log" notables_rc=0
  bash "$script_path" "$out_notables" --screen-manifest "$sm" --api-manifest "$am_notables" --feature-manifest "$fm_nomethod" \
    >/dev/null 2>"$notables_stderr" || notables_rc=$?
  assert "ケースf: targetTables欠落のfeature参照APIは非CRUDとして成功" \
    bash -c "[ $notables_rc -eq 0 ]"
  assert "ケースf: targetTables欠落でも3成果物を生成する" \
    bash -c "[ -f '$out_notables/permission-matrix.json' ] && [ -f '$out_notables/crud-matrix.json' ] && [ -f '$out_notables/traceability.json' ]"
  assert "ケースf: method由来のpermission CRUDは維持し、table CRUD行は作らない" \
    bash -c "jq -e '.features == [{\"unitKey\": \"user-management\", \"crud\": {\"admin\": \"R\", \"guest\": \"R\", \"member\": \"R\"}}]' '$out_notables/permission-matrix.json' >/dev/null && jq -e '.features == []' '$out_notables/crud-matrix.json' >/dev/null"

  # --- ケースg: feature参照APIのmethod欠落は停止（targetTables欠落は許容） ---
  local am_missing_both="$tmp/api-manifest-missing-both.json"
  jq -n --arg sourceDir "$tmp/src" --arg sf "$tmp/src/api/users.py" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "api",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [
      {unitKey: "users-list", kind: "endpoint", identifier: "GET /api/users", sourceFile: $sf,
       confidence: "high"}
    ]
  }' > "$am_missing_both"

  local out_missing_both="$tmp/out-missing-both" missing_both_stderr="$tmp/missing-both-stderr.log" missing_both_rc=0
  bash "$script_path" "$out_missing_both" --screen-manifest "$sm" --api-manifest "$am_missing_both" --feature-manifest "$fm_nomethod" \
    >/dev/null 2>"$missing_both_stderr" || missing_both_rc=$?
  assert "ケースg: method/targetTables両欠落のfeature参照APIはexit 1" \
    bash -c "[ $missing_both_rc -eq 1 ]"
  assert "ケースg: stderrに不足フィールド(method)だけが列挙される" \
    bash -c "grep -q '不足フィールド: method' '$missing_both_stderr' && ! grep -q '不足フィールド: targetTables' '$missing_both_stderr'"
  assert "ケースg: 失敗時に出力ファイルを残さない" \
    bash -c "[ ! -e '$out_missing_both/permission-matrix.json' ] && [ ! -e '$out_missing_both/crud-matrix.json' ] && [ ! -e '$out_missing_both/traceability.json' ]"

  # --- ケースh: feature-manifest指定だが units 空(検査A/Bともに対象外の回帰確認) ---
  local fm_empty="$tmp/feature-manifest-empty.json"
  jq -n --arg sourceDir "$tmp/src" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "feature",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 0, unresolvedCount: 0},
    units: []
  }' > "$fm_empty"

  local out_empty="$tmp/out-empty"
  assert "ケースh: feature-manifestのunits空でも生成コマンドが成功(回帰確認)" \
    bash "$script_path" "$out_empty" --screen-manifest "$sm" --api-manifest "$am" --feature-manifest "$fm_empty"
  assert "ケースh: permission-matrix の features は空配列" \
    jq -e '.features == []' "$out_empty/permission-matrix.json"

  # --- ケースi: featureなしの非CRUD境界（unresolved / targetTables欠落 / 空配列） ---
  local am_noncrud="$tmp/api-manifest-noncrud.json"
  jq -n --arg sourceDir "$tmp/src" --arg sf "$tmp/src/api/users.py" '{
    generatedAt: "2026-01-01T00:00:00Z", sourceDir: $sourceDir, unitKind: "api",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 3, unresolvedCount: 1},
    units: [
      {unitKey: "unresolved-api", kind: "unresolved", identifier: "unknown", sourceFile: $sf, confidence: "low"},
      {unitKey: "no-table-evidence", kind: "endpoint", identifier: "GET /api/no-table-evidence", sourceFile: $sf, confidence: "high"},
      {unitKey: "checked-zero-tables", kind: "endpoint", identifier: "GET /api/checked-zero", sourceFile: $sf, confidence: "high", method: "GET", targetTables: []}
    ]
  }' > "$am_noncrud"
  local out_noncrud="$tmp/out-noncrud"
  assert "ケースi: featureなしのunresolved・targetTables欠落・空配列APIは成功" \
    bash "$script_path" "$out_noncrud" --screen-manifest "$sm" --api-manifest "$am_noncrud"
  assert "ケースi: 非CRUD境界でも3成果物を生成する" \
    bash -c "[ -f '$out_noncrud/permission-matrix.json' ] && [ -f '$out_noncrud/crud-matrix.json' ] && [ -f '$out_noncrud/traceability.json' ]"

  # --- ケースj: featureなしでtargetTables非空かつmethod欠落は停止 ---
  local out_nomethod_no_feature="$tmp/out-nomethod-no-feature" nomethod_no_feature_stderr="$tmp/nomethod-no-feature-stderr.log" nomethod_no_feature_rc=0
  bash "$script_path" "$out_nomethod_no_feature" --screen-manifest "$sm" --api-manifest "$am_nomethod" \
    >/dev/null 2>"$nomethod_no_feature_stderr" || nomethod_no_feature_rc=$?
  assert "ケースj: featureなしのtargetTables非空かつmethod欠落はexit 1" \
    bash -c "[ $nomethod_no_feature_rc -eq 1 ]"
  assert "ケースj: method不足と出力0を報告する" \
    bash -c "grep -q '不足フィールド: method' '$nomethod_no_feature_stderr' && [ ! -e '$out_nomethod_no_feature/permission-matrix.json' ] && [ ! -e '$out_nomethod_no_feature/crud-matrix.json' ] && [ ! -e '$out_nomethod_no_feature/traceability.json' ]"

  # --- ケースk: methodの値域違反は出力前に停止 ---
  local method_case method_filter method_stderr method_out method_rc
  for method_case in null empty OPTIONS number; do
    case "$method_case" in
      null) method_filter='.units[0].method = null' ;;
      empty) method_filter='.units[0].method = ""' ;;
      OPTIONS) method_filter='.units[0].method = "OPTIONS"' ;;
      number) method_filter='.units[0].method = 1' ;;
    esac
    jq "$method_filter" "$am" > "$tmp/api-manifest-method-$method_case.json"
    method_stderr="$tmp/method-$method_case-stderr.log"
    method_out="$tmp/out-method-$method_case"
    method_rc=0
    bash "$script_path" "$method_out" --screen-manifest "$sm" --api-manifest "$tmp/api-manifest-method-$method_case.json" \
      >/dev/null 2>"$method_stderr" || method_rc=$?
    assert "ケースk-$method_case: 不正methodはexit 1・不正フィールド表示・出力0" \
      bash -c "[ $method_rc -eq 1 ] && grep -q '不正フィールド: method' '$method_stderr' && [ ! -e '$method_out/permission-matrix.json' ] && [ ! -e '$method_out/crud-matrix.json' ] && [ ! -e '$method_out/traceability.json' ]"
  done

  # --- ケースl: targetTablesの型・要素違反は出力前に停止 ---
  local tables_case tables_filter tables_stderr tables_out tables_rc
  for tables_case in null string empty-element number-element; do
    case "$tables_case" in
      null) tables_filter='.units[0].targetTables = null' ;;
      string) tables_filter='.units[0].targetTables = "users"' ;;
      empty-element) tables_filter='.units[0].targetTables = [""]' ;;
      number-element) tables_filter='.units[0].targetTables = [1]' ;;
    esac
    jq "$tables_filter" "$am" > "$tmp/api-manifest-target-tables-$tables_case.json"
    tables_stderr="$tmp/target-tables-$tables_case-stderr.log"
    tables_out="$tmp/out-target-tables-$tables_case"
    tables_rc=0
    bash "$script_path" "$tables_out" --screen-manifest "$sm" --api-manifest "$tmp/api-manifest-target-tables-$tables_case.json" \
      >/dev/null 2>"$tables_stderr" || tables_rc=$?
    assert "ケースl-$tables_case: 不正targetTablesはexit 1・不正フィールド表示・出力0" \
      bash -c "[ $tables_rc -eq 1 ] && grep -q '不正フィールド: targetTables' '$tables_stderr' && [ ! -e '$tables_out/permission-matrix.json' ] && [ ! -e '$tables_out/crud-matrix.json' ] && [ ! -e '$tables_out/traceability.json' ]"
  done

  # --- ケースm: 同梱API一覧をfeatureなしで導出できる ---
  local repo_root sample_api sample_screen sample_out
  repo_root="$(cd "$script_dir/../../.." && pwd)"
  sample_api="$tmp/sample-api-manifest.json"
  sample_screen="$repo_root/shared/samples/一覧/画面一覧/screen-manifest.ext.json"
  sample_out="$tmp/out-sample"
  awk '/^[[:space:]]*<script[^>]*id="unit-manifest"/{inside=1; next} inside && /<\/script>/{exit} inside{print}' \
    "$repo_root/shared/samples/一覧/API一覧/API一覧.html" > "$sample_api"
  assert "ケースm: 同梱API一覧JSONを抽出できる" jq empty "$sample_api"
  assert "ケースm: 同梱サンプルをfeatureなしで導出できる" \
    bash "$script_path" "$sample_out" --screen-manifest "$sample_screen" --api-manifest "$sample_api"
  assert "ケースm: 同梱サンプルで3成果物を生成する" \
    bash -c "[ -f '$sample_out/permission-matrix.json' ] && [ -f '$sample_out/crud-matrix.json' ] && [ -f '$sample_out/traceability.json' ]"

  # --- ケースn: feature参照先がunresolvedならpermission/crudへ混入させない ---
  local sm_unresolved="$tmp/screen-manifest-unresolved.json" am_unresolved="$tmp/api-manifest-unresolved.json"
  local fm_unresolved="$tmp/feature-manifest-unresolved.json" out_unresolved="$tmp/out-unresolved"
  jq -n '{screens:[{screenKey:"ghost-screen",route:"/ghost",permissions:[],relatedApis:["ghost-api"]}]}' > "$sm_unresolved"
  jq -n '{units:[{unitKey:"ghost-api",kind:"unresolved",identifier:"GET /ghost",method:"GET",targetTables:["users"]}]}' > "$am_unresolved"
  jq -n '{units:[{unitKey:"ghost-feature",kind:"feature",identifier:"ghost-feature",relatedApis:["ghost-api"]}]}' > "$fm_unresolved"
  assert "ケースn: unresolved API参照でも生成コマンドが成功" \
    bash "$script_path" "$out_unresolved" --screen-manifest "$sm_unresolved" --api-manifest "$am_unresolved" --feature-manifest "$fm_unresolved"
  assert "ケースn: unresolved APIはpermission CRUD文字とcrud行へ混入しない" \
    bash -c "jq -e '.features == [{\"unitKey\":\"ghost-feature\",\"crud\":{\"guest\":\"\",\"member\":\"\"}}]' '$out_unresolved/permission-matrix.json' >/dev/null && jq -e '.features == []' '$out_unresolved/crud-matrix.json' >/dev/null"

  # --- ケースo: 失敗時は旧3成果物だけ除去し、無関係ファイルを保持 ---
  local out_stale="$tmp/out-stale" stale_stderr="$tmp/stale-stderr.log" stale_rc=0
  mkdir -p "$out_stale"
  printf '%s\n' old > "$out_stale/permission-matrix.json"
  printf '%s\n' old > "$out_stale/crud-matrix.json"
  printf '%s\n' old > "$out_stale/traceability.json"
  printf '%s\n' keep > "$out_stale/keep.txt"
  bash "$script_path" "$out_stale" --screen-manifest "$sm" --api-manifest "$am_nomethod" \
    >/dev/null 2>"$stale_stderr" || stale_rc=$?
  assert "ケースo: method不足入力はexit 1" bash -c "[ $stale_rc -eq 1 ]"
  assert "ケースo: 旧3成果物は消え、無関係keep.txtは残る" \
    bash -c "[ ! -e '$out_stale/permission-matrix.json' ] && [ ! -e '$out_stale/crud-matrix.json' ] && [ ! -e '$out_stale/traceability.json' ] && [ -f '$out_stale/keep.txt' ]"

  # --- ケースp: 公開途中の失敗でも対象3成果物をrollbackし、staging siblingを残さない ---
  local out_rollback="$tmp/out-rollback" rollback_bin="$tmp/rollback-bin"
  local rollback_counter="$tmp/rollback-mv-count" rollback_stderr="$tmp/rollback-stderr.log" rollback_rc=0
  mkdir -p "$out_rollback" "$rollback_bin"
  printf '%s\n' old > "$out_rollback/permission-matrix.json"
  printf '%s\n' old > "$out_rollback/crud-matrix.json"
  printf '%s\n' old > "$out_rollback/traceability.json"
  printf '%s\n' keep > "$out_rollback/keep.txt"
  printf '%s\n' 0 > "$rollback_counter"
  cat > "$rollback_bin/mv" <<'EOF'
#!/usr/bin/env bash
count="$(cat "$MV_SHIM_COUNT_FILE")"
count=$((count + 1))
printf '%s\n' "$count" > "$MV_SHIM_COUNT_FILE"
if [ "$count" -eq 2 ]; then
  exit 97
fi
exec /bin/mv "$@"
EOF
  chmod +x "$rollback_bin/mv"
  PATH="$rollback_bin:$PATH" MV_SHIM_COUNT_FILE="$rollback_counter" \
    bash "$script_path" "$out_rollback" --screen-manifest "$sm" --api-manifest "$am" \
    >/dev/null 2>"$rollback_stderr" || rollback_rc=$?
  assert "ケースp: 2件目の公開mv失敗は非ゼロ終了" \
    bash -c "[ $rollback_rc -ne 0 ] && [ \"\$(cat '$rollback_counter')\" -eq 2 ]"
  assert "ケースp: rollbackで対象3成果物・staging siblingを除去し、無関係keep.txtを保持" \
    bash -c "[ ! -e '$out_rollback/permission-matrix.json' ] && [ ! -e '$out_rollback/crud-matrix.json' ] && [ ! -e '$out_rollback/traceability.json' ] && [ -f '$out_rollback/keep.txt' ] && ! find '$tmp' -maxdepth 1 -type d -name '.out-rollback.matrix-staging.*' -print -quit | grep -q ."

  # --- ケースq/r: unresolvedでも明示targetTablesの値・型は検査する ---
  local unresolved_tables_case unresolved_tables_value unresolved_tables_manifest
  local unresolved_tables_out unresolved_tables_stderr unresolved_tables_rc
  for unresolved_tables_case in string whitespace; do
    case "$unresolved_tables_case" in
      string) unresolved_tables_value='"bad"' ;;
      whitespace) unresolved_tables_value='["   "]' ;;
    esac
    unresolved_tables_manifest="$tmp/api-manifest-unresolved-target-tables-$unresolved_tables_case.json"
    jq -n --argjson targetTables "$unresolved_tables_value" \
      '{units:[{unitKey:"unresolved-invalid-tables",kind:"unresolved",identifier:"unknown",targetTables:$targetTables}]}' \
      > "$unresolved_tables_manifest"
    unresolved_tables_out="$tmp/out-unresolved-target-tables-$unresolved_tables_case"
    unresolved_tables_stderr="$tmp/unresolved-target-tables-$unresolved_tables_case-stderr.log"
    mkdir -p "$unresolved_tables_out"
    printf '%s\n' old > "$unresolved_tables_out/permission-matrix.json"
    printf '%s\n' old > "$unresolved_tables_out/crud-matrix.json"
    printf '%s\n' old > "$unresolved_tables_out/traceability.json"
    unresolved_tables_rc=0
    bash "$script_path" "$unresolved_tables_out" --screen-manifest "$sm" --api-manifest "$unresolved_tables_manifest" \
      >/dev/null 2>"$unresolved_tables_stderr" || unresolved_tables_rc=$?
    assert "ケース$unresolved_tables_case: unresolvedの不正targetTablesはexit 1・unitKey表示・旧/部分成果物0" \
      bash -c "[ $unresolved_tables_rc -eq 1 ] && grep -q '不正フィールド: targetTables' '$unresolved_tables_stderr' && grep -q 'unresolved-invalid-tables' '$unresolved_tables_stderr' && [ ! -e '$unresolved_tables_out/permission-matrix.json' ] && [ ! -e '$unresolved_tables_out/crud-matrix.json' ] && [ ! -e '$unresolved_tables_out/traceability.json' ]"
  done

  # --- ケースs: 生成済み機能一覧→matrix→permission-function連結 ---
  local feature_html="$repo_root/shared/samples/一覧/機能一覧/機能一覧.html"
  local api_html="$repo_root/shared/samples/一覧/API一覧/API一覧.html"
  local screen_sample="$repo_root/shared/samples/一覧/画面一覧/screen-manifest.ext.json"
  local feature_sample="$tmp/feature-manifest-sample.json"
  local api_sample="$tmp/api-manifest-sample.json"
  awk '/^[[:space:]]*<script[^>]*id="unit-manifest"/{inside=1; next} inside && /<\/script>/{exit} inside{print}' \
    "$feature_html" > "$feature_sample"
  awk '/^[[:space:]]*<script[^>]*id="unit-manifest"/{inside=1; next} inside && /<\/script>/{exit} inside{print}' \
    "$api_html" > "$api_sample"
  assert "ケースs: feature relatedApis は API unitKey に全件対応する" \
    jq -s -e '(.[0].units | map(.unitKey) | unique) as $api_keys
           | [.[1].units[] | (.relatedApis // [])[]
              | select(. as $key | $api_keys | index($key) == null)]
           | length == 0' "$api_sample" "$feature_sample"

  local out_feature_chain="$tmp/out-feature-chain"
  local sample_hash="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  assert "ケースs: 生成済み一覧からmatrix生成が成功" \
    bash "$script_path" "$out_feature_chain" --screen-manifest "$screen_sample" --api-manifest "$api_sample" \
      --feature-manifest "$feature_sample" --generated-at 2026-07-29T00:00:00Z \
      --manifest-content-hash "$sample_hash"

  local permission_function="$out_feature_chain/permission-function.json"
  assert "ケースs: permission-matrixから権限機能JSON生成が成功" \
    bash "$script_dir/build-permission-function-data.sh" "$out_feature_chain/permission-matrix.json" "$permission_function" \
      --generated-at 2026-07-29T00:00:00Z --manifest-content-hash "$sample_hash"
  assert "ケースs: permission-matrix の features に unitKey 重複がない" \
    jq -e '([.features[].unitKey] | length) == ([.features[].unitKey] | unique | length)' \
      "$out_feature_chain/permission-matrix.json"
  assert "ケースs: 権限機能JSONの functions が1件以上" \
    jq -e '.functions | length >= 1' "$permission_function"

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

# ---------------------------------------------------------------------------
# 引数パース
# ---------------------------------------------------------------------------
USAGE="Usage: build-matrix-data.sh <output-dir> --screen-manifest <path> --api-manifest <path> [--table-manifest <path>] [--feature-manifest <path>] [--roles <comma-separated>] [--generated-at <iso8601>] [--manifest-content-hash <sha256>]"
OUTPUT_DIR="${1:?$USAGE}"
shift

SCREEN_MANIFEST=""
API_MANIFEST=""
TABLE_MANIFEST=""
FEATURE_MANIFEST=""
ROLES_CSV=""
GENERATED_AT_ARG=""
MANIFEST_CONTENT_HASH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --screen-manifest)  SCREEN_MANIFEST="${2:-}";  shift 2 ;;
    --api-manifest)     API_MANIFEST="${2:-}";     shift 2 ;;
    --table-manifest)   TABLE_MANIFEST="${2:-}";   shift 2 ;;
    --feature-manifest) FEATURE_MANIFEST="${2:-}"; shift 2 ;;
    --roles)            ROLES_CSV="${2:-}";        shift 2 ;;
    --generated-at)     GENERATED_AT_ARG="${2:-}"; shift 2 ;;
    --manifest-content-hash) MANIFEST_CONTENT_HASH="${2:-}"; shift 2 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      echo "$USAGE" >&2
      exit 1
      ;;
  esac
done

# 前回成功分を今回の失敗結果と誤認させない。既存ディレクトリ内の対象3成果物だけを除去する。
if [ -d "$OUTPUT_DIR" ]; then
  rm -f -- "$OUTPUT_DIR/permission-matrix.json" "$OUTPUT_DIR/crud-matrix.json" "$OUTPUT_DIR/traceability.json"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

if [ -z "$SCREEN_MANIFEST" ] || [ -z "$API_MANIFEST" ]; then
  echo "ERROR: --screen-manifest と --api-manifest は必須です" >&2
  echo "$USAGE" >&2
  exit 1
fi

for f in "$SCREEN_MANIFEST" "$API_MANIFEST" ${TABLE_MANIFEST:+"$TABLE_MANIFEST"} ${FEATURE_MANIFEST:+"$FEATURE_MANIFEST"}; do
  if [ ! -f "$f" ]; then
    echo "ERROR: manifest not found: $f" >&2
    exit 1
  fi
  if ! jq empty "$f" >/dev/null 2>&1; then
    echo "ERROR: invalid JSON: $f" >&2
    exit 1
  fi
done

GENERATED_AT="${GENERATED_AT_ARG:-$(date +%Y-%m-%dT%H:%M:%S%z | sed 's/\(..\)$/:\1/')}"
if { [ -n "$GENERATED_AT_ARG" ] && [ -z "$MANIFEST_CONTENT_HASH" ]; } \
  || { [ -z "$GENERATED_AT_ARG" ] && [ -n "$MANIFEST_CONTENT_HASH" ]; }; then
  echo "ERROR: --generated-at and --manifest-content-hash must be specified together" >&2
  exit 1
fi
if [ -n "$MANIFEST_CONTENT_HASH" ] \
  && ! printf '%s' "$MANIFEST_CONTENT_HASH" | grep -Eq '^[0-9a-f]{64}$'; then
  echo "ERROR: --manifest-content-hash must be 64 lowercase hex" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 導出の素材抽出（ARG_MAX 超過を避けるため、マニフェスト全体はシェル変数へ代入せず
# 各 jq 呼び出しで --slurpfile によりファイルから直接読ませる）
# ---------------------------------------------------------------------------
if [ -n "$FEATURE_MANIFEST" ]; then
  HAS_FEATURES=true
else
  HAS_FEATURES=false
fi

if [ -n "$TABLE_MANIFEST" ]; then
  HAS_TABLES=true
else
  HAS_TABLES=false
fi

# 未指定の任意マニフェストは /dev/null を渡す（--slurpfile は空ファイルを空配列として読む）
FEATURE_MANIFEST_FILE="${FEATURE_MANIFEST:-/dev/null}"
TABLE_MANIFEST_FILE="${TABLE_MANIFEST:-/dev/null}"

# dataSource: 各ファイルの導出に使った入力マニフェストのパス(メタ表示用)
DS_PERMISSION="screen-manifest.ext.json + api-manifest.json${FEATURE_MANIFEST:+ + feature-manifest.json}"
DS_CRUD="api-manifest.json${FEATURE_MANIFEST:+ + feature-manifest.json}${TABLE_MANIFEST:+ + table-manifest.json}"
DS_TRACE="screen-manifest.ext.json + api-manifest.json${TABLE_MANIFEST:+ + table-manifest.json}"

# roles: --roles 指定値(カンマ区切り・前後空白トリム)。未指定なら検出ロール + member/guest
if [ -n "$ROLES_CSV" ]; then
  ROLES_JSON="$(printf '%s' "$ROLES_CSV" | jq -R -c 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')"
else
  ROLES_JSON="$(jq -c '([.screens[]? | .permissions // [] | .[]] + ["member", "guest"]) | unique' "$SCREEN_MANIFEST")"
fi

# --- fail-safe の除外理由を stderr へ ---
total_screens="$(jq '(.screens // []) | length' "$SCREEN_MANIFEST")"
perm_screens_count="$(jq '[.screens[]? | select(has("permissions"))] | length' "$SCREEN_MANIFEST")"
if [ "$perm_screens_count" -lt "$total_screens" ]; then
  echo "NOTE: permissions 未抽出の画面 $((total_screens - perm_screens_count)) 件は permission-matrix で permissions: null(権限未設定)として出力しました(fail-safe: 誤った全許可を出さない)" >&2
fi

if [ "$HAS_FEATURES" = true ]; then
  feat_with_apis="$(jq '[.units[]? | select(((.relatedApis // []) | length) > 0)] | length' "$FEATURE_MANIFEST")"
else
  feat_with_apis=0
fi
if [ "$feat_with_apis" -eq 0 ]; then
  if [ "$HAS_FEATURES" = true ]; then
    echo "NOTE: feature-manifest に relatedApis を持つ feature が 0 件のため permission-matrix の features は空配列です" >&2
  else
    echo "NOTE: feature-manifest 未指定のため permission-matrix の features は空配列です" >&2
  fi
fi

# --- 検査A: feature-manifest の集約キー(unitKey)重複検出 ---
# 機能一覧が空・未指定の場合は既存の安全機構(features: [])を壊さないためスキップする。
if [ "$HAS_FEATURES" = true ]; then
  feat_count="$(jq '(.units // []) | length' "$FEATURE_MANIFEST")"
  if [ "$feat_count" -gt 0 ]; then
    dup_unit_keys="$(jq -r '[.units[]?.unitKey] | group_by(.) | map(select(length > 1) | .[0]) | .[]' "$FEATURE_MANIFEST")"
    if [ -n "$dup_unit_keys" ]; then
      echo "ERROR: feature-manifest に重複する unitKey があります:" >&2
      printf '%s\n' "$dup_unit_keys" >&2
      exit 1
    fi
  fi
fi

# --- 検査B: 全APIの存在値検証 + CRUD/permission対象のmethod必須検査（出力作成前） ---
# 存在する method / targetTables の型・値域は unresolved を含む全 API units で検査する。
# method の欠落は、feature 指定時は解決済み relatedApis の参照先、未指定時は
# targetTables キーを明示した解決済み API だけを候補にする（欠落からCRUDを推測しない）。
validation_targets='($am[0].units // []) as $apis
  | ($fm[0].units // []) as $features
  | (if $hasFeatures
     then ([$features[]? | (.relatedApis // [])[]] | unique) as $relatedApis
          | [$apis[] | select(.kind != "unresolved" and (.unitKey as $unitKey | $relatedApis | index($unitKey) != null))]
     else [$apis[] | select(.kind != "unresolved" and has("targetTables"))]
     end)'
missing_method_apis="$(jq -n -r \
  --slurpfile am "$API_MANIFEST" --slurpfile fm "$FEATURE_MANIFEST_FILE" --argjson hasFeatures "$HAS_FEATURES" \
  "$validation_targets as \$targets
   | [\$targets[]
      | select((if \$hasFeatures then true else ((.targetTables | type) == \"array\" and (.targetTables | length) > 0) end))
      | select(has(\"method\") | not) | .unitKey] | unique | .[0:10][]")"
invalid_method_apis="$(jq -n -r \
  --slurpfile am "$API_MANIFEST" \
  '[($am[0].units // [])[] | select(has("method"))
     | select((.method | type) != "string" or (.method | test("^(GET|POST|PUT|PATCH|DELETE)$") | not))
     | .unitKey] | unique | .[0:10][]')"
invalid_target_tables_apis="$(jq -n -r \
  --slurpfile am "$API_MANIFEST" \
  '[($am[0].units // [])[] | select(has("targetTables"))
     | select(if (.targetTables | type) != "array"
              then true
              else any(.targetTables[]; type != "string" or (test("\\S") | not))
              end)
     | .unitKey] | unique | .[0:10][]')"
if [ -n "$missing_method_apis" ] || [ -n "$invalid_method_apis" ] || [ -n "$invalid_target_tables_apis" ]; then
  echo "ERROR: CRUD判定材料が不正または不足しています:" >&2
  if [ -n "$missing_method_apis" ]; then
    echo "  不足フィールド: method" >&2
    echo "  method を持たない API (最大10件):" >&2
    while IFS= read -r unit_key; do [ -n "$unit_key" ] && echo "  - $unit_key" >&2; done <<< "$missing_method_apis"
  fi
  if [ -n "$invalid_method_apis" ]; then
    echo "  不正フィールド: method" >&2
    echo "  method がHTTP動詞として不正な API (最大10件):" >&2
    while IFS= read -r unit_key; do [ -n "$unit_key" ] && echo "  - $unit_key" >&2; done <<< "$invalid_method_apis"
  fi
  if [ -n "$invalid_target_tables_apis" ]; then
    echo "  不正フィールド: targetTables" >&2
    echo "  targetTables が文字列配列でない API (最大10件):" >&2
    while IFS= read -r unit_key; do [ -n "$unit_key" ] && echo "  - $unit_key" >&2; done <<< "$invalid_target_tables_apis"
  fi
  exit 1
fi

# --- table-manifest 収載確認(advisory。出力は変えない) ---
if [ -n "$TABLE_MANIFEST" ]; then
  unknown_tables="$(jq -n -r \
    --slurpfile am "$API_MANIFEST" \
    --slurpfile tm "$TABLE_MANIFEST" \
    '(([$am[0].units[]? | .targetTables // [] | .[]] | unique) - [$tm[0].units[]? | .unitKey]) | join(", ")')"
  if [ -n "$unknown_tables" ]; then
    echo "WARN: apis の targetTables に table-manifest 未収載の unitKey があります: ${unknown_tables}" >&2
  fi
fi

# ---------------------------------------------------------------------------
# 共通 jq 定義(method → CRUD 文字・CRUD 正規順・ロールアクセス判定)
# ---------------------------------------------------------------------------
JQ_DEFS='
  def method_letter:
    ascii_upcase
    | if . == "POST" then "C"
      elif . == "GET" then "R"
      elif . == "PUT" or . == "PATCH" then "U"
      elif . == "DELETE" then "D"
      else "" end;
  def crud_str:
    . as $ls | ["C", "R", "U", "D"] | map(select(. as $x | ($ls | index($x)) != null)) | join("");
  def role_access($p; $r):
    (($p | length) == 0) or (($p | index($r)) != null);
'

# OUTPUT_DIR と同じ親にhidden siblingを作り、3成果物をまとめて公開する。
OUTPUT_PARENT="$(dirname "$OUTPUT_DIR")"
OUTPUT_NAME="$(basename "$OUTPUT_DIR")"
mkdir -p "$OUTPUT_PARENT"
STAGING_DIR="$(mktemp -d "$OUTPUT_PARENT/.${OUTPUT_NAME}.matrix-staging.XXXXXX")"
PUBLISH_COMPLETE=false
cleanup_matrix_transaction() {
  local exit_code=$?
  trap - EXIT
  set +e
  if [ "$PUBLISH_COMPLETE" != true ]; then
    rm -f -- "$OUTPUT_DIR/permission-matrix.json" "$OUTPUT_DIR/crud-matrix.json" "$OUTPUT_DIR/traceability.json"
  fi
  rm -rf "$STAGING_DIR"
  exit "$exit_code"
}
trap cleanup_matrix_transaction EXIT

# ---------------------------------------------------------------------------
# 1. permission-matrix.json
# ---------------------------------------------------------------------------
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --arg manifestContentHash "$MANIFEST_CONTENT_HASH" \
  --arg dataSource "$DS_PERMISSION" \
  --argjson roles "$ROLES_JSON" \
  --slurpfile screenManifest "$SCREEN_MANIFEST" \
  --slurpfile apiManifest "$API_MANIFEST" \
  --slurpfile featureManifest "$FEATURE_MANIFEST_FILE" \
  "$JQ_DEFS"'
  ($screenManifest[0].screens // []) as $allScreens
  | ([ $allScreens[] | select(has("permissions")) ]) as $screens
  | ($apiManifest[0].units // []) as $apis
  | ($featureManifest[0].units // []) as $features
  | ({
    generatedAt: $generatedAt,
    dataSource: $dataSource,
    roles: $roles,
    screens: [
      $allScreens[]
      | { screenId: .screenKey,
          screenName: .screenKey,
          route: (.route // ""),
          permissions: (if has("permissions")
                        then (.permissions as $p
                              | [ $roles[] | {key: ., value: role_access($p; .)} ] | from_entries)
                        else null end) }
    ],
    features: [
      $features[]
      | select(((.relatedApis // []) | length) > 0)
      | . as $f
      | ([ $f.relatedApis[] as $k
           | $apis[] | select(.unitKey == $k and .kind != "unresolved" and has("method"))
           | {unitKey: .unitKey, letter: (.method | method_letter)}
           | select(.letter != "") ]) as $fapis
      | { unitKey: $f.unitKey,
          crud: ([ $roles[] as $r
                   | { key: $r,
                       value: ([ $fapis[] as $fa
                                 | select(any($screens[];
                                     (((.relatedApis // []) | index($fa.unitKey)) != null)
                                     and role_access(.permissions; $r)))
                                 | $fa.letter ] | unique | crud_str) }
                 ] | from_entries) }
    ]
  } + (if ($manifestContentHash | length) > 0 then {manifestContentHash: $manifestContentHash} else {} end))' > "$STAGING_DIR/permission-matrix.json"

# ---------------------------------------------------------------------------
# 2. crud-matrix.json
# ---------------------------------------------------------------------------
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --arg manifestContentHash "$MANIFEST_CONTENT_HASH" \
  --arg dataSource "$DS_CRUD" \
  --slurpfile apiManifest "$API_MANIFEST" \
  --slurpfile featureManifest "$FEATURE_MANIFEST_FILE" \
  --slurpfile tableManifest "$TABLE_MANIFEST_FILE" \
  --argjson hasFeatures "$HAS_FEATURES" \
  --argjson hasTables "$HAS_TABLES" \
  "$JQ_DEFS"'
  ($apiManifest[0].units // []) as $apis
  | ($featureManifest[0].units // []) as $features
  | ($tableManifest[0].units // []) as $tableUnits
  | ([ $tableUnits[] | {key: .unitKey, value: (.identifier // .unitKey)} ] | from_entries) as $phys
  | (
      if $hasFeatures then
        [ $features[]
          | select(((.relatedApis // []) | length) > 0)
          | . as $f
          | ([ $f.relatedApis[] as $k
               | $apis[] | select(.unitKey == $k and .kind != "unresolved" and has("method") and has("targetTables")
                                  and (.targetTables | type == "array") and (.targetTables | length) > 0)
               | (.method | method_letter) as $l
               | select($l != "")
               | .targetTables[] as $t
               | {table: ($phys[$t] // $t), letter: $l} ]) as $cells
          | select(($cells | length) > 0)
          | { featureId: $f.unitKey,
              featureName: ($f.identifier // $f.unitKey),
              cells: ($cells | group_by(.table)
                      | map({key: .[0].table, value: ([.[].letter] | unique | crud_str)})
                      | from_entries) } ]
      else
        [ $apis[]
          | select(.kind != "unresolved" and has("method") and has("targetTables")
                   and (.targetTables | type == "array") and (.targetTables | length) > 0)
          | (.method | method_letter) as $l
          | select($l != "")
          | select((.targetTables | length) > 0)
          | { featureId: .unitKey,
              featureName: (.identifier // .unitKey),
              cells: ([.targetTables[] | {key: ($phys[.] // .), value: $l}] | from_entries) } ]
      end
    ) as $featureRows
  | { generatedAt: $generatedAt,
      dataSource: $dataSource,
      tables: (if $hasTables
               then [ $tableUnits[]
                      | {physicalName: (.identifier // .unitKey)}
                        + (if has("logicalName") then {logicalName: .logicalName} else {} end) ]
               else ([ $featureRows[].cells | keys[] ] | unique | map({physicalName: .}))
               end),
      features: $featureRows }
  + (if $hasFeatures then {} else {note: "feature-manifest未指定のためAPI単位で集約(featureIdはAPIのunitKey)"} end)
  + (if ($manifestContentHash | length) > 0 then {manifestContentHash: $manifestContentHash} else {} end)
  ' > "$STAGING_DIR/crud-matrix.json"

# ---------------------------------------------------------------------------
# 3. traceability.json
# ---------------------------------------------------------------------------
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --arg manifestContentHash "$MANIFEST_CONTENT_HASH" \
  --arg dataSource "$DS_TRACE" \
  --slurpfile screenManifest "$SCREEN_MANIFEST" \
  --slurpfile apiManifest "$API_MANIFEST" \
  --slurpfile tableManifest "$TABLE_MANIFEST_FILE" \
  --argjson hasTables "$HAS_TABLES" \
  '
  ($screenManifest[0].screens // []) as $screens
  | ($apiManifest[0].units // []) as $apis
  | ($tableManifest[0].units // []) as $tableUnits
  | ({ generatedAt: $generatedAt,
    dataSource: $dataSource,
    screens: [
      $screens[]
      | select(((.relatedApis // []) | length) > 0)
      | { screenId: .screenKey,
          screenName: .screenKey,
          route: (.route // ""),
          apis: .relatedApis }
        + (if ((.sourceHash // "") | length) > 0 then {sourceHash: .sourceHash} else {} end)
    ],
    apis: [
      $apis[]
      | { apiId: .unitKey,
          apiName: .unitKey,
          endpoint: (.identifier // .unitKey),
          tables: (.targetTables // []) }
    ],
    tables: (if $hasTables
             then [ $tableUnits[]
                    | {tableId: .unitKey, tableName: (.identifier // .unitKey)}
                      + (if has("logicalName") then {logicalName: .logicalName} else {} end) ]
             else ([ $apis[] | .targetTables // [] | .[] ] | unique | map({tableId: ., tableName: .}))
             end) }
    + (if ($manifestContentHash | length) > 0 then {manifestContentHash: $manifestContentHash} else {} end))
  ' > "$STAGING_DIR/traceability.json"

mkdir -p "$OUTPUT_DIR"
mv "$STAGING_DIR/permission-matrix.json" "$OUTPUT_DIR/permission-matrix.json"
mv "$STAGING_DIR/crud-matrix.json" "$OUTPUT_DIR/crud-matrix.json"
mv "$STAGING_DIR/traceability.json" "$OUTPUT_DIR/traceability.json"
echo "OK: wrote $OUTPUT_DIR/permission-matrix.json" >&2
echo "OK: wrote $OUTPUT_DIR/crud-matrix.json" >&2
echo "OK: wrote $OUTPUT_DIR/traceability.json" >&2
rm -rf "$STAGING_DIR"
PUBLISH_COMPLETE=true
trap - EXIT
