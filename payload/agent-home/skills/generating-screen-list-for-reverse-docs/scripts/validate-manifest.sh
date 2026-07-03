#!/usr/bin/env bash
# generating-screen-list-for-reverse-docs: screen-manifest.json の独立検証(6項目)。抽出元(組み込みスクリプト/Claude手書き)を問わずマニフェスト品質を機械保証する。
#
# Usage: validate-manifest.sh <manifest.json> [--fix <fixed-out.json>]
#
# 検査項目(全6項目。結果は [PASS]/[FAIL] 項目名 — 詳細 の形式でstderrへ列挙):
#   1. schema-必須フィールド    : トップレベル必須キー + screens[]各要素の必須キーの存在
#   2. strategy-承認            : strategy.extractionMethod 非空 かつ strategy.approvedByUser == true
#   3. 重複-route+entryFile     : (route, entryFile) 組の重複0件
#   4. entryFile-実在           : kind=route/embedded-view の entryFile がファイルとして実在するか
#                                  (--fix指定時は不在行を kind=unresolved・confidence=low に降格し
#                                   detectionSummaryを再計算した修正版JSONを出力してPASS扱い)
#   5. 意味キー-品質            : screenKeyが連番ID規約(数字のみ/-数字終わり/前後ハイフン/連続ハイフン)に違反していないか
#   6. summary-一致             : detectionSummary が screens[] からの再計算値と一致するか
#                                  (--fix出力に対しては修正後の値で検査)
#
# 全6項目PASSでexit 0。1件でもFAILがあればexit 1(--fixで解消された項目4はPASS扱い)。

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

MANIFEST="${1:-}"
if [ -z "$MANIFEST" ]; then
  echo "Usage: validate-manifest.sh <manifest.json> [--fix <fixed-out.json>]" >&2
  exit 1
fi

FIX_OUT=""
if [ "${2:-}" = "--fix" ]; then
  FIX_OUT="${3:-}"
  if [ -z "$FIX_OUT" ]; then
    echo "Usage: validate-manifest.sh <manifest.json> --fix <fixed-out.json>" >&2
    exit 1
  fi
fi

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 1
fi

if ! jq empty "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: invalid JSON: $MANIFEST" >&2
  exit 1
fi

overall_fail=0

# ---------------------------------------------------------------------------
# 1. schema-必須フィールド
# ---------------------------------------------------------------------------
missing_top="$(jq -r '(["generatedAt","sourceDir","strategy","detectionSummary","screens"]) - keys | join(",")' "$MANIFEST")"
missing_screen_fields="$(jq -r '
  [ .screens[]? |
    ( ["screenKey","kind","route","entryFile","confidence"] - keys ) as $miss
    | select(($miss | length) > 0)
    | (.screenKey // "?") + ":" + ($miss | join(","))
  ] | join("; ")
' "$MANIFEST")"

if [ -n "$missing_top" ] || [ -n "$missing_screen_fields" ]; then
  overall_fail=1
  detail="トップレベル欠落=[${missing_top}] screens欠落=[${missing_screen_fields}]"
  echo "[FAIL] schema-必須フィールド — ${detail}" >&2
else
  echo "[PASS] schema-必須フィールド — 必須キーはすべて存在" >&2
fi

# ---------------------------------------------------------------------------
# 2. strategy-承認
# ---------------------------------------------------------------------------
extraction_nonempty="$(jq -r '((.strategy.extractionMethod // "") | length) > 0' "$MANIFEST")"
approved_true="$(jq -r '(.strategy.approvedByUser == true)' "$MANIFEST")"

if [ "$extraction_nonempty" != "true" ] || [ "$approved_true" != "true" ]; then
  overall_fail=1
  echo "[FAIL] strategy-承認 — Phase 1の検出戦略宣言が未承認です。承認を経ずに後続Phaseへ進むことはできません" >&2
else
  echo "[PASS] strategy-承認 — extractionMethod設定済み・approvedByUser=true" >&2
fi

# ---------------------------------------------------------------------------
# 3. 重複-route+entryFile
# ---------------------------------------------------------------------------
dup_list="$(jq -r '
  [ .screens[]? | (.route // "") + "|" + (.entryFile // "") ]
  | group_by(.) | map(select(length > 1) | .[0]) | join("; ")
' "$MANIFEST")"

if [ -n "$dup_list" ]; then
  overall_fail=1
  echo "[FAIL] 重複-route+entryFile — 重複組: ${dup_list}" >&2
else
  echo "[PASS] 重複-route+entryFile — 重複組0件" >&2
fi

# ---------------------------------------------------------------------------
# 4. entryFile-実在
# ---------------------------------------------------------------------------
source_dir="$(jq -r '.sourceDir // ""' "$MANIFEST")"

missing_keys_raw=""
missing_detail=""
while IFS= read -r row; do
  [ -z "$row" ] && continue
  key="$(jq -r '.screenKey // "?"' <<<"$row")"
  ef="$(jq -r '.entryFile // ""' <<<"$row")"
  if [ -z "$ef" ]; then
    missing_keys_raw="${missing_keys_raw}${key}
"
    missing_detail="${missing_detail}${key}:(empty entryFile); "
    continue
  fi
  case "$ef" in
    /*) path="$ef" ;;
    *) path="${source_dir%/}/$ef" ;;
  esac
  if [ ! -f "$path" ]; then
    missing_keys_raw="${missing_keys_raw}${key}
"
    missing_detail="${missing_detail}${key}:${ef}; "
  fi
done < <(jq -c '.screens[]? | select(.kind == "route" or .kind == "embedded-view")' "$MANIFEST")

check4_pass=1
if [ -n "$missing_keys_raw" ]; then
  if [ -n "$FIX_OUT" ]; then
    missing_keys_json="$(printf '%s' "$missing_keys_raw" | jq -R -s 'split("\n") | map(select(length > 0))')"
    jq --argjson missing "$missing_keys_json" '
      .screens = [
        .screens[] |
        if (.kind == "route" or .kind == "embedded-view") and ((.screenKey // "?") as $k | ($missing | index($k)) != null)
        then .kind = "unresolved" | .confidence = "low"
        else .
        end
      ]
      | .detectionSummary.screenCount = (.screens | length)
      | .detectionSummary.clusterCount = (.screens | map(.clusterId) | map(select(. != null)) | unique | length)
      | .detectionSummary.sharedScreenCount = (.screens | map(select((.sharedWith // []) | length > 0)) | length)
      | .detectionSummary.embeddedCandidateCount = (.screens | map(select(.kind == "embedded-view")) | length)
      | .detectionSummary.unresolvedCount = (.screens | map(select(.kind == "unresolved")) | length)
    ' "$MANIFEST" > "$FIX_OUT"
    echo "[PASS] entryFile-実在 — 不在エントリを修正: unresolvedへ降格し summary 再計算のうえ ${FIX_OUT} に出力しました(${missing_detail})" >&2
  else
    overall_fail=1
    check4_pass=0
    echo "[FAIL] entryFile-実在 — 実在しないentryFile: ${missing_detail}" >&2
  fi
else
  echo "[PASS] entryFile-実在 — 全entryFileが実在" >&2
fi

# ---------------------------------------------------------------------------
# 5. 意味キー-品質
# ---------------------------------------------------------------------------
bad_keys="$(jq -r '
  [ .screens[]? | (.screenKey // "") |
    select(
      test("^[0-9]+$") or test("-[0-9]+$") or test("^-") or test("-$") or test("--")
    )
  ] | join(", ")
' "$MANIFEST")"

if [ -n "$bad_keys" ]; then
  overall_fail=1
  echo "[FAIL] 意味キー-品質 — 連番ID規約違反のscreenKey: ${bad_keys}" >&2
else
  echo "[PASS] 意味キー-品質 — 連番ID規約違反0件" >&2
fi

# ---------------------------------------------------------------------------
# 6. summary-一致(--fixが実行された場合は修正後JSONで検査)
# ---------------------------------------------------------------------------
if [ -n "$FIX_OUT" ] && [ -n "$missing_keys_raw" ] && [ -f "$FIX_OUT" ]; then
  effective_source="$FIX_OUT"
else
  effective_source="$MANIFEST"
fi

actual_summary="$(jq -c '{
  screenCount: (.detectionSummary.screenCount // 0),
  clusterCount: (.detectionSummary.clusterCount // 0),
  sharedScreenCount: (.detectionSummary.sharedScreenCount // 0),
  embeddedCandidateCount: (.detectionSummary.embeddedCandidateCount // 0),
  unresolvedCount: (.detectionSummary.unresolvedCount // 0)
}' "$effective_source")"

recalced_summary="$(jq -c '{
  screenCount: (.screens | length),
  clusterCount: (.screens | map(.clusterId) | map(select(. != null)) | unique | length),
  sharedScreenCount: (.screens | map(select((.sharedWith // []) | length > 0)) | length),
  embeddedCandidateCount: (.screens | map(select(.kind == "embedded-view")) | length),
  unresolvedCount: (.screens | map(select(.kind == "unresolved")) | length)
}' "$effective_source")"

if [ "$actual_summary" != "$recalced_summary" ]; then
  overall_fail=1
  echo "[FAIL] summary-一致 — detectionSummary=${actual_summary} 再計算値=${recalced_summary}" >&2
else
  echo "[PASS] summary-一致 — detectionSummaryは再計算値と一致" >&2
fi

# ---------------------------------------------------------------------------
if [ "$overall_fail" -eq 0 ]; then
  echo "[OK] validate-manifest: 全6項目PASS" >&2
  exit 0
fi

exit 1
