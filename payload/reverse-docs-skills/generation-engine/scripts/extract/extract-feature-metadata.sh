#!/usr/bin/env bash
# 抽出エンジン(generation-engine/scripts/extract): 機能種別マニフェストへのメタデータ抽出。
# 入力マニフェスト(unitKind=feature)の units[] を走査し、各ユニットの unitKey・identifier・
# unitNameGuess(存在するもののみ)からキーワード分類した operationClass を追加した拡張マニフェストを
# 出力する。既存フィールドは一切変更しない。他種別のようなソースコード走査は行わない
# (機能は既存一覧の派生グルーピングであり、判定材料は manifest 内の識別子文字列のみ)。
#
# Usage: extract-feature-metadata.sh <feature-manifest.json> <source-dir> <output.json>
#            [--screen-manifest <path>] [--table-manifest <path>]
# Legacy: extract-feature-metadata.sh <feature-manifest.json> <output.json>
#            [--screen-manifest <path>] [--table-manifest <path>] [--source-dir <path>]
#        extract-feature-metadata.sh --self-test
#
# 入出力契約:
#   入力: unitKind=feature のユニットマニフェスト(validate-manifest.sh PASS 済み想定)
#   出力: units[] 各要素へ operationClass を追加した拡張マニフェスト JSON。
#         スキーマ正本: delivery-payload/references/manifest-schema-extensions.md「features(機能・補足)」節
#           - operationClass: string 「照会」「登録」「更新」「削除」「承認」「その他」の6値
#         出力は validate-manifest.sh --unit-kind feature で検証可能。
#
# 検出ヒューリスティック(キーワード判定。判定対象は unitKey + identifier + unitNameGuess の連結文字列):
#   1. haystack を組み立てる: unitKey ' ' identifier ' ' unitNameGuess(存在する場合のみ)
#   2. 以下の優先順(先勝ち。複数カテゴリのキーワードが同時ヒットしても最初に一致したものを採用)で
#      キーワードを大小文字無視・部分一致で検索する:
#        照会: get/list/view/search/find/show/display/参照/照会/検索/表示
#        登録: create/add/new/register/insert/登録/追加/作成
#        更新: update/edit/modify/change/更新/編集/変更
#        削除: delete/remove/destroy/削除/除去
#        承認: approve/confirm/accept/reject/承認/確認
#   3. いずれにもヒットしなければ「その他」
#   operationClass は kind != "unresolved" の全行に必ず付与する(欠落なし。6値目「その他」が
#   キーワード不一致の受け皿となるため、他フィールドのような fail-safe 欠落は行わない)。
#
# 直接データアクセス経路(1-152・feature-detection.md Stage 3b): --screen-manifest・
# --table-manifest・--source-dir がすべて指定された場合のみ、relatedApis かつ relatedTables が
# 空配列の feature(kind!=unresolved)について、relatedScreens[] が指す画面の files[](空なら
# entryFile)を生SQLパターン(FROM\s+\w+|INSERT\s+INTO\s+\w+|UPDATE\s+\w+。大小文字無視)で走査し、
# ヒットしたテーブル名をテーブル一覧マニフェストの identifier/unitKey と照合して relatedTables に
# 記録する(既存の relatedApis/relatedTables が非空の feature は対象外。上書きしない)。
#
# emptyRelation 診断(1-152・detectionSummary.diagnostics.emptyRelation): 直接データアクセス経路の
# 適用後も relatedApis と relatedTables の両方が空配列のままの feature(kind="feature"。unresolved
# 除く)の比率を検出できなかった事実として記録する。
#   出力: count(両方空のfeature数)/total(kind="feature"の総数)/ratio/threshold(0.5固定)/warning。
#   --screen-manifest 等の指定有無によらず常に算出する(relatedApis/relatedTables は常に manifest に
#   存在するフィールドのため)。
#
# 出力 JSON は unit-list/validate-manifest.sh --unit-kind feature で検証可能であること
# (self-test 内で validate-manifest.sh も実行して PASS を確認する)。

set -euo pipefail

# キーワード分類(先勝ち)。ERE(拡張正規表現)で英語キーワードは大小文字無視、日本語キーワードは
# 部分一致。1行1カテゴリ、値は "カテゴリ名<TAB>ERE" とする。
CLASSIFY_RULES=$'照会\tget|list|view|search|find|show|display|参照|照会|検索|表示
登録\tcreate|add|new|register|insert|登録|追加|作成
更新\tupdate|edit|modify|change|更新|編集|変更
削除\tdelete|remove|destroy|削除|除去
承認\tapprove|confirm|accept|reject|承認|確認'

classify_haystack() {
  local haystack="$1" label ere
  while IFS=$'\t' read -r label ere; do
    [ -z "$label" ] && continue
    if printf '%s' "$haystack" | grep -EIiq -- "$ere"; then
      printf '%s' "$label"
      return 0
    fi
  done <<<"$CLASSIFY_RULES"
  printf 'その他'
}

# --- --self-test モード ---
# create-user/list-orders/update-profile/delete-order/approve-request/ping(無関係語)の
# 6ユニットで各カテゴリの判定値と、キーワード不一致ユニットが「その他」になること、
# 既存フィールド不変、validate-manifest.sh の PASS を検証する。
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-feature-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/features"
  for f in create-user list-orders update-profile delete-order approve-request ping-endpoint; do
    printf '// %s\n' "$f" > "$tmp/src/features/${f}.ts"
  done

  local manifest="$tmp/feature-manifest.json"
  jq -n --arg sourceDir "$tmp/src" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "feature",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 6, unresolvedCount: 0},
    units: [
      {unitKey: "create-user", kind: "feature", identifier: "create-user",
       unitNameGuess: "利用者登録", sourceFile: "features/create-user.ts", confidence: "high",
       relatedScreens: [], relatedApis: [], relatedTables: []},
      {unitKey: "list-orders", kind: "feature", identifier: "list-orders",
       unitNameGuess: "注文一覧照会", sourceFile: "features/list-orders.ts", confidence: "high",
       relatedScreens: [], relatedApis: [], relatedTables: []},
      {unitKey: "update-profile", kind: "feature", identifier: "update-profile",
       unitNameGuess: "プロフィール更新", sourceFile: "features/update-profile.ts", confidence: "high",
       relatedScreens: [], relatedApis: [], relatedTables: []},
      {unitKey: "delete-order", kind: "feature", identifier: "delete-order",
       unitNameGuess: "注文削除", sourceFile: "features/delete-order.ts", confidence: "high",
       relatedScreens: [], relatedApis: [], relatedTables: []},
      {unitKey: "approve-request", kind: "feature", identifier: "approve-request",
       unitNameGuess: "申請承認", sourceFile: "features/approve-request.ts", confidence: "high",
       relatedScreens: [], relatedApis: [], relatedTables: []},
      {unitKey: "ping-endpoint", kind: "feature", identifier: "ping-endpoint",
       unitNameGuess: "疎通テスト用ダミー", sourceFile: "features/ping-endpoint.ts", confidence: "high",
       relatedScreens: [], relatedApis: [], relatedTables: []}
    ]
  }' > "$manifest"

  local out="$tmp/out.json"
  if ! _gt_out1="$(bash "$script_path" "$manifest" "$tmp/src" "$out" 2>&1)"; then
    echo "  [FAIL] 実行: 抽出コマンド自体が失敗した" >&2
    printf '%s\n' "$_gt_out1" | sed 's/^/    /' >&2
    echo "self-test FAIL" >&2
    return 1
  fi

  check() {
    local label="$1" filter="$2"
    if _gt_out2="$(jq -e "$filter" "$out" 2>&1)"; then
      echo "  [PASS] $label"
    else
      echo "  [FAIL] $label" >&2
      printf '%s\n' "$_gt_out2" | sed 's/^/    /' >&2
      rc=1
    fi
  }

  check "登録: create-userがキーワード一致で分類される" \
    '.units[0].operationClass == "登録"'
  check "照会: list-ordersがキーワード一致で分類される" \
    '.units[1].operationClass == "照会"'
  check "更新: update-profileがキーワード一致で分類される" \
    '.units[2].operationClass == "更新"'
  check "削除: delete-orderがキーワード一致で分類される" \
    '.units[3].operationClass == "削除"'
  check "承認: approve-requestがキーワード一致で分類される" \
    '.units[4].operationClass == "承認"'
  check "その他: 該当キーワードなしのpingが「その他」に分類される" \
    '.units[5].operationClass == "その他"'

  # 1-152: 全6機能がrelatedApis/relatedTables空のフィクスチャで、全件空が無警告で通らないこと
  check "emptyRelation診断: count=6(全featureがrelatedApis/relatedTables空)" \
    '.detectionSummary.diagnostics.emptyRelation.count == 6'
  check "emptyRelation診断: total=6(kind=featureの総数)" \
    '.detectionSummary.diagnostics.emptyRelation.total == 6'
  check "emptyRelation診断: 全件空でwarning: true" \
    '.detectionSummary.diagnostics.emptyRelation.warning == true'

  # 既存フィールド不変: operationClass を取り除くと入力と完全一致する
  # (detectionSummary.diagnostics.emptyRelation は本スクリプトが新規に追加するため、
  #  ユニット単位の追加フィールドと同様に除去してから比較する)
  jq -S 'del(.units[].operationClass) | del(.detectionSummary.diagnostics)' "$out" > "$tmp/stripped.json"
  jq -S . "$manifest" > "$tmp/orig.json"
  if _gt_out3="$(diff -q "$tmp/stripped.json" "$tmp/orig.json" 2>&1)"; then
    echo "  [PASS] 既存フィールド不変: operationClass除去後は入力マニフェストと完全一致"
  else
    echo "  [FAIL] 既存フィールド不変: 入力マニフェストとの差分が発生した" >&2
    printf '%s\n' "$_gt_out3" | sed 's/^/    /' >&2
    rc=1
  fi

  if _gt_out4="$(bash "$script_dir/../unit-list/validate-manifest.sh" "$out" --unit-kind feature 2>&1)"; then
    echo "  [PASS] validate-manifest: 拡張マニフェストが全項目PASS"
  else
    echo "  [FAIL] validate-manifest: 拡張マニフェストが検証FAILした" >&2
    printf '%s\n' "$_gt_out4" | sed 's/^/    /' >&2
    rc=1
  fi

  local legacy_out="$tmp/legacy-out.json"
  if _gt_out5="$(bash "$script_path" "$manifest" "$legacy_out" >/dev/null 2>&1 \
     && jq -e '.detectionSummary.diagnostics.legacyArgumentOrder.used == true' "$legacy_out" 2>&1)"; then
    echo "  [PASS] 旧引数順互換: 使用したことが出力のdiagnosticsに記録される"
  else
    echo "  [FAIL] 旧引数順互換: diagnosticsへの記録が確認できなかった" >&2
    printf '%s\n' "$_gt_out5" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- 1-152: 直接データアクセス経路のフィクスチャ(画面が生SQLを直接埋め込み) ---
  mkdir -p "$tmp/direct/src/pages" "$tmp/direct/src/pages_norel"
  cat > "$tmp/direct/src/pages/widget_list.ts" <<'EOF'
export async function loadWidgets(db) {
  return db.query("SELECT id, name FROM widgets WHERE active = 1");
}
EOF
  cat > "$tmp/direct/src/pages_norel/other_view.ts" <<'EOF'
export function renderOther() {
  return null;
}
EOF

  local direct_screen_manifest="$tmp/direct/screen-manifest.json"
  jq -n --arg f "pages/widget_list.ts" --arg f2 "pages_norel/other_view.ts" '{
    generatedAt: "2026-01-01T00:00:00Z", sourceDir: "x", unitKind: "screen",
    strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
    detectionSummary: {screenCount: 2, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
    screens: [
      {screenKey: "widget-list-screen", kind: "route", route: "/widgets", entryFile: $f,
       screenNameGuess: "ウィジェット一覧", confidence: "high", files: [$f]},
      {screenKey: "other-screen", kind: "route", route: "/other", entryFile: $f2,
       screenNameGuess: "他画面", confidence: "high", files: [$f2]}
    ]
  }' > "$direct_screen_manifest"

  local direct_table_manifest="$tmp/direct/table-manifest.json"
  jq -n '{
    generatedAt: "2026-01-01T00:00:00Z", sourceDir: "x", unitKind: "table",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [
      {unitKey: "widgets-table", kind: "table", identifier: "widgets", sourceFile: "pages/widget_list.ts", confidence: "high"}
    ]
  }' > "$direct_table_manifest"

  local direct_feature_manifest="$tmp/direct/feature-manifest.json"
  jq -n '{
    generatedAt: "2026-01-01T00:00:00Z", sourceDir: "x", unitKind: "feature",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [
      {unitKey: "widget-management", kind: "feature", category: "在庫管理", identifier: "/widgets",
       unitNameGuess: "ウィジェット管理", summary: "ウィジェットを一覧表示する", sourceFile: "pages/widget_list.ts",
       relatedScreens: ["widget-list-screen"], relatedApis: [], relatedTables: [],
       confidence: "high", fileCount: 1, detectionMethod: "manual"}
    ]
  }' > "$direct_feature_manifest"

  local direct_out="$tmp/direct/out.json"
  if _gt_out6="$(bash "$script_path" "$direct_feature_manifest" "$tmp/direct/src" "$direct_out" \
       --screen-manifest "$direct_screen_manifest" --table-manifest "$direct_table_manifest" \
       >/dev/null 2>&1 \
     && jq -e '.units[0].relatedTables == ["widgets-table"]' "$direct_out" 2>&1)"; then
    echo "  [PASS] 直接データアクセス経路: 画面が直接持つ生SQLからrelatedTablesが紐付く"
  else
    echo "  [FAIL] 直接データアクセス経路: relatedTablesが期待通りに紐付かなかった" >&2
    printf '%s\n' "$_gt_out6" | sed 's/^/    /' >&2
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

USAGE="Usage: extract-feature-metadata.sh <feature-manifest.json> <source-dir> <output.json> [--screen-manifest <path>] [--table-manifest <path>] [--rules-file <json>]"
MANIFEST="${1:?$USAGE}"
LEGACY_ARGUMENT_ORDER="false"
if [ "$#" -ge 3 ] && [[ "${3:-}" != --* ]]; then
  SOURCE_DIR="${2:?$USAGE}"
  OUTPUT_JSON="${3:?$USAGE}"
  shift 3
else
  # 旧順序: <feature-manifest.json> <output.json> [--source-dir <path>]。
  # 第3位置引数がないため、正規順序と曖昧にならない。
  OUTPUT_JSON="${2:?$USAGE}"
  SOURCE_DIR=""
  LEGACY_ARGUMENT_ORDER="true"
  shift 2
fi

SCREEN_MANIFEST=""
TABLE_MANIFEST=""
EXTRACTION_RULES_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --screen-manifest) SCREEN_MANIFEST="${2:-}"; shift 2 ;;
    --table-manifest) TABLE_MANIFEST="${2:-}"; shift 2 ;;
    --source-dir)
      if [ "$LEGACY_ARGUMENT_ORDER" != "true" ]; then
        echo "ERROR: --source-dir is only accepted with the legacy two-position argument order" >&2
        echo "$USAGE" >&2
        exit 1
      fi
      SOURCE_DIR="${2:-}"
      shift 2
      ;;
    --rules-file) EXTRACTION_RULES_FILE="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
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
if ! jq empty "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: invalid JSON: $MANIFEST" >&2
  exit 1
fi
if [ "$LEGACY_ARGUMENT_ORDER" != "true" ] && [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: source-dir not found: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_JSON")"

# --- 非UTF-8原本の走査対応(改善課題1-131): detect-encoding.sh の走査ヘルパーを読み込む ---
_EXTRACT_FEATURE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../detect-encoding.sh
source "$_EXTRACT_FEATURE_SCRIPT_DIR/../detect-encoding.sh"
if ! SCAN_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/extract-feature-metadata-scan.XXXXXX" 2>/dev/null)" || [ -z "$SCAN_WORKDIR" ]; then
  echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi

if ! units_tmp="$(mktemp "${TMPDIR:-/tmp}/extract-feature-units.XXXXXX" 2>/dev/null)" || [ -z "$units_tmp" ]; then
  echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi
trap 'rm -f "$units_tmp"; rm -rf "$SCAN_WORKDIR"' EXIT

# --- 直接データアクセス経路(1-152・Stage 3b)の有効化判定 ---
DIRECT_ACCESS_ENABLED="false"
table_map=""
if [ -n "$SCREEN_MANIFEST" ] && [ -f "$SCREEN_MANIFEST" ] \
  && [ -n "$TABLE_MANIFEST" ] && [ -f "$TABLE_MANIFEST" ] \
  && [ -n "$SOURCE_DIR" ] && [ -d "$SOURCE_DIR" ]; then
  DIRECT_ACCESS_ENABLED="true"
  if ! table_map="$(mktemp "${TMPDIR:-/tmp}/extract-feature-table-map.XXXXXX" 2>/dev/null)" || [ -z "$table_map" ]; then
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  jq -r '.units[]? | select(.kind != "unresolved") | [(.identifier // ""), (.unitKey // "")] | @tsv' "$TABLE_MANIFEST" \
    | awk -F'\t' 'NF==2 && $1 != "" && $2 != ""' > "$table_map"
fi

# --- relatedScreens[] の画面が持つ files[](空なら entryFile)を1行1パスで返す ---
screen_files_for() {
  local screen_key="$1"
  jq -r --arg k "$screen_key" '
    (.screens // [])[] | select(.screenKey == $k) |
    if ((.files // []) | length) > 0 then .files[] else (.entryFile // empty) end
  ' "$SCREEN_MANIFEST" 2>/dev/null
}

# --- ファイル内の生SQL(FROM/INSERT INTO/UPDATE)からテーブル名だけを1行1件で返す ---
direct_sql_table_names() {
  local fpath="$1" scan_fpath
  # scan_fpath: 非UTF-8原本ならUTF-8一時コピー(改善課題1-131)。走査(grep)には常にscan_fpathを使う
  scan_fpath="$(to_utf8_for_scan "$fpath" "$SCAN_WORKDIR")"
  grep -Eio 'FROM[[:space:]]+[[:alnum:]_]+|INSERT[[:space:]]+INTO[[:space:]]+[[:alnum:]_]+|UPDATE[[:space:]]+[[:alnum:]_]+' "$scan_fpath" 2>/dev/null \
    | sed -E 's/^[Ff][Rr][Oo][Mm][[:space:]]+//; s/^[Ii][Nn][Ss][Ee][Rr][Tt][[:space:]]+[Ii][Nn][Tt][Oo][[:space:]]+//; s/^[Uu][Pp][Dd][Aa][Tt][Ee][[:space:]]+//'
}

while IFS= read -r row; do
  [ -z "$row" ] && continue
  kind="$(jq -r '.kind // ""' <<<"$row")"
  if [ "$kind" = "unresolved" ]; then
    printf '%s\n' "$row" >> "$units_tmp"
    continue
  fi

  unit_key="$(jq -r '.unitKey // ""' <<<"$row")"
  identifier="$(jq -r '.identifier // ""' <<<"$row")"
  name_guess="$(jq -r '.unitNameGuess // ""' <<<"$row")"
  haystack="${unit_key} ${identifier} ${name_guess}"

  class="$(classify_haystack "$haystack")"
  aug="$(jq --arg c "$class" '. + {operationClass: $c}' <<<"$row")"

  # --- Stage 3b: relatedApis/relatedTables が両方空のfeatureのみ、画面の直接アクセスを試みる ---
  if [ "$DIRECT_ACCESS_ENABLED" = "true" ]; then
    related_apis_empty="$(jq -r '((.relatedApis // []) | length) == 0' <<<"$aug")"
    related_tables_empty="$(jq -r '((.relatedTables // []) | length) == 0' <<<"$aug")"
    if [ "$related_apis_empty" = "true" ] && [ "$related_tables_empty" = "true" ]; then
      found_tables="[]"
      while IFS= read -r screen_key; do
        [ -z "$screen_key" ] && continue
        while IFS= read -r f; do
          [ -z "$f" ] && continue
          case "$f" in
            /*) fpath="$f" ;;
            *) fpath="${SOURCE_DIR%/}/$f" ;;
          esac
          [ -f "$fpath" ] || continue
          while IFS= read -r table_name; do
            [ -z "$table_name" ] && continue
            while IFS=$'\t' read -r m_id m_key; do
              [ -z "$m_id" ] && continue
              if [ "$(printf '%s' "$m_id" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$table_name" | tr '[:upper:]' '[:lower:]')" ]; then
                found_tables="$(jq --arg k "$m_key" 'if index($k) then . else . + [$k] end' <<<"$found_tables")"
              fi
            done < "$table_map"
          done < <(direct_sql_table_names "$fpath")
        done < <(screen_files_for "$screen_key")
      done < <(jq -r '.relatedScreens // [] | .[]' <<<"$aug")
      found_tables="$(jq 'unique' <<<"$found_tables")"
      if [ "$(jq 'length' <<<"$found_tables")" -gt 0 ]; then
        aug="$(jq --argjson t "$found_tables" '.relatedTables = $t' <<<"$aug")"
      fi
    fi
  fi

  printf '%s\n' "$aug" >> "$units_tmp"
done < <(jq -c '.units[]?' "$MANIFEST")

# --- emptyRelation(1-152): relatedApis/relatedTables が両方空のままのfeature比率(0件でも算出) ---
empty_relation_json="$(jq -sc '
  [.[] | select(.kind == "feature")] as $f
  | ($f | length) as $total
  | ($f | map(select(((.relatedApis // []) | length) == 0 and ((.relatedTables // []) | length) == 0)) | length) as $count
  | {count: $count, total: $total,
     ratio: (if $total > 0 then ($count / $total) else 0 end),
     threshold: 0.5,
     warning: (if $total > 0 then (($count / $total) > 0.5) else false end)}
' "$units_tmp")"

jq --slurpfile newunits "$units_tmp" --argjson er "$empty_relation_json" --argjson legacy_argument_order "$LEGACY_ARGUMENT_ORDER" '
  .units = $newunits
  | .detectionSummary.diagnostics = ((.detectionSummary.diagnostics // {}) + {emptyRelation: $er})
  | if $legacy_argument_order then
      .detectionSummary.diagnostics.legacyArgumentOrder = {
        used: true,
        message: "Legacy argument order was used; pass <feature-manifest.json> <source-dir> <output.json>."
      }
    else . end
' "$MANIFEST" > "$OUTPUT_JSON"

echo "OK: wrote $OUTPUT_JSON" >&2
bash "$_EXTRACT_FEATURE_SCRIPT_DIR/finalize-extension-manifest.sh" "$MANIFEST" "$OUTPUT_JSON" --rules-file "$EXTRACTION_RULES_FILE" --rule 'operationClass|unitKey と identifier と unitNameGuess の操作語' --rule 'relatedApis|関連画面の API パス' --rule 'relatedTables|画面構成ファイル内の SQL'
