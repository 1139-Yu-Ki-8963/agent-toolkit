#!/usr/bin/env bash
# 抽出エンジン(shared/scripts/extract): 機能種別マニフェストへのメタデータ抽出。
# 入力マニフェスト(unitKind=feature)の units[] を走査し、各ユニットの unitKey・identifier・
# unitNameGuess(存在するもののみ)からキーワード分類した operationClass を追加した拡張マニフェストを
# 出力する。既存フィールドは一切変更しない。他種別のようなソースコード走査は行わない
# (機能は既存一覧の派生グルーピングであり、判定材料は manifest 内の識別子文字列のみ)。
#
# Usage: extract-feature-metadata.sh <feature-manifest.json> <output.json>
#        extract-feature-metadata.sh --self-test
#
# 入出力契約:
#   入力: unitKind=feature のユニットマニフェスト(validate-manifest.sh PASS 済み想定)
#   出力: units[] 各要素へ operationClass を追加した拡張マニフェスト JSON。
#         スキーマ正本: shared/references/manifest-schema-extensions.md「features(機能・補足)」節
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
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-feature-self-test.XXXXXX")"
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
  if ! bash "$script_path" "$manifest" "$out" >/dev/null 2>&1; then
    echo "  [FAIL] 実行: 抽出コマンド自体が失敗した" >&2
    echo "self-test FAIL" >&2
    return 1
  fi

  check() {
    local label="$1" filter="$2"
    if jq -e "$filter" "$out" >/dev/null 2>&1; then
      echo "  [PASS] $label"
    else
      echo "  [FAIL] $label" >&2
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

  # 既存フィールド不変: operationClass を取り除くと入力と完全一致する
  jq -S 'del(.units[].operationClass)' "$out" > "$tmp/stripped.json"
  jq -S . "$manifest" > "$tmp/orig.json"
  if diff -q "$tmp/stripped.json" "$tmp/orig.json" >/dev/null 2>&1; then
    echo "  [PASS] 既存フィールド不変: operationClass除去後は入力マニフェストと完全一致"
  else
    echo "  [FAIL] 既存フィールド不変: 入力マニフェストとの差分が発生した" >&2
    rc=1
  fi

  if bash "$script_dir/../unit-list/validate-manifest.sh" "$out" --unit-kind feature >/dev/null 2>&1; then
    echo "  [PASS] validate-manifest: 拡張マニフェストが全項目PASS"
  else
    echo "  [FAIL] validate-manifest: 拡張マニフェストが検証FAILした" >&2
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

USAGE="Usage: extract-feature-metadata.sh <feature-manifest.json> <output.json>"
MANIFEST="${1:?$USAGE}"
OUTPUT_JSON="${2:?$USAGE}"

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

mkdir -p "$(dirname "$OUTPUT_JSON")"

units_tmp="$(mktemp "${TMPDIR:-/tmp}/extract-feature-units.XXXXXX")"
trap 'rm -f "$units_tmp"' EXIT

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

  printf '%s\n' "$aug" >> "$units_tmp"
done < <(jq -c '.units[]?' "$MANIFEST")

jq --slurpfile newunits "$units_tmp" '.units = $newunits' "$MANIFEST" > "$OUTPUT_JSON"

echo "OK: wrote $OUTPUT_JSON" >&2
