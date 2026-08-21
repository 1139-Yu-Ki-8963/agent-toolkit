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
# 入力契約: 各マニフェストは generation-engine/scripts/unit-list/validate-manifest.sh で PASS する
#   拡張済みマニフェスト(スキーマ正本: delivery-payload/references/manifest-schema-extensions.md)。
#   導出の根拠に使う任意フィールド:
#     screen-manifest:  screens[].permissions(confirmedPermissionsがあれば優先) / relatedApis / sourceHash
#     api-manifest:     units[].method / targetTables
#     feature-manifest: units[].relatedApis
#     table-manifest:   units[].unitKey(targetTables の収載確認のみ。出力には影響しない)
#
# 出力契約: <output-dir>/permission-matrix.json・crud-matrix.json・traceability.json の
#   3 ファイル(スキーマは manifest-schema-extensions.md「マトリクス・対応表用の新規データファイル
#   定義」に完全準拠。同スキーマは delivery-payload/templates/matrix/ の各テンプレート内 JS が
#   参照するトップレベルキー・フィールド名と一致させている。二重管理・ドリフト禁止)。
#
# 導出規則: method / targetTables が存在する場合の型・値域検査は全 API units に適用する。
#   欠落 method の必須判定では kind=unresolved を除外し、次の CRUD/permission 対象だけを検査する。
#   feature-manifest 指定時は解決済み relatedApis の method を必須とし、targetTables 欠落/[]は許容する。
#   未指定時は targetTables 明示APIだけを候補とし、非空ならmethod必須、[]ならmethod欠落を許容する。
#   method は5動詞の単値、または5動詞を / で連結した複数値（例: GET/POST）に限る。
#   複数値は各動詞へ展開して CRUD を合成する。判定材料が欠落・不正な API は全体を
#   停止せず3成果物から除外し、stderr へ全 unitKey と理由を列挙する。
#   targetTables は空白トリム後に非空の文字列配列に限る。
#   API以外の入力契約違反は、出力公開前に非ゼロ終了する。
#   1. permission-matrix.json
#      - roles: --roles 指定値。未指定なら全 screens の実効permissions(confirmedPermissions
#        優先・無ければpermissions)に現れるロール集合 + 暗黙ロール member/guest の和集合
#        (重複除去・アルファベット順で決定的)
#      - screens[]: 全画面を出力する。screenId/screenName は screenKey、route は
#        route(無ければ空文字)。permissions または confirmedPermissions を持つ画面は
#        {ロール: 真偽値} オブジェクト(confirmedPermissionsがあればpermissionsより優先。
#        空配列なら全ロール true、非空なら該当ロールを含む時のみ true)。どちらも
#        未抽出の画面は誤った全許可を出さないため permissions: null(権限未設定)として出力する
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

BUILD_MATRIX_DATA_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../output-layout.sh
source "$BUILD_MATRIX_DATA_SCRIPT_DIR/../output-layout.sh"

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
  local tmp rc=0 unknown=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-matrix-data-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  assert() {
    local desc="$1"
    shift
    local _gt_out1
    if _gt_out1="$("$@" 2>&1)"; then
      echo "  [PASS] $desc"
    else
      echo "  [FAIL] $desc" >&2
      printf '%s\n' "$_gt_out1" | sed 's/^/    /' >&2
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
    detectionSummary: {screenCount: 5, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
    screens: [
      {screenKey: "user-admin", kind: "route", route: "/admin/users", entryFile: "screens/UserAdmin.tsx",
       confidence: "high", screenType: "top", accountGroup: "admin", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false,
       permissions: ["admin"], relatedApis: ["users-list", "user-delete"], sourceHash: "abcdef123456",
       valueProvenance: {permissions: "measured"}},
      {screenKey: "home", kind: "route", route: "/", entryFile: "screens/Home.tsx",
       confidence: "high", screenType: "top", accountGroup: "user", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false,
       permissions: [], relatedApis: ["users-list"], valueProvenance: {permissions: "inferred"}},
      {screenKey: "legacy-report", kind: "route", route: "/legacy/report", entryFile: "screens/Home.tsx",
       confidence: "low", screenType: "detail", accountGroup: "report", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false},
      {screenKey: "confirmed-override", kind: "route", route: "/confirmed/override", entryFile: "screens/Home.tsx",
       confidence: "high", screenType: "detail", accountGroup: "user", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false,
       permissions: [], confirmedPermissions: ["admin"], valueProvenance: {permissions: "inferred"}},
      {screenKey: "confirmed-only", kind: "route", route: "/confirmed/only", entryFile: "screens/Home.tsx",
       confidence: "high", screenType: "detail", accountGroup: "user", accountSubType: "common", hasTemplate: true, parentScreen: null, childComponents: [], isProcessingEndpoint: false,
       confirmedPermissions: ["admin"]}
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
    jq -e '.screens | length == 5' "$pm"
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
  assert "1-170: valueProvenance.permissionsがscreen-manifestからpermission-matrixへ中継される" \
    jq -e '(.screens[] | select(.screenId == "user-admin") | .valueProvenance.permissions) == "measured"
           and (.screens[] | select(.screenId == "home") | .valueProvenance.permissions) == "inferred"
           and (.screens[] | select(.screenId == "legacy-report") | has("valueProvenance") | not)' "$pm"
  assert "1-170: confirmedPermissionsが未確定のpermissions([])より優先される(admin限定に上書き)" \
    jq -e '(.screens[] | select(.screenId == "confirmed-override") | .permissions)
           == {"admin": true, "guest": false, "member": false}' "$pm"
  assert "1-170: permissionsが欠落してもconfirmedPermissionsだけでnullにならず権限判定が成立する" \
    jq -e '(.screens[] | select(.screenId == "confirmed-only") | .permissions)
           == {"admin": true, "guest": false, "member": false}' "$pm"

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
  assert "ケースe: method欠落APIを除外して生成コマンドが成功" \
    bash -c "[ $nomethod_rc -eq 0 ]"
  assert "ケースe: stderrに除外理由と全unitKeyが出力される" \
    bash -c "grep -q '不足フィールド: method' '$nomethod_stderr' && grep -q 'users-list' '$nomethod_stderr'"
  assert "ケースe: 除外しても3成果物を生成しtraceabilityから外す" \
    bash -c "[ -f '$out_nomethod/permission-matrix.json' ] && [ -f '$out_nomethod/crud-matrix.json' ] && jq -e '.apis == []' '$out_nomethod/traceability.json' >/dev/null"

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

  # --- ケースg: feature参照APIのmethod欠落は除外（targetTables欠落は許容） ---
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
  assert "ケースg: method/targetTables両欠落のfeature参照APIは成功" \
    bash -c "[ $missing_both_rc -eq 0 ]"
  assert "ケースg: stderrに不足フィールド(method)だけが全件列挙される" \
    bash -c "grep -q '不足フィールド: method' '$missing_both_stderr' && ! grep -q '不足フィールド: targetTables' '$missing_both_stderr'"
  assert "ケースg: 除外しても3成果物を生成する" \
    bash -c "[ -f '$out_missing_both/permission-matrix.json' ] && [ -f '$out_missing_both/crud-matrix.json' ] && [ -f '$out_missing_both/traceability.json' ]"

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

  # --- 改善課題1-85: 全必須軸が0件の3データも、未生成と区別して公開・報告する ---
  local sm_zero="$tmp/screen-manifest-zero.json" am_zero="$tmp/api-manifest-zero.json"
  local fm_zero="$tmp/feature-manifest-zero.json" out_zero="$tmp/out-zero" zero_stderr="$tmp/zero-stderr.log" zero_rc=0
  jq -n '{screens: []}' > "$sm_zero"
  jq -n '{units: []}' > "$am_zero"
  jq -n '{units: []}' > "$fm_zero"
  bash "$script_path" "$out_zero" --screen-manifest "$sm_zero" --api-manifest "$am_zero" \
    --feature-manifest "$fm_zero" --roles , > /dev/null 2>"$zero_stderr" || zero_rc=$?
  if [ "$zero_rc" -eq 0 ] \
    && [ -f "$out_zero/permission-matrix.json" ] \
    && [ -f "$out_zero/crud-matrix.json" ] \
    && [ -f "$out_zero/traceability.json" ]; then
    echo "  [PASS] 改善課題1-85: 全必須軸0件でも3データJSONを出力する"
  else
    echo "  [FAIL] 改善課題1-85: 全必須軸0件の3データJSONを出力できない" >&2
    rc=1
  fi
  assert "改善課題1-85: 0件データの各JSON名と全軸の0件数をINFOで出力する" \
    bash -c "[ -f '$out_zero/permission-matrix.json' ] && [ -f '$out_zero/crud-matrix.json' ] && [ -f '$out_zero/traceability.json' ] && grep -Fq 'INFO: zero-row matrix data: $out_zero/permission-matrix.json (roles=0, screens=0)' '$zero_stderr' && grep -Fq 'INFO: zero-row matrix data: $out_zero/crud-matrix.json (tables=0, features=0)' '$zero_stderr' && grep -Fq 'INFO: zero-row matrix data: $out_zero/traceability.json (screens=0, apis=0, tables=0)' '$zero_stderr'"

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

  # --- ケースj: featureなしでtargetTables非空かつmethod欠落は除外 ---
  local out_nomethod_no_feature="$tmp/out-nomethod-no-feature" nomethod_no_feature_stderr="$tmp/nomethod-no-feature-stderr.log" nomethod_no_feature_rc=0
  bash "$script_path" "$out_nomethod_no_feature" --screen-manifest "$sm" --api-manifest "$am_nomethod" \
    >/dev/null 2>"$nomethod_no_feature_stderr" || nomethod_no_feature_rc=$?
  assert "ケースj: featureなしのtargetTables非空かつmethod欠落も成功" \
    bash -c "[ $nomethod_no_feature_rc -eq 0 ]"
  assert "ケースj: method不足を報告し3成果物から除外する" \
    bash -c "grep -q '不足フィールド: method' '$nomethod_no_feature_stderr' && [ -f '$out_nomethod_no_feature/permission-matrix.json' ] && [ -f '$out_nomethod_no_feature/crud-matrix.json' ] && jq -e '.apis == []' '$out_nomethod_no_feature/traceability.json' >/dev/null"

  # --- ケースk: methodの値域違反は該当APIだけを除外 ---
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
    assert "ケースk-$method_case: 不正methodを除外して生成し、理由を出力する" \
      bash -c "[ $method_rc -eq 0 ] && grep -q '不正フィールド: method' '$method_stderr' && [ -f '$method_out/permission-matrix.json' ] && [ -f '$method_out/crud-matrix.json' ] && jq -e '[.apis[].apiId] == [\"user-delete\"]' '$method_out/traceability.json' >/dev/null"
  done

  # --- ケースl: targetTablesの型・要素違反は該当APIだけを除外 ---
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
    assert "ケースl-$tables_case: 不正targetTablesを除外して生成し、理由を出力する" \
      bash -c "[ $tables_rc -eq 0 ] && grep -q '不正フィールド: targetTables' '$tables_stderr' && [ -f '$tables_out/permission-matrix.json' ] && [ -f '$tables_out/crud-matrix.json' ] && jq -e '[.apis[].apiId] == [\"user-delete\"]' '$tables_out/traceability.json' >/dev/null"
  done

  # --- ケースm: 複数methodをCRUDへ展開して合成 ---
  local am_multiple_methods="$tmp/api-manifest-multiple-methods.json" out_multiple_methods="$tmp/out-multiple-methods" multiple_methods_stderr="$tmp/multiple-methods-stderr.log" multiple_methods_rc=0
  jq '.units[0].method = "GET/POST"' "$am" > "$am_multiple_methods"
  bash "$script_path" "$out_multiple_methods" --screen-manifest "$sm" --api-manifest "$am_multiple_methods" \
    >/dev/null 2>"$multiple_methods_stderr" || multiple_methods_rc=$?
  assert "ケースm: GET/POSTを持つAPIでも生成コマンドが成功" \
    bash -c "[ $multiple_methods_rc -eq 0 ] && [ -f '$out_multiple_methods/permission-matrix.json' ] && [ -f '$out_multiple_methods/crud-matrix.json' ] && [ -f '$out_multiple_methods/traceability.json' ]"
  assert "ケースm: 複数methodのCRUD展開がstderrとデータへ残る" \
    bash -c "grep -q '複数methodの API は各動詞を CRUD へ展開して合成' '$multiple_methods_stderr' && grep -q 'users-list: GET/POST' '$multiple_methods_stderr' && jq -e '[.features[].cells | .users] | index(\"CR\") != null' '$out_multiple_methods/crud-matrix.json' >/dev/null"

  # --- ケースn: 同梱API一覧をfeatureなしで導出できる ---
  local repo_root sample_api sample_screen sample_out
  repo_root="$(cd "$script_dir/../../.." && pwd)"
  local layout_json screen_manifest_ext_rel api_list_html_rel
  layout_json="$(resolve_output_layout "$repo_root/generation-engine/samples")" || return 1
  screen_manifest_ext_rel="$(output_layout_get "$layout_json" screenManifestExt)" || return 1
  api_list_html_rel="$(output_layout_get "$layout_json" unitListHtml API)" || return 1
  sample_api="$tmp/sample-api-manifest.json"
  sample_screen="$repo_root/generation-engine/samples/$screen_manifest_ext_rel"
  sample_out="$tmp/out-sample"
  local api_list_html_abs="$repo_root/generation-engine/samples/$api_list_html_rel"
  if [ -f "$api_list_html_abs" ]; then
    awk '/^[[:space:]]*<script[^>]*id="unit-manifest"/{inside=1; next} inside && /<\/script>/{exit} inside{print}' \
      "$api_list_html_abs" > "$sample_api"
    assert "ケースm: 同梱API一覧JSONを抽出できる" jq empty "$sample_api"
    assert "ケースm: 同梱サンプルをfeatureなしで導出できる" \
      bash "$script_path" "$sample_out" --screen-manifest "$sample_screen" --api-manifest "$sample_api"
    assert "ケースm: 同梱サンプルで3成果物を生成する" \
      bash -c "[ -f '$sample_out/permission-matrix.json' ] && [ -f '$sample_out/crud-matrix.json' ] && [ -f '$sample_out/traceability.json' ]"
  else
    # generation-engine/samples/project-portal/一覧 配下がまだ旧配置(日本語)のままで、
    # output-layout.jsonの既定値(project-portal/lists、英字)と食い違っているため、
    # 解決先パスに同梱サンプルが実在しない(1-29で指摘済みの構造的な不一致。この
    # スクリプト単体の担当範囲を超えるため、samples側の再配置は行わない)。
    echo "  [UNKNOWN] ケースm/n: 同梱API一覧フィクスチャが解決先パス($api_list_html_rel)に実在しないため判定できません(generation-engine/samples/project-portal/一覧 配下が旧配置のまま。output-layout.jsonの既定値との不一致)" >&2
    unknown=1
  fi

  # --- ケースo: feature参照先がunresolvedならpermission/crudへ混入させない ---
  local sm_unresolved="$tmp/screen-manifest-unresolved.json" am_unresolved="$tmp/api-manifest-unresolved.json"
  local fm_unresolved="$tmp/feature-manifest-unresolved.json" out_unresolved="$tmp/out-unresolved"
  jq -n '{screens:[{screenKey:"ghost-screen",route:"/ghost",permissions:[],relatedApis:["ghost-api"]}]}' > "$sm_unresolved"
  jq -n '{units:[{unitKey:"ghost-api",kind:"unresolved",identifier:"GET /ghost",method:"GET",targetTables:["users"]}]}' > "$am_unresolved"
  jq -n '{units:[{unitKey:"ghost-feature",kind:"feature",identifier:"ghost-feature",relatedApis:["ghost-api"]}]}' > "$fm_unresolved"
  assert "ケースn: unresolved API参照でも生成コマンドが成功" \
    bash "$script_path" "$out_unresolved" --screen-manifest "$sm_unresolved" --api-manifest "$am_unresolved" --feature-manifest "$fm_unresolved"
  assert "ケースn: unresolved APIはpermission CRUD文字とcrud行へ混入しない" \
    bash -c "jq -e '.features == [{\"unitKey\":\"ghost-feature\",\"crud\":{\"guest\":\"\",\"member\":\"\"}}]' '$out_unresolved/permission-matrix.json' >/dev/null && jq -e '.features == []' '$out_unresolved/crud-matrix.json' >/dev/null"

  # --- ケースp: 除外時は旧3成果物を置換し、無関係ファイルを保持 ---
  local out_stale="$tmp/out-stale" stale_stderr="$tmp/stale-stderr.log" stale_rc=0
  mkdir -p "$out_stale"
  printf '%s\n' old > "$out_stale/permission-matrix.json"
  printf '%s\n' old > "$out_stale/crud-matrix.json"
  printf '%s\n' old > "$out_stale/traceability.json"
  printf '%s\n' keep > "$out_stale/keep.txt"
  bash "$script_path" "$out_stale" --screen-manifest "$sm" --api-manifest "$am_nomethod" \
    >/dev/null 2>"$stale_stderr" || stale_rc=$?
  assert "ケースp: method不足入力は除外してexit 0" bash -c "[ $stale_rc -eq 0 ]"
  assert "ケースp: 3成果物を置換し、無関係keep.txtは残る" \
    bash -c "[ -f '$out_stale/permission-matrix.json' ] && [ -f '$out_stale/crud-matrix.json' ] && [ -f '$out_stale/traceability.json' ] && [ -f '$out_stale/keep.txt' ]"

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

  # --- ケースq/r: unresolvedでも不正targetTablesは該当APIだけを除外する ---
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
    assert "ケース$unresolved_tables_case: unresolvedの不正targetTablesを除外してunitKeyを出力する" \
      bash -c "[ $unresolved_tables_rc -eq 0 ] && grep -q '不正フィールド: targetTables' '$unresolved_tables_stderr' && grep -q 'unresolved-invalid-tables' '$unresolved_tables_stderr' && [ -f '$unresolved_tables_out/permission-matrix.json' ] && [ -f '$unresolved_tables_out/crud-matrix.json' ] && jq -e '.apis == []' '$unresolved_tables_out/traceability.json' >/dev/null"
  done

  # --- ケースs: 生成済み機能一覧→matrix→permission-function連結 ---
  local feature_list_html_rel
  feature_list_html_rel="$(output_layout_get "$layout_json" unitListHtml 機能)" || return 1
  local feature_html="$repo_root/generation-engine/samples/$feature_list_html_rel"
  local api_manifest_ext_rel
  api_manifest_ext_rel="$(output_layout_get "$layout_json" apiManifestExt)" || return 1
  local screen_sample="$repo_root/generation-engine/samples/$screen_manifest_ext_rel"
  local feature_sample="$tmp/feature-manifest-sample.json"
  local api_sample="$tmp/api-manifest-sample.json"
  if [ -f "$feature_html" ]; then
    awk '/^[[:space:]]*<script[^>]*id="unit-manifest"/{inside=1; next} inside && /<\/script>/{exit} inside{print}' \
      "$feature_html" > "$feature_sample"
    # API だけは一覧の HTML ではなく拡張版のファイルから読む。一覧の HTML に埋め込まれた
    # API のデータは基本版であり method の欄を持たないが、このスクリプトは作成・参照・更新・
    # 削除の判定に method を必須とするため、一覧から読むと入口で止まる（2026-08-19 実測。
    # 一覧版は 141 件すべてが method を持たない）。unitKey の集合は一覧版と拡張版で一致する
    # ため、feature の relatedApis の対応を確かめる目的には影響しない。一覧へ戻さないこと。
    cp "$repo_root/generation-engine/samples/$api_manifest_ext_rel" "$api_sample"
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
  else
    # generation-engine/samples/project-portal/一覧 配下がまだ旧配置(日本語)のままで、
    # output-layout.jsonの既定値(project-portal/lists、英字)と食い違っているため、
    # 解決先パスに同梱サンプルが実在しない(1-29で指摘済みの構造的な不一致。この
    # スクリプト単体の担当範囲を超えるため、samples側の再配置は行わない)。
    echo "  [UNKNOWN] ケースs: 同梱機能一覧フィクスチャが解決先パス($feature_list_html_rel)に実在しないため判定できません(generation-engine/samples/project-portal/一覧 配下が旧配置のまま。output-layout.jsonの既定値との不一致)" >&2
    unknown=1
  fi

  if [ "$rc" -ne 0 ]; then
    echo "self-test FAIL" >&2
  elif [ "$unknown" -ne 0 ]; then
    echo "self-test UNKNOWN" >&2
    return 2
  else
    echo "self-test 全項目 PASS"
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
# 各 jq 呼び出しで --slurpfile によりファイルから直接読ませる）。
# 引数長の上限はOSに依存する(extract-table-metadata.sh の同種対策と同じ理由)。
# 手元の環境で上限に達しないからといって、シェル変数への代入(--argjson直渡し)へ戻すな。
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
  ROLES_JSON="$(jq -c '([.screens[]? | ((.confirmedPermissions // .permissions) // []) | .[]] + ["member", "guest"]) | unique' "$SCREEN_MANIFEST")"
fi

# --- fail-safe の除外理由を stderr へ ---
total_screens="$(jq '(.screens // []) | length' "$SCREEN_MANIFEST")"
perm_screens_count="$(jq '[.screens[]? | select(has("permissions") or has("confirmedPermissions"))] | length' "$SCREEN_MANIFEST")"
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
      | select(has(\"method\") | not) | .unitKey] | unique | .[]")"
invalid_method_apis="$(jq -n -r \
  --slurpfile am "$API_MANIFEST" \
  '[($am[0].units // [])[] | select(has("method"))
     | select((.method | type) != "string" or (.method | test("^(GET|POST|PUT|PATCH|DELETE)(/(GET|POST|PUT|PATCH|DELETE))*$") | not))
     | .unitKey] | unique | .[]')"
invalid_target_tables_apis="$(jq -n -r \
  --slurpfile am "$API_MANIFEST" \
  '[($am[0].units // [])[] | select(has("targetTables"))
     | select(if (.targetTables | type) != "array"
              then true
              else any(.targetTables[]; type != "string" or (test("\\S") | not))
              end)
     | .unitKey] | unique | .[]')"
skipped_api_keys_json="$(printf '%s\n%s\n%s\n' "$missing_method_apis" "$invalid_method_apis" "$invalid_target_tables_apis" \
  | jq -R -s 'split("\n") | map(select(length > 0)) | unique')"
skipped_api_count="$(jq 'length' <<<"$skipped_api_keys_json")"
# 除外API一覧はAPI件数に比例して伸びうる可変長の値のため、コマンドライン引数
# ではなく一時ファイル経由(--slurpfile)でjqへ渡す（改善課題1-52）。
if ! SKIPPED_API_KEYS_FILE="$(mktemp "${TMPDIR:-/tmp}/skipped-api-keys.XXXXXX")" || [ -z "$SKIPPED_API_KEYS_FILE" ]; then
  echo "FATAL: 一時ファイルの作成に失敗しました(mktemp)" >&2
  exit 1
fi
printf '%s' "$skipped_api_keys_json" > "$SKIPPED_API_KEYS_FILE"
if [ "$skipped_api_count" -gt 0 ]; then
  echo "WARN: CRUD判定材料が不正または不足の API ${skipped_api_count}件を除外して生成を続行します:" >&2
  if [ -n "$missing_method_apis" ]; then
    echo "  不足フィールド: method を持たない API:" >&2
    while IFS= read -r unit_key; do [ -n "$unit_key" ] && echo "  - $unit_key" >&2; done <<< "$missing_method_apis"
  fi
  if [ -n "$invalid_method_apis" ]; then
    echo "  不正フィールド: method がスキーマのHTTP動詞形式でない API:" >&2
    while IFS= read -r unit_key; do [ -n "$unit_key" ] && echo "  - $unit_key" >&2; done <<< "$invalid_method_apis"
  fi
  if [ -n "$invalid_target_tables_apis" ]; then
    echo "  不正フィールド: targetTables が文字列配列でない API:" >&2
    while IFS= read -r unit_key; do [ -n "$unit_key" ] && echo "  - $unit_key" >&2; done <<< "$invalid_target_tables_apis"
  fi
fi
multi_method_apis="$(jq -r \
  '[.units[]? | select((.method | type) == "string" and (.method | test("^(GET|POST|PUT|PATCH|DELETE)/(GET|POST|PUT|PATCH|DELETE)(/(GET|POST|PUT|PATCH|DELETE))*$")))
    | "\(.unitKey): \(.method)"] | .[]' "$API_MANIFEST")"
if [ -n "$multi_method_apis" ]; then
  echo "INFO: 複数methodの API は各動詞を CRUD へ展開して合成します:" >&2
  while IFS= read -r api; do [ -n "$api" ] && echo "  - $api" >&2; done <<< "$multi_method_apis"
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
  def method_letters:
    split("/") | map(method_letter) | map(select(. != "")) | unique;
  def is_skipped($keys):
    .unitKey as $key | ($keys | index($key)) != null;
  def crud_str:
    . as $ls | ["C", "R", "U", "D"] | map(select(. as $x | ($ls | index($x)) != null)) | join("");
  def role_access($p; $r):
    (($p | length) == 0) or (($p | index($r)) != null);
  def effective_permissions:
    (.confirmedPermissions // .permissions);
'

# OUTPUT_DIR と同じ親にhidden siblingを作り、3成果物をまとめて公開する。
# 3ファイルをOUTPUT_DIRへ直接ずつ書き出すと、途中で失敗した場合に一部だけ更新された
# 不整合な状態が残る。staging先で全件作ってから完了(PUBLISH_COMPLETE)後にのみ確定させ、
# 失敗時はtrap(cleanup_matrix_transaction)で未確定分を削除する。
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
  rm -f -- "$SKIPPED_API_KEYS_FILE"
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
  --slurpfile skippedApiKeys "$SKIPPED_API_KEYS_FILE" \
  --slurpfile screenManifest "$SCREEN_MANIFEST" \
  --slurpfile apiManifest "$API_MANIFEST" \
  --slurpfile featureManifest "$FEATURE_MANIFEST_FILE" \
  "$JQ_DEFS"'
  ($screenManifest[0].screens // []) as $allScreens
  | ([ $allScreens[] | select(has("permissions") or has("confirmedPermissions")) ]) as $screens
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
          permissions: (if (has("permissions") or has("confirmedPermissions"))
                        then (effective_permissions as $p
                              | [ $roles[] | {key: ., value: role_access($p; .)} ] | from_entries)
                        else null end) }
          + (if (.valueProvenance.permissions // "" ) != ""
             then {valueProvenance: {permissions: .valueProvenance.permissions}}
             else {} end)
    ],
    features: [
      $features[]
      | select(((.relatedApis // []) | length) > 0)
      | . as $f
      | ([ $f.relatedApis[] as $k
           | $apis[] | select(.unitKey == $k and .kind != "unresolved" and has("method") and (is_skipped($skippedApiKeys[0]) | not))
           | {unitKey: .unitKey, letters: (.method | method_letters)}
           | select((.letters | length) > 0) ]) as $fapis
      | { unitKey: $f.unitKey,
          crud: ([ $roles[] as $r
                   | { key: $r,
                       value: ([ $fapis[] as $fa
                                 | select(any($screens[];
                                     (((.relatedApis // []) | index($fa.unitKey)) != null)
                                     and role_access(effective_permissions; $r)))
                                 | $fa.letters[] ] | unique | crud_str) }
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
  --slurpfile skippedApiKeys "$SKIPPED_API_KEYS_FILE" \
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
               | $apis[] | select(.unitKey == $k and .kind != "unresolved" and has("method") and has("targetTables") and (is_skipped($skippedApiKeys[0]) | not)
                                  and (.targetTables | type == "array") and (.targetTables | length) > 0)
               | (.method | method_letters[]) as $l
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
          | select(.kind != "unresolved" and has("method") and has("targetTables") and (is_skipped($skippedApiKeys[0]) | not)
                   and (.targetTables | type == "array") and (.targetTables | length) > 0)
          | [(.method | method_letters[]) as $l
             | .targetTables[] | {key: ($phys[.] // .), value: $l}] as $cells
          | select(($cells | length) > 0)
          | { featureId: .unitKey,
              featureName: (.identifier // .unitKey),
              cells: ($cells | group_by(.key)
                      | map({key: .[0].key, value: ([.[].value] | unique | crud_str)})
                      | from_entries) } ]
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
  --slurpfile skippedApiKeys "$SKIPPED_API_KEYS_FILE" \
  "$JQ_DEFS"'
  ($screenManifest[0].screens // []) as $screens
  | ($apiManifest[0].units // []) as $apis
  | ($tableManifest[0].units // []) as $tableUnits
  | ([$apis[] | select(is_skipped($skippedApiKeys[0]) | not) | .unitKey]) as $includedApiKeys
  | ({ generatedAt: $generatedAt,
    dataSource: $dataSource,
    screens: [
      $screens[]
      | select(((.relatedApis // []) | length) > 0)
      | { screenId: .screenKey,
          screenName: .screenKey,
          route: (.route // ""),
          apis: [(.relatedApis // [])[] | select(. as $key | ($includedApiKeys | index($key)) != null)] }
        + (if ((.sourceHash // "") | length) > 0 then {sourceHash: .sourceHash} else {} end)
    ],
    apis: [
      $apis[] | select(is_skipped($skippedApiKeys[0]) | not)
      | { apiId: .unitKey,
          apiName: .unitKey,
          endpoint: (.identifier // .unitKey),
          tables: (.targetTables // []) }
    ],
    tables: (if $hasTables
             then [ $tableUnits[]
                    | {tableId: .unitKey, tableName: (.identifier // .unitKey)}
                      + (if has("logicalName") then {logicalName: .logicalName} else {} end) ]
             else ([ $apis[] | select(is_skipped($skippedApiKeys[0]) | not) | .targetTables // [] | .[] ] | unique | map({tableId: ., tableName: .}))
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

# 3成果物を公開した後で、ページ生成側が「0件データ」と「未生成」を区別できるよう
# 全必須軸が0件のJSONだけを明示的に報告する。一部軸だけが0件の通常データは報告しない。
permission_roles_count="$(jq '.roles | length' "$OUTPUT_DIR/permission-matrix.json")"
permission_screens_count="$(jq '.screens | length' "$OUTPUT_DIR/permission-matrix.json")"
if [ "$permission_roles_count" -eq 0 ] && [ "$permission_screens_count" -eq 0 ]; then
  echo "INFO: zero-row matrix data: $OUTPUT_DIR/permission-matrix.json (roles=0, screens=0)" >&2
fi
crud_tables_count="$(jq '.tables | length' "$OUTPUT_DIR/crud-matrix.json")"
crud_features_count="$(jq '.features | length' "$OUTPUT_DIR/crud-matrix.json")"
if [ "$crud_tables_count" -eq 0 ] && [ "$crud_features_count" -eq 0 ]; then
  echo "INFO: zero-row matrix data: $OUTPUT_DIR/crud-matrix.json (tables=0, features=0)" >&2
fi
traceability_screens_count="$(jq '.screens | length' "$OUTPUT_DIR/traceability.json")"
traceability_apis_count="$(jq '.apis | length' "$OUTPUT_DIR/traceability.json")"
traceability_tables_count="$(jq '.tables | length' "$OUTPUT_DIR/traceability.json")"
if [ "$traceability_screens_count" -eq 0 ] && [ "$traceability_apis_count" -eq 0 ] && [ "$traceability_tables_count" -eq 0 ]; then
  echo "INFO: zero-row matrix data: $OUTPUT_DIR/traceability.json (screens=0, apis=0, tables=0)" >&2
fi
rm -rf "$STAGING_DIR"
PUBLISH_COMPLETE=true
trap - EXIT
