#!/usr/bin/env bash
# finalize-extension-manifest.sh — 拡張抽出の充足状況を共通で記録する。
#
# Usage: finalize-extension-manifest.sh <base-manifest.json> <extended-manifest.json>
#          [--unit-array units|screens] [--rules-file <json>] [--rule <name>|<searched-for>]
#
# rules-file は対象側が抽出規則を明示するための任意 JSON。形式は
# {"unitOverrides":[{"unitKey":"...", "fields":{"追加項目": "値"}}]} とする。
# fields は既存値を上書きせず、既定抽出が扱えない構造に対する確認済みの規則結果だけを渡す。
# 全ユニットで追加項目を検出できなかったときは、出力を残したうえで終了コード 2 を返す。
set -euo pipefail

self_test() {
  local tmp rc=0 base ext rules
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/finalize-extension-manifest-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN
  base="$tmp/base.json"
  ext="$tmp/ext.json"
  rules="$tmp/rules.json"
  echo '{"units":[{"unitKey":"u1"}]}' > "$base"

  # 既定規則で追加が得られる入力: 弱根拠率は 1.0 未満で終了コード0。
  echo '{"units":[{"unitKey":"u1","method":"GET"}]}' > "$ext"
  local _gt_out1
  if _gt_out1="$(bash "$0" "$base" "$ext" --rule 'method|HTTP method' 2>&1)" \
      && jq -e '.detectionSummary.diagnostics.extensionExtraction | .addedUnitCount == 1 and .weakEvidence.ratio < 1' "$ext" >/dev/null; then
    echo "  [PASS] 既定規則: 追加項目と弱根拠率を記録"
  else
    echo "  [FAIL] 既定規則: 追加項目または弱根拠率が不正" >&2
    printf '%s\n' "$_gt_out1" | sed 's/^/    /' >&2
    rc=1
  fi

  # 全体では1件追加されても、未一致規則へ同じ件数を転記しない。
  echo '{"units":[{"unitKey":"u1","method":"GET"}]}' > "$ext"
  local _gt_out2
  if _gt_out2="$(bash "$0" "$base" "$ext" --rule 'method|HTTP method' --rule 'authRequired|認証指定' 2>&1)" \
      && jq -e '.detectionSummary.diagnostics.extensionExtraction.rules
        | (map(select(.name == "method"))[0].matchedUnitCount == 1)
          and (map(select(.name == "authRequired"))[0].matchedUnitCount == 0)' "$ext" >/dev/null; then
    echo "  [PASS] 規則別件数: 一致規則1件・未一致規則0件を個別に記録"
  else
    echo "  [FAIL] 規則別件数: 全体追加件数と規則ごとの一致件数を分離できない" >&2
    printf '%s\n' "$_gt_out2" | sed 's/^/    /' >&2
    rc=1
  fi

  # 既定規則で拾えない入力: 呼び出し側へ rc=2 と規則ごとの探索内容を渡す。
  echo '{"units":[{"unitKey":"u1"}]}' > "$ext"
  local _gt_out3
  if _gt_out3="$(bash "$0" "$base" "$ext" --rule 'method|HTTP method' 2>&1)"; then
    echo "  [FAIL] 弱根拠: rc=2 にならない" >&2
    printf '%s\n' "$_gt_out3" | sed 's/^/    /' >&2
    rc=1
  elif [ "$?" -ne 2 ] || ! jq -e '.detectionSummary.diagnostics.extensionExtraction | .weakEvidence.warning == true and .rules[0].searchedFor == "HTTP method"' "$ext" >/dev/null; then
    echo "  [FAIL] 弱根拠: 診断または規則別出力が不正" >&2
    printf '%s\n' "$_gt_out3" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 弱根拠: rc=2 と規則別診断を記録"
  fi

  # 対象側が明示した規則は、既定規則に無い構造でも追加項目として反映する。
  echo '{"unitOverrides":[{"unitKey":"u1","fields":{"authRequired":true}}]}' > "$rules"
  echo '{"units":[{"unitKey":"u1"}]}' > "$ext"
  local _gt_out4
  if _gt_out4="$(bash "$0" "$base" "$ext" --rules-file "$rules" --rule 'authRequired|対象側の宣言' 2>&1)" \
      && jq -e '.units[0].authRequired == true and .detectionSummary.diagnostics.extensionExtraction.addedUnitCount == 1' "$ext" >/dev/null; then
    echo "  [PASS] 対象側規則: 宣言値を追加"
  else
    echo "  [FAIL] 対象側規則: 宣言値を追加できない" >&2
    printf '%s\n' "$_gt_out4" | sed 's/^/    /' >&2
    rc=1
  fi

  # 規則未指定では unit 配列の既存値を変えず、従来どおり弱根拠として扱う。
  echo '{"units":[{"unitKey":"u1"}]}' > "$ext"
  local _gt_out5
  if _gt_out5="$(bash "$0" "$base" "$ext" 2>&1)"; then
    echo "  [FAIL] 規則未指定: rc=2 にならない" >&2
    printf '%s\n' "$_gt_out5" | sed 's/^/    /' >&2
    rc=1
  elif [ "$?" -ne 2 ] || ! jq -e '.units == [{"unitKey":"u1"}]' "$ext" >/dev/null; then
    echo "  [FAIL] 規則未指定: 既存結果を維持できない" >&2
    printf '%s\n' "$_gt_out5" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 規則未指定: 既存結果を維持"
  fi

  # 既にある診断は履歴として保持し、今回の実行で上書きしない。
  echo '{"units":[{"unitKey":"u1","method":"GET"}],"detectionSummary":{"diagnostics":{"extensionExtraction":{"addedUnitCount":1,"total":1,"weakEvidence":{"count":0,"total":1,"ratio":0,"warning":false},"rules":[],"preserved":true}}}}' > "$ext"
  local _gt_out6
  if _gt_out6="$(bash "$0" "$base" "$ext" --rule 'method|HTTP method' 2>&1)" \
      && jq -e '.detectionSummary.diagnostics.extensionExtraction.preserved == true' "$ext" >/dev/null; then
    echo "  [PASS] 既存診断: extensionExtractionを上書きしない"
  else
    echo "  [FAIL] 既存診断: extensionExtractionを上書きした" >&2
    printf '%s\n' "$_gt_out6" | sed 's/^/    /' >&2
    rc=1
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

BASE_MANIFEST="${1:?Usage: $0 <base-manifest.json> <extended-manifest.json> [...] }"
EXTENDED_MANIFEST="${2:?Usage: $0 <base-manifest.json> <extended-manifest.json> [...] }"
shift 2
UNIT_ARRAY="units"
RULES_FILE=""
RULES_JSON='[]'

while [ "$#" -gt 0 ]; do
  case "$1" in
    --unit-array) UNIT_ARRAY="${2:-}"; shift 2 ;;
    --rules-file) RULES_FILE="${2:-}"; shift 2 ;;
    --rule)
      rule="${2:-}"
      case "$rule" in
        *'|'*) rule_name="${rule%%|*}"; searched_for="${rule#*|}" ;;
        *) echo "ERROR: --rule は name|searched-for 形式です: $rule" >&2; exit 1 ;;
      esac
      RULES_JSON="$(jq --arg name "$rule_name" --arg searchedFor "$searched_for" '. + [{name: $name, searchedFor: $searchedFor}]' <<<"$RULES_JSON")"
      shift 2
      ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

case "$UNIT_ARRAY" in units|screens) ;; *) echo "ERROR: unsupported unit array: $UNIT_ARRAY" >&2; exit 1 ;; esac
[ -f "$BASE_MANIFEST" ] || { echo "ERROR: base manifest がない: $BASE_MANIFEST" >&2; exit 1; }
[ -f "$EXTENDED_MANIFEST" ] || { echo "ERROR: extended manifest がない: $EXTENDED_MANIFEST" >&2; exit 1; }

OVERRIDES_JSON='[]'
if [ -n "$RULES_FILE" ]; then
  if ! OVERRIDES_JSON="$(jq -ce '.unitOverrides // [] | if type == "array" and all(.[]; (type == "object") and (.unitKey | type == "string") and (.fields | type == "object")) then . else error("unitOverrides must be [{unitKey, fields}]") end' "$RULES_FILE")"; then
    echo "ERROR: 抽出規則ファイルの形式が不正: $RULES_FILE" >&2
    exit 1
  fi
fi

# overridesはRULES_FILEのunitOverridesから来る値で、対象単位1件ごとに1要素を
# 持つ構造のため件数に比例して伸びうる。コマンドライン引数ではなく一時ファイル
# 経由(--slurpfile)でjqへ渡す（改善課題1-52）。rulesは呼び出し側が --rule を
# 固定個数（抽出種別ごとに3〜5個）だけ渡す設計であり件数が伸びないため
# --argjson のまま残す。
output_dir="$(dirname "$EXTENDED_MANIFEST")"
# 理由：jqの直接出力は途中失敗で既存マニフェストを空または部分出力へ置き換えうるため、
# 同一ディレクトリの一時ファイルへ完成させてからmvし、確定結果だけを反映する。
# 実測値：なし。
# 環境依存：なし。同一ディレクトリを使い、別ファイルシステムになる構成を避ける。
# 手元の正常系だけを理由に、直接リダイレクトへ戻さないこと。
# 経緯：a2c015e1導入時から一時ファイル方式だったが、理由の記録がなかった。
if ! tmp_output="$(mktemp "$output_dir/.finalize-extension-manifest.XXXXXX" 2>/dev/null)" || [ -z "$tmp_output" ]; then
  echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi
if ! overrides_tmp="$(mktemp "$output_dir/.finalize-extension-manifest-overrides.XXXXXX" 2>/dev/null)" || [ -z "$overrides_tmp" ]; then
  echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi
trap 'rm -f "$tmp_output" "$overrides_tmp"' EXIT
printf '%s' "$OVERRIDES_JSON" > "$overrides_tmp"

jq --slurpfile base "$BASE_MANIFEST" --arg array "$UNIT_ARRAY" --slurpfile overridesFile "$overrides_tmp" --argjson rules "$RULES_JSON" '
  ($overridesFile[0]) as $overrides
  | (reduce $overrides[] as $rule ({}; .[$rule.unitKey] = $rule.fields)) as $overrideMap
  | .[$array] = [ .[$array][]? | . as $unit | (($overrideMap[($unit.unitKey // $unit.screenKey // "")] // {}) + $unit) ]
  | . as $extended
  | ([$extended[$array][]?] | length) as $total
  | ([$extended[$array] | to_entries[] | .key as $i | .value as $after | ($base[0][$array][$i] // {}) as $before | select((($after | keys) - ($before | keys) | length) > 0)] | length) as $added
  | ($total - $added) as $weak
  | .detectionSummary = ((.detectionSummary // {}) | .diagnostics = ((.diagnostics // {}) | if has("extensionExtraction") then . else . + {extensionExtraction: {addedUnitCount: $added, total: $total, weakEvidence: {count: $weak, total: $total, ratio: (if $total > 0 then ($weak / $total) else 0 end), warning: ($total > 0 and $weak == $total)}, rules: ($rules | map(. as $rule | . + {matchedUnitCount: ([$extended[$array] | to_entries[] | .key as $i | .value as $after | ($base[0][$array][$i] // {}) as $before | select(($before | has($rule.name) | not) and ($after | has($rule.name)))] | length)}))}} end))
' "$EXTENDED_MANIFEST" > "$tmp_output"
mv "$tmp_output" "$EXTENDED_MANIFEST"

total="$(jq -r '.detectionSummary.diagnostics.extensionExtraction.total' "$EXTENDED_MANIFEST")"
added="$(jq -r '.detectionSummary.diagnostics.extensionExtraction.addedUnitCount' "$EXTENDED_MANIFEST")"
if [ "$total" -gt 0 ] && [ "$added" -eq 0 ]; then
  echo "WARN: EXTENSION_EXTRACTION_ALL_WEAK added=0 total=$total; 規則ごとの探索結果は detectionSummary.diagnostics.extensionExtraction.rules を確認してください" >&2
  exit 2
fi
echo "OK: extension extraction added=$added total=$total" >&2
