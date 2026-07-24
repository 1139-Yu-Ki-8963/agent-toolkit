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
# 導出規則(fail-safe: 根拠フィールドが欠落した要素は誤った権限・アクセスを出力せず、
#   理由を stderr へ出す):
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
#        method・targetTables のいずれかが欠落した API は行の根拠に含めない
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
       confidence: "high", permissions: ["admin"], relatedApis: ["users-list", "user-delete"], sourceHash: "abcdef123456"},
      {screenKey: "home", kind: "route", route: "/", entryFile: "screens/Home.tsx",
       confidence: "high", permissions: [], relatedApis: ["users-list"]},
      {screenKey: "legacy-report", kind: "route", route: "/legacy/report", entryFile: "screens/Home.tsx",
       confidence: "low"}
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
USAGE="Usage: build-matrix-data.sh <output-dir> --screen-manifest <path> --api-manifest <path> [--table-manifest <path>] [--feature-manifest <path>] [--roles <comma-separated>]"
OUTPUT_DIR="${1:?$USAGE}"
shift

SCREEN_MANIFEST=""
API_MANIFEST=""
TABLE_MANIFEST=""
FEATURE_MANIFEST=""
ROLES_CSV=""
while [ $# -gt 0 ]; do
  case "$1" in
    --screen-manifest)  SCREEN_MANIFEST="${2:-}";  shift 2 ;;
    --api-manifest)     API_MANIFEST="${2:-}";     shift 2 ;;
    --table-manifest)   TABLE_MANIFEST="${2:-}";   shift 2 ;;
    --feature-manifest) FEATURE_MANIFEST="${2:-}"; shift 2 ;;
    --roles)            ROLES_CSV="${2:-}";        shift 2 ;;
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

mkdir -p "$OUTPUT_DIR"

GENERATED_AT="$(date +%Y-%m-%dT%H:%M:%S%z | sed 's/\(..\)$/:\1/')"

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
DS_PERMISSION="$SCREEN_MANIFEST + $API_MANIFEST${FEATURE_MANIFEST:+ + $FEATURE_MANIFEST}"
DS_CRUD="$API_MANIFEST${FEATURE_MANIFEST:+ + $FEATURE_MANIFEST}${TABLE_MANIFEST:+ + $TABLE_MANIFEST}"
DS_TRACE="$SCREEN_MANIFEST + $API_MANIFEST${TABLE_MANIFEST:+ + $TABLE_MANIFEST}"

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

# ---------------------------------------------------------------------------
# 1. permission-matrix.json
# ---------------------------------------------------------------------------
jq -n \
  --arg generatedAt "$GENERATED_AT" \
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
  | {
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
           | $apis[] | select(.unitKey == $k and has("method"))
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
  }' > "$OUTPUT_DIR/permission-matrix.json"
echo "OK: wrote $OUTPUT_DIR/permission-matrix.json" >&2

# ---------------------------------------------------------------------------
# 2. crud-matrix.json
# ---------------------------------------------------------------------------
jq -n \
  --arg generatedAt "$GENERATED_AT" \
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
               | $apis[] | select(.unitKey == $k and has("method") and has("targetTables"))
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
          | select(has("method") and has("targetTables"))
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
  ' > "$OUTPUT_DIR/crud-matrix.json"
echo "OK: wrote $OUTPUT_DIR/crud-matrix.json" >&2

# ---------------------------------------------------------------------------
# 3. traceability.json
# ---------------------------------------------------------------------------
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --arg dataSource "$DS_TRACE" \
  --slurpfile screenManifest "$SCREEN_MANIFEST" \
  --slurpfile apiManifest "$API_MANIFEST" \
  --slurpfile tableManifest "$TABLE_MANIFEST_FILE" \
  --argjson hasTables "$HAS_TABLES" \
  '
  ($screenManifest[0].screens // []) as $screens
  | ($apiManifest[0].units // []) as $apis
  | ($tableManifest[0].units // []) as $tableUnits
  | { generatedAt: $generatedAt,
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
  ' > "$OUTPUT_DIR/traceability.json"
echo "OK: wrote $OUTPUT_DIR/traceability.json" >&2
