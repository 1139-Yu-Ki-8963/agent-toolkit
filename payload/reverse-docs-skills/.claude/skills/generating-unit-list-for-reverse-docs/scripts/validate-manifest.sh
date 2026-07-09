#!/usr/bin/env bash
# generating-unit-list-for-reverse-docs: ユニットマニフェスト(screen-manifest.json 等)の独立検証(7項目)。
# 抽出元(組み込みスクリプト/Claude手書き)・ユニット種別(screen/api/table/batch/report/external)を
# 問わずマニフェスト品質を機械保証する。unit_kind=screen(デフォルト)の場合は従来と完全に同じ
# 出力・挙動を保証する。
#
# Usage: validate-manifest.sh <manifest.json> [--fix <fixed-out.json>] [--unit-kind <kind>]
#        validate-manifest.sh --self-test
#
# --unit-kind 未指定時は、マニフェスト内の unitKind フィールド(jq -r '.unitKind // empty')を読み、
# それも空なら screen にフォールバックする。unit_kind=screen の場合は配列キー screens・要素キー
# screenKey/route/entryFile/screenIdRegex を使う。screen以外は units・unitKey/identifier/
# sourceFile/unitIdRegex を使う。
#
# 検査項目(全7項目。結果は [PASS]/[FAIL] 項目名 — 詳細 の形式でstderrへ列挙):
#   1. schema-必須フィールド    : トップレベル必須キー + 各要素の必須キーの存在
#                                  (screen: generatedAt,sourceDir,strategy,detectionSummary,screens /
#                                   screenKey,kind,route,entryFile,confidence。
#                                   screen以外: 上記に unitKind を追加 / unitKey,kind,identifier,
#                                   sourceFile,confidence)
#   2. strategy-承認            : strategy.extractionMethod 非空 かつ strategy.approvedByUser == true
#   3. 重複-route+entryFile     : (route, entryFile) 組の重複0件
#                                  (screen以外は (identifier, sourceFile) 組の重複0件)
#   4. entryFile-実在           : kind=route/embedded-view の entryFile がファイルとして実在するか
#                                  (screen以外は kind!=unresolved の sourceFile が実在するかを検査。
#                                   --fix指定時は不在行を kind=unresolved・confidence=low に降格し
#                                   detectionSummaryを再計算した修正版JSONを出力してPASS扱い)
#   5. 意味キー-品質            : screenKeyが連番ID規約(数字のみ/-数字終わり/前後ハイフン/連続ハイフン)に違反していないか
#                                  (screen以外は unitKey を同基準で検査。
#                                   strategy.screenIdRegex(screen以外はunitIdRegex)が非null文字列の場合、
#                                   そのEREに完全一致するキーおよび `<一致部分>-<dup番号>` 形式の
#                                   派生キーは業務ID由来として判定対象から除外する)
#   6. 参照整合                : 派生キー(末尾-dup番号)の元キー実在・sharedWith参照先の実在・embeddedIn親キーの実在
#                                  (strategy.sharedWithBusinessIdsAllowed=trueかつscreenIdRegex設定時のみ、
#                                   sharedWith要素のうちregexに完全一致する業務IDは行未解決でも参照整合の
#                                   対象外とする opt-in 緩和。デフォルトfalseはstrict維持。embeddedIn等には非適用。
#                                   screen以外は sharedWith/embeddedIn を持たないため、派生キーの元キー実在
#                                   チェックのみ実行する)
#   7. summary-一致             : detectionSummary が screens[]/units[] からの再計算値と一致するか
#                                  (screen: screenCount/clusterCount/sharedScreenCount/embeddedCandidateCount/
#                                   unresolvedCount。screen以外: unitCount/unresolvedCount のみ。
#                                   --fix出力に対しては修正後の値で検査)
#
# 全7項目PASSでexit 0。1件でもFAILがあればexit 1(--fixで解消された項目4はPASS扱い)。

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 検証本体。manifest・fix_out(空文字可)・unit_kind を受け取り、[PASS]/[FAIL]行を
# stderrへ列挙したうえで、全項目PASSなら0、1件でもFAILなら1をreturnする。
# ---------------------------------------------------------------------------
run_validate() {
  local MANIFEST="$1"
  local FIX_OUT="$2"
  local UNIT_KIND="$3"

  local ITEMS_KEY ITEM_KEY_FIELD IDENTIFIER_FIELD SOURCE_FIELD ID_REGEX_FIELD SUMMARY_COUNT_FIELD
  local TOP_REQUIRED_JSON ITEM_REQUIRED_JSON
  case "$UNIT_KIND" in
    screen)
      ITEMS_KEY="screens"
      ITEM_KEY_FIELD="screenKey"
      IDENTIFIER_FIELD="route"
      SOURCE_FIELD="entryFile"
      ID_REGEX_FIELD="screenIdRegex"
      SUMMARY_COUNT_FIELD="screenCount"
      TOP_REQUIRED_JSON='["generatedAt","sourceDir","strategy","detectionSummary","screens"]'
      ITEM_REQUIRED_JSON='["screenKey","kind","route","entryFile","confidence"]'
      ;;
    *)
      ITEMS_KEY="units"
      ITEM_KEY_FIELD="unitKey"
      IDENTIFIER_FIELD="identifier"
      SOURCE_FIELD="sourceFile"
      ID_REGEX_FIELD="unitIdRegex"
      SUMMARY_COUNT_FIELD="unitCount"
      TOP_REQUIRED_JSON='["generatedAt","sourceDir","unitKind","strategy","detectionSummary","units"]'
      ITEM_REQUIRED_JSON='["unitKey","kind","identifier","sourceFile","confidence"]'
      ;;
  esac

  local overall_fail=0

  # ---------------------------------------------------------------------------
  # 1. schema-必須フィールド
  # ---------------------------------------------------------------------------
  local missing_top missing_item_fields detail
  missing_top="$(jq -r --argjson req "$TOP_REQUIRED_JSON" '$req - keys | join(",")' "$MANIFEST")"
  missing_item_fields="$(jq -r --arg items "$ITEMS_KEY" --argjson req "$ITEM_REQUIRED_JSON" --arg keyfield "$ITEM_KEY_FIELD" '
    [ .[$items][]? |
      ( $req - keys ) as $miss
      | select(($miss | length) > 0)
      | (.[$keyfield] // "?") + ":" + ($miss | join(","))
    ] | join("; ")
  ' "$MANIFEST")"

  if [ -n "$missing_top" ] || [ -n "$missing_item_fields" ]; then
    overall_fail=1
    detail="トップレベル欠落=[${missing_top}] ${ITEMS_KEY}欠落=[${missing_item_fields}]"
    echo "[FAIL] schema-必須フィールド — ${detail}" >&2
  else
    echo "[PASS] schema-必須フィールド — 必須キーはすべて存在" >&2
  fi

  # ---------------------------------------------------------------------------
  # 2. strategy-承認
  # ---------------------------------------------------------------------------
  local extraction_nonempty approved_true
  extraction_nonempty="$(jq -r '((.strategy.extractionMethod // "") | length) > 0' "$MANIFEST")"
  approved_true="$(jq -r '(.strategy.approvedByUser == true)' "$MANIFEST")"

  if [ "$extraction_nonempty" != "true" ] || [ "$approved_true" != "true" ]; then
    overall_fail=1
    echo "[FAIL] strategy-承認 — Phase 1の検出戦略宣言が未承認です。承認を経ずに後続Phaseへ進むことはできません" >&2
  else
    echo "[PASS] strategy-承認 — extractionMethod設定済み・approvedByUser=true" >&2
  fi

  # ---------------------------------------------------------------------------
  # 3. 重複-<identifier>+<source> (screen: route+entryFile / screen以外: identifier+sourceFile)
  # ---------------------------------------------------------------------------
  local dup_list dup_label
  dup_label="重複-${IDENTIFIER_FIELD}+${SOURCE_FIELD}"
  dup_list="$(jq -r --arg items "$ITEMS_KEY" --arg idf "$IDENTIFIER_FIELD" --arg srcf "$SOURCE_FIELD" '
    [ .[$items][]? | (.[$idf] // "") + "|" + (.[$srcf] // "") ]
    | group_by(.) | map(select(length > 1) | .[0]) | join("; ")
  ' "$MANIFEST")"

  if [ -n "$dup_list" ]; then
    overall_fail=1
    echo "[FAIL] ${dup_label} — 重複組: ${dup_list}" >&2
  else
    echo "[PASS] ${dup_label} — 重複組0件" >&2
  fi

  # ---------------------------------------------------------------------------
  # 4. <source>-実在 (screen: entryFile-実在 / screen以外: sourceFile-実在)
  #    screen: kind=route/embedded-view の entryFile を検査
  #    screen以外: kind!=unresolved の sourceFile を検査
  # ---------------------------------------------------------------------------
  local source_dir check4_label
  source_dir="$(jq -r '.sourceDir // ""' "$MANIFEST")"
  check4_label="${SOURCE_FIELD}-実在"

  local missing_keys_raw="" missing_detail="" row key ef path
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    key="$(jq -r --arg f "$ITEM_KEY_FIELD" '.[$f] // "?"' <<<"$row")"
    ef="$(jq -r --arg f "$SOURCE_FIELD" '.[$f] // ""' <<<"$row")"
    if [ -z "$ef" ]; then
      missing_keys_raw="${missing_keys_raw}${key}
"
      missing_detail="${missing_detail}${key}:(empty ${SOURCE_FIELD}); "
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
  done < <(
    if [ "$UNIT_KIND" = "screen" ]; then
      jq -c '.screens[]? | select(.kind == "route" or .kind == "embedded-view")' "$MANIFEST"
    else
      jq -c '.units[]? | select(.kind != "unresolved")' "$MANIFEST"
    fi
  )

  local check4_pass=1
  if [ -n "$missing_keys_raw" ]; then
    if [ -n "$FIX_OUT" ]; then
      local missing_keys_json
      missing_keys_json="$(printf '%s' "$missing_keys_raw" | jq -R -s 'split("\n") | map(select(length > 0))')"
      if [ "$UNIT_KIND" = "screen" ]; then
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
      else
        jq --argjson missing "$missing_keys_json" '
          .units = [
            .units[] |
            if (.kind != "unresolved") and ((.unitKey // "?") as $k | ($missing | index($k)) != null)
            then .kind = "unresolved" | .confidence = "low"
            else .
            end
          ]
          | .detectionSummary.unitCount = (.units | length)
          | .detectionSummary.unresolvedCount = (.units | map(select(.kind == "unresolved")) | length)
        ' "$MANIFEST" > "$FIX_OUT"
      fi
      echo "[PASS] ${check4_label} — 不在エントリを修正: unresolvedへ降格し summary 再計算のうえ ${FIX_OUT} に出力しました(${missing_detail})" >&2
    else
      overall_fail=1
      check4_pass=0
      echo "[FAIL] ${check4_label} — 実在しない${SOURCE_FIELD}: ${missing_detail}" >&2
    fi
  else
    echo "[PASS] ${check4_label} — 全${SOURCE_FIELD}が実在" >&2
  fi

  # ---------------------------------------------------------------------------
  # 5. 意味キー-品質
  #    strategy.<ID_REGEX_FIELD>が非null文字列の場合、そのEREに完全一致するキー
  #    (および `<一致部分>-<dup番号>` 形式の派生キー)は業務ID由来として判定対象から除外する
  # ---------------------------------------------------------------------------
  local id_regex bad_keys
  id_regex="$(jq -r --arg f "$ID_REGEX_FIELD" '(.strategy[$f] // "")' "$MANIFEST")"

  bad_keys="$(jq -r --arg re "$id_regex" --arg items "$ITEMS_KEY" --arg keyfield "$ITEM_KEY_FIELD" '
    ($re | length > 0) as $has_re
    | ("^(" + $re + ")(-[0-9]+)?$") as $exclude
    | [ .[$items][]? | (.[$keyfield] // "") |
        (
          if $has_re then (try (test($exclude)) catch false) else false end
        ) as $is_excluded
        | select(
            ($is_excluded | not) and
            (test("^[0-9]+$") or test("-[0-9]+$") or test("^-") or test("-$") or test("--"))
          )
      ] | join(", ")
  ' "$MANIFEST")"

  if [ -n "$bad_keys" ]; then
    overall_fail=1
    echo "[FAIL] 意味キー-品質 — 連番ID規約違反の${ITEM_KEY_FIELD}: ${bad_keys}" >&2
  else
    echo "[PASS] 意味キー-品質 — 連番ID規約違反0件" >&2
  fi

  # ---------------------------------------------------------------------------
  # 6. 参照整合
  #    screen: 派生キー(末尾-dup番号)の元キー実在・sharedWith参照先の実在・embeddedIn親キーの実在
  #      (screenIdRegex設定時は、regexに完全一致しないキーのみを派生キー候補とする)
  #      参照先の実在判定は screenKey への一致 または screenId(業務ID)への一致のいずれかで成立とする
  #      (「代表1冊+バリエーション統合」方式では sharedWith/embeddedIn に独立screenKeyを持たない
  #       業務IDが列挙されるため)。
  #      strategy.sharedWithBusinessIdsAllowed=true かつ screenIdRegex非null文字列の場合のみ、
  #      sharedWith要素のうちregexに完全一致する業務IDは行未解決でも参照整合の対象外とする
  #      (opt-in緩和。デフォルトfalseはstrict維持。派生キー・embeddedInには非適用)。
  #    screen以外: sharedWith/embeddedInを持たないため、派生キーの元キー実在チェックのみ実行する。
  #    jqがエラー終了した場合はfail-closedで即FAILとする(誤PASS防止)。
  # ---------------------------------------------------------------------------
  local ref_integrity_issues jq_rc
  if [ "$UNIT_KIND" = "screen" ]; then
    local shared_with_relax_flag
    shared_with_relax_flag="$(jq -r '(.strategy.sharedWithBusinessIdsAllowed == true)' "$MANIFEST")"

    ref_integrity_issues="$(jq -r --arg re "$id_regex" --argjson relaxFlag "$shared_with_relax_flag" '
      ($re | length > 0) as $has_re
      | ($relaxFlag and $has_re) as $relax_shared_with
      | (.screens // []) as $screens
      | ($screens | map(.screenKey // "") | map(select(length > 0))) as $validkeys
      | ($screens | map(.screenId // empty) | map(select(type == "string" and length > 0))) as $validids
      | (
          [ $validkeys[] | . as $k
            | (
                if $has_re then
                  ( (try (test("^(" + $re + ")$")) catch false) as $full
                    | (try (test("^(" + $re + ")-[0-9]+$")) catch false) as $suffixed
                    | ($full | not) and $suffixed
                  )
                else
                  (test("-[0-9]+$"))
                end
              ) as $is_derived
            | select($is_derived)
            | ($k | sub("-[0-9]+$"; "")) as $base
            | select((($validkeys | index($base)) == null) and (($validids | index($base)) == null))
            | "派生キー[" + $k + "]の元キー[" + $base + "]が不在"
          ]
          +
          [ $screens[] | (.screenKey // "?") as $sk
            | (.sharedWith // [])[] as $sw
            | ((($validkeys | index($sw)) == null) and (($validids | index($sw)) == null)) as $unresolved
            | ($relax_shared_with and (try ($sw | test("^(" + $re + ")$")) catch false)) as $is_business_id
            | select($unresolved and ($is_business_id | not))
            | "screens[" + $sk + "].sharedWith[" + $sw + "]が不在"
          ]
          +
          [ $screens[] | (.screenKey // "?") as $sk
            | .embeddedIn as $ei
            | (
                if ($ei | type) == "array" then $ei
                elif ($ei | type) == "string" then
                  ($ei | split(",") | map(gsub("^ +"; "") | gsub(" +$"; "")))
                else []
                end
              ) as $parents
            | $parents[] | select(length > 0) as $parent
            | select((($validkeys | index($parent)) == null) and (($validids | index($parent)) == null))
            | "screens[" + $sk + "].embeddedIn[" + $parent + "]が不在"
          ]
        ) | join("; ")
    ' "$MANIFEST" 2>/dev/null)"
    jq_rc=$?
  else
    ref_integrity_issues="$(jq -r --arg re "$id_regex" --arg items "$ITEMS_KEY" --arg keyfield "$ITEM_KEY_FIELD" '
      ($re | length > 0) as $has_re
      | (.[$items] // []) as $items_arr
      | ($items_arr | map(.[$keyfield] // "") | map(select(length > 0))) as $validkeys
      | (
          [ $validkeys[] | . as $k
            | (
                if $has_re then
                  ( (try (test("^(" + $re + ")$")) catch false) as $full
                    | (try (test("^(" + $re + ")-[0-9]+$")) catch false) as $suffixed
                    | ($full | not) and $suffixed
                  )
                else
                  (test("-[0-9]+$"))
                end
              ) as $is_derived
            | select($is_derived)
            | ($k | sub("-[0-9]+$"; "")) as $base
            | select(($validkeys | index($base)) == null)
            | "派生キー[" + $k + "]の元キー[" + $base + "]が不在"
          ]
        ) | join("; ")
    ' "$MANIFEST" 2>/dev/null)"
    jq_rc=$?
  fi

  if [ "$jq_rc" -ne 0 ]; then
    overall_fail=1
    echo "[FAIL] 参照整合 — jq評価エラー(rc=${jq_rc})。マニフェスト構造を確認してください" >&2
  elif [ -n "$ref_integrity_issues" ]; then
    overall_fail=1
    echo "[FAIL] 参照整合 — ${ref_integrity_issues}" >&2
  else
    echo "[PASS] 参照整合 — 派生キー・sharedWith・embeddedInの参照先はすべて実在" >&2
  fi

  # ---------------------------------------------------------------------------
  # 7. summary-一致(--fixが実行された場合は修正後JSONで検査)
  # ---------------------------------------------------------------------------
  local effective_source actual_summary recalced_summary
  if [ -n "$FIX_OUT" ] && [ -n "$missing_keys_raw" ] && [ -f "$FIX_OUT" ]; then
    effective_source="$FIX_OUT"
  else
    effective_source="$MANIFEST"
  fi

  if [ "$UNIT_KIND" = "screen" ]; then
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
  else
    actual_summary="$(jq -c '{
      unitCount: (.detectionSummary.unitCount // 0),
      unresolvedCount: (.detectionSummary.unresolvedCount // 0)
    }' "$effective_source")"

    recalced_summary="$(jq -c '{
      unitCount: (.units | length),
      unresolvedCount: (.units | map(select(.kind == "unresolved")) | length)
    }' "$effective_source")"
  fi

  if [ "$actual_summary" != "$recalced_summary" ]; then
    overall_fail=1
    echo "[FAIL] summary-一致 — detectionSummary=${actual_summary} 再計算値=${recalced_summary}" >&2
  else
    echo "[PASS] summary-一致 — detectionSummaryは再計算値と一致" >&2
  fi

  # ---------------------------------------------------------------------------
  if [ "$overall_fail" -eq 0 ]; then
    echo "[OK] validate-manifest: 全7項目PASS" >&2
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# 自己テスト: screen(既定パス・後方互換確認)とapi(汎用パス確認)の両方を検証する。
# ---------------------------------------------------------------------------
self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-manifest-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  local rc=0

  # ---- screen フィクスチャ: 既定パス(--unit-kind未指定)の後方互換確認 ----
  mkdir -p "$tmp/screen-src/src/screens"
  cat > "$tmp/screen-src/src/screens/Home.tsx" <<'EOF'
export function Home() { return null; }
EOF

  local screen_pass="$tmp/screen-pass.json"
  cat > "$screen_pass" <<JSON
{
  "generatedAt": "2026-01-01T00:00:00Z",
  "sourceDir": "$tmp/screen-src",
  "strategy": {
    "extractionMethod": "custom",
    "approvedByUser": true,
    "screenIdRegex": null,
    "excludePatterns": []
  },
  "detectionSummary": {
    "screenCount": 1,
    "clusterCount": 0,
    "sharedScreenCount": 0,
    "embeddedCandidateCount": 0,
    "unresolvedCount": 0
  },
  "screens": [
    {
      "screenKey": "home-screen",
      "kind": "route",
      "route": "/home",
      "entryFile": "src/screens/Home.tsx",
      "confidence": "high"
    }
  ]
}
JSON

  if run_validate "$screen_pass" "" "screen" >/dev/null 2>&1; then
    echo "  [PASS] screen陽性: 既定unitKind(screen)で全7項目PASS"
  else
    echo "  [FAIL] screen陽性: 正当なscreenマニフェストがFAILした" >&2
    rc=1
  fi

  local screen_missing_top="$tmp/screen-missing-top.json"
  jq 'del(.screens)' "$screen_pass" > "$screen_missing_top"
  if run_validate "$screen_missing_top" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] screen陰性: screens欠落マニフェストがPASSした" >&2
    rc=1
  else
    echo "  [PASS] screen陰性: screens欠落でFAIL"
  fi

  # ---- api フィクスチャ: unitKind=apiでの汎用パス確認 ----
  mkdir -p "$tmp/api-src/routes"
  cat > "$tmp/api-src/routes/users.ts" <<'EOF'
export function usersRoute() {}
EOF

  local api_pass="$tmp/api-pass.json"
  cat > "$api_pass" <<JSON
{
  "generatedAt": "2026-01-01T00:00:00Z",
  "sourceDir": "$tmp/api-src",
  "unitKind": "api",
  "strategy": {
    "extractionMethod": "custom",
    "approvedByUser": true,
    "unitIdRegex": null,
    "excludePatterns": []
  },
  "detectionSummary": {
    "unitCount": 2,
    "unresolvedCount": 0
  },
  "units": [
    {
      "unitKey": "users-list",
      "kind": "endpoint",
      "identifier": "GET /api/users",
      "sourceFile": "$tmp/api-src/routes/users.ts",
      "confidence": "high"
    },
    {
      "unitKey": "users-detail",
      "kind": "endpoint",
      "identifier": "GET /api/users/:id",
      "sourceFile": "$tmp/api-src/routes/users.ts",
      "confidence": "high"
    }
  ]
}
JSON

  if run_validate "$api_pass" "" "api" >/dev/null 2>&1; then
    echo "  [PASS] api陽性: unitKind=apiで全7項目PASS"
  else
    echo "  [FAIL] api陽性: 正当なapiマニフェストがFAILした" >&2
    rc=1
  fi

  local resolved_kind
  resolved_kind="$(jq -r '.unitKind // empty' "$api_pass")"
  [ -z "$resolved_kind" ] && resolved_kind="screen"
  if [ "$resolved_kind" = "api" ]; then
    echo "  [PASS] unitKind自動判定: マニフェストのunitKindフィールドから'api'を読み取り"
  else
    echo "  [FAIL] unitKind自動判定: 期待='api' 実測='${resolved_kind}'" >&2
    rc=1
  fi

  # 検査4(sourceFile-実在)のFAIL確認: sourceFileが実在しないunitsを混入させる
  local api_missing_source="$tmp/api-missing-source.json"
  jq --arg f "$tmp/api-src/routes/does-not-exist.ts" '.units[0].sourceFile = $f' "$api_pass" > "$api_missing_source"
  if run_validate "$api_missing_source" "" "api" >/dev/null 2>&1; then
    echo "  [FAIL] api陰性: sourceFile不在なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] api陰性: sourceFile不在でFAIL"
  fi

  # --fixでunresolvedへ降格しPASSすることを確認
  local api_fixed="$tmp/api-fixed.json"
  if run_validate "$api_missing_source" "$api_fixed" "api" >/dev/null 2>&1; then
    echo "  [PASS] api --fix: sourceFile不在エントリをunresolvedへ降格しPASS"
  else
    echo "  [FAIL] api --fix: --fix指定時もFAILした" >&2
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

# ---------------------------------------------------------------------------
# 引数パース
# ---------------------------------------------------------------------------
MANIFEST="${1:-}"
if [ -z "$MANIFEST" ]; then
  echo "Usage: validate-manifest.sh <manifest.json> [--fix <fixed-out.json>] [--unit-kind <kind>]" >&2
  exit 1
fi
shift

FIX_OUT=""
UNIT_KIND_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fix)
      FIX_OUT="${2:-}"
      if [ -z "$FIX_OUT" ]; then
        echo "Usage: validate-manifest.sh <manifest.json> [--fix <fixed-out.json>] [--unit-kind <kind>]" >&2
        exit 1
      fi
      shift 2
      ;;
    --unit-kind)
      UNIT_KIND_ARG="${2:-}"
      if [ -z "$UNIT_KIND_ARG" ]; then
        echo "Usage: validate-manifest.sh <manifest.json> [--fix <fixed-out.json>] [--unit-kind <kind>]" >&2
        exit 1
      fi
      shift 2
      ;;
    *)
      echo "Usage: validate-manifest.sh <manifest.json> [--fix <fixed-out.json>] [--unit-kind <kind>]" >&2
      exit 1
      ;;
  esac
done

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 1
fi

if ! jq empty "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: invalid JSON: $MANIFEST" >&2
  exit 1
fi

if [ -n "$UNIT_KIND_ARG" ]; then
  UNIT_KIND="$UNIT_KIND_ARG"
else
  UNIT_KIND="$(jq -r '.unitKind // empty' "$MANIFEST")"
  [ -z "$UNIT_KIND" ] && UNIT_KIND="screen"
fi

run_validate "$MANIFEST" "$FIX_OUT" "$UNIT_KIND"
exit $?
