#!/usr/bin/env bash
# 種別別一覧スキル群(generating-<種別>-list-for-reverse-docs)共通エンジン: ユニットマニフェスト(screen-manifest.json 等)の独立検証(7項目)。
# 抽出元(組み込みスクリプト/Claude手書き)・ユニット種別(screen/api/table/batch/report/external)を
# 問わずマニフェスト品質を機械保証する。unit_kind=screen(デフォルト)の場合は従来と完全に同じ
# 出力・挙動を保証する。
#
# Usage: validate-manifest.sh <manifest.json> [--fix <fixed-out.json>] [--unit-kind <kind>] [--axes <file>]
#        validate-manifest.sh --self-test
#
# --axes <file> は分類軸・任意列の宣言ファイルを受理する(現時点では受理するのみで検査には未使用)。
#
# --unit-kind 未指定時は、マニフェスト内の unitKind フィールド(jq -r '.unitKind // empty')を読み、
# それも空なら screen にフォールバックする。unit_kind=screen の場合は配列キー screens・要素キー
# screenKey/route/entryFile/screenIdRegex を使う。screen以外は units・unitKey/identifier/
# sourceFile/unitIdRegex を使う。
#
# 検査項目(screen: 全16項目 / screen以外: 全12項目。結果は [PASS]/[FAIL] 項目名 — 詳細 の形式でstderrへ列挙):
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
#   8. 任意フィールド-型         : スキーマ拡張(shared/references/manifest-schema-extensions.md
#                                   「種別ごとの追加フィールド定義」が正本)の任意フィールドが要素に
#                                   存在する場合のみ型を検査する(不在はエラーにしない。後方互換):
#                                   - 文字列配列: permissions/relatedApis/callers/foreignKeys/
#                                     mainColumns/targetTables/downstreamJobs
#                                   - boolean: authRequired/hasTemplate/isProcessingEndpoint / 数値: columnCount
#                                   - 文字列: method/ioSummary/designDocStatus/category/format/
#                                     trigger/direction/protocol/authMethod/execMethod/operationClass
#                                   - object({cron, readable}を持つ): schedule
#                                   - 2値制約: designDocStatus(着手済/未着手)・trigger(画面/バッチ)・
#                                     direction(送信/受信)
#   9. 名称-一意性               : 表示名(screen: confirmedScreenName優先・無ければscreenNameGuess /
#                                   screen以外: unitNameGuess)が空でない要素間で重複していないか。
#                                   任意フィールド nameScope(未指定は空文字列)が判定範囲を定める。
#                                   同一nameScope内の重複だけをFAILとし、異なるnameScope間の同名は
#                                   許容する(例: 画面はサイト単位、バッチは配置ディレクトリ単位。1-124)。
#                                   1件でも同一スコープ内重複があればFAILし、重複名称とそれを共有する
#                                   キー全件を列挙する
#  10. 実装参照-統合候補         : 同一の実装参照(screen: entryFile / screen以外: sourceFile)を持つ
#                                   要素群のうち、identifier(screen: route)が引数プレースホルダ
#                                   (`:name`または`{name}`)による分岐を示していないものを統合候補として
#                                   列挙する(常にPASS。自動統合はしない。統合可否は利用者判断)
#  11. screenType-必須+値域     : screen専用(screen以外はskip)。全screensにscreenTypeフィールドが
#                                   存在し(不在・null不可)、値が list/detail/form/confirm/complete/
#                                   error/top/processing_endpoint のいずれかであること
#  12. accountGroup-値域         : screen専用。存在する場合は user/admin/editor/report/common のいずれか
#  13. accountSubType-値域       : screen専用。存在する場合は文字列かつ識別子形式(^[A-Za-z_][A-Za-z0-9_]*$)
#                                   であること(detect-screens.shの抽出値は role 名または common/role_checked
#                                   のいずれかで、固定小集合の列挙ではなく識別子形式のみが不変契約のため)
#  14. parent-child参照          : parentScreen と childComponents のscreenKey実在、componentType値域、
#                                   親→子・子→親の双方向一致を検証する
#  15. unitKey-一意性            : 集約キー(unitKey)の重複0件を検査する
#                                   (screen: 要素がunitKeyを持たないため検査をスキップしPASS扱い /
#                                   screen以外: unitKeyが重複していないか。unitKeyを持つ要素が
#                                   0件、またはunitKeyを持つ要素が1件以下の場合もスキップしPASS扱い)
#  16. 置換文字-非混入           : マニフェスト内の全文字列値に置換文字(U+FFFD, \357\277\275)が
#                                   含まれていないかを検査する(screen/screen以外を問わず共通。1-135)。
#                                   非UTF-8原本を誤ってUTF-8として読み込んだ場合に生じる文字化けを
#                                   機械検知する。含まれる場合は該当パス(キー)と件数を列挙する
#
# 全項目(screen: 16項目 / screen以外: 12項目)PASSでexit 0。1件でもFAILがあればexit 1
# (--fixで解消された項目4はPASS扱い。項目10は常にPASSする情報列挙)。

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

# unit-axes.sh(分類軸・任意列の宣言解決)を source する。sourceは呼び出し元の
# 位置引数を引き継ぐため、--self-test等の引数がunit-axes.sh自身の--self-test分岐に
# 誤って渡らないよう、source中だけ位置引数を空にして復元する。
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_ORIG_ARGS=("$@")
set --
. "$SCRIPT_DIR/../unit-axes.sh"
set -- "${_ORIG_ARGS[@]}"
unset _ORIG_ARGS

# 宣言(axes_json)から指定キーのclosed値域(values[].key)をJSON配列文字列で返す。
# 該当軸が無い/closedでない場合、またはaxes_jsonが空(宣言未解決)の場合は空文字を返す
# (呼び出し側でハードコード値域へのフォールバック判定に使う)。
axes_closed_values() {
  local json="$1" key="$2"
  [ -z "$json" ] && return 0
  printf '%s' "$json" | jq -c --arg k "$key" '
    [ .axes[]? | select(.key==$k and .valuePolicy=="closed") | .values[]?.key ]
  ' 2>/dev/null
}

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
  local missing_top missing_item_fields detail generated_at_ok manifest_kind kind_ok
  missing_top="$(jq -r --argjson req "$TOP_REQUIRED_JSON" '$req - keys | join(",")' "$MANIFEST")"
  missing_item_fields="$(jq -r --arg items "$ITEMS_KEY" --argjson req "$ITEM_REQUIRED_JSON" --arg keyfield "$ITEM_KEY_FIELD" '
    [ .[$items][]? |
      ( $req - keys ) as $miss
      | select(($miss | length) > 0)
      | (.[$keyfield] // "?") + ":" + ($miss | join(","))
    ] | join("; ")
  ' "$MANIFEST")"

  generated_at_ok="$(jq -r '(.generatedAt | type) == "string" and (.generatedAt | length) > 0' "$MANIFEST" 2>/dev/null || echo false)"
  manifest_kind="$(jq -r '.unitKind // empty' "$MANIFEST")"
  if [ "$UNIT_KIND" = "screen" ]; then
    # screen は unitKind 未導入の既存契約を受け入れる。ただし、値がある場合は screen に限る。
    kind_ok="$(jq -r '((has("unitKind") | not) or .unitKind == "screen")' "$MANIFEST" 2>/dev/null || echo false)"
  else
    kind_ok="$(jq -r --arg expected "$UNIT_KIND" '(.unitKind | type) == "string" and .unitKind == $expected' "$MANIFEST" 2>/dev/null || echo false)"
  fi

  if [ -n "$missing_top" ] || [ -n "$missing_item_fields" ] \
    || [ "$generated_at_ok" != "true" ] || [ "$kind_ok" != "true" ]; then
    overall_fail=1
    detail="トップレベル欠落=[${missing_top}] ${ITEMS_KEY}欠落=[${missing_item_fields}] generatedAt非空文字列=${generated_at_ok} unitKind=${manifest_kind:-\"(screen既存契約)\"}/期待=${UNIT_KIND}"
    echo "[FAIL] schema-必須フィールド — ${detail}" >&2
  else
    echo "[PASS] schema-必須フィールド — 必須キーはすべて存在" >&2
  fi

  # ---------------------------------------------------------------------------
  # 2. strategy-承認
  # ---------------------------------------------------------------------------
  local extraction_nonempty approved_true id_regex_contract_ok
  extraction_nonempty="$(jq -r '((.strategy.extractionMethod // "") | length) > 0' "$MANIFEST")"
  approved_true="$(jq -r '(.strategy.approvedByUser == true)' "$MANIFEST")"
  id_regex_contract_ok="$(jq -r --arg f "$ID_REGEX_FIELD" '(.strategy | has($f)) and ((.strategy[$f] == null) or (.strategy[$f] | type) == "string")' "$MANIFEST" 2>/dev/null || echo false)"

  if [ "$extraction_nonempty" != "true" ] || [ "$approved_true" != "true" ] || [ "$id_regex_contract_ok" != "true" ]; then
    overall_fail=1
    echo "[FAIL] strategy-承認 — extractionMethod・approvedByUser=true・${ID_REGEX_FIELD}(nullまたは文字列)が必要です" >&2
  else
    echo "[PASS] strategy-承認 — extractionMethod設定済み・approvedByUser=true・${ID_REGEX_FIELD}が契約どおり" >&2
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
  # 8. 任意フィールド-型
  #    スキーマ拡張の任意フィールドが要素に存在する場合のみ型を検査する。
  #    フィールド不在はエラーにしない(後方互換)。既存の必須キー集合には影響しない。
  #    jqがエラー終了した場合はfail-closedで即FAILとする(誤PASS防止)。
  # ---------------------------------------------------------------------------
  local type_issues type_jq_rc
  type_issues="$(jq -r --arg items "$ITEMS_KEY" --arg keyfield "$ITEM_KEY_FIELD" '
    def is_str_arr: (type == "array") and (all(.[]?; type == "string"));
    def is_safe_relative_url:
      if type != "string" then false
      else
        length > 0
        and . == gsub("^\\s+|\\s+$"; "")
        and (startswith("/") | not)
        and (startswith("\\") | not)
        and (contains("\\") | not)
        and (test("^[A-Za-z][A-Za-z0-9+.-]*:") | not)
        and ((explode | any(. < 32 or . == 127)) | not)
      end;
    [ .[$items][]? |
      (.[$keyfield] // "?") as $k
      | (
          [ ("permissions","relatedApis","callers","foreignKeys","mainColumns","targetTables","downstreamJobs") as $f
            | select(has($f) and (.[$f] != null)) | select((.[$f] | is_str_arr) | not)
            | $f + "が文字列配列でない" ]
        + [ ("authRequired","hasTemplate","isProcessingEndpoint") as $f
            | select(has($f) and (.[$f] != null)) | select((.[$f] | type) != "boolean")
            | $f + "がbooleanでない" ]
        + [ select(has("columnCount") and (.columnCount != null)) | select((.columnCount | type) != "number")
            | "columnCountが数値でない" ]
        + [ ("method","ioSummary","designDocStatus","category","format","trigger","direction","protocol","authMethod","execMethod","operationClass") as $f
            | select(has($f) and (.[$f] != null)) | select((.[$f] | type) != "string")
            | $f + "が文字列でない" ]
        + [ ("designDocPath","detailDocPath","sequencePath","testCasePath",
             "unitTestViewpointPath","integrationTestViewpointPath","integrationTestCasePath","scenarioPath") as $f
            | select(has($f) and (.[$f] != null))
            | select((.[$f] | is_safe_relative_url) | not)
            | $f + "が安全な相対URLでない" ]
        + [ select(has("schedule") and (.schedule != null))
            | select(((.schedule | type) != "object") or (((.schedule | has("cron")) and (.schedule | has("readable"))) | not))
            | "scheduleが{cron, readable}を持つobjectでない" ]
        + [ select(has("designDocStatus") and ((.designDocStatus | type) == "string"))
            | .designDocStatus as $v | select((["着手済","未着手"] | index($v)) == null)
            | "designDocStatusが2値(着手済/未着手)外" ]
        + [ select(has("trigger") and ((.trigger | type) == "string"))
            | .trigger as $v | select((["画面","バッチ"] | index($v)) == null)
            | "triggerが2値(画面/バッチ)外" ]
        + [ select(has("direction") and ((.direction | type) == "string"))
            | .direction as $v | select((["送信","受信"] | index($v)) == null)
            | "directionが2値(送信/受信)外" ]
        ) as $errs
      | select(($errs | length) > 0)
      | $k + ":" + ($errs | join(","))
    ] | join("; ")
  ' "$MANIFEST" 2>/dev/null)"
  type_jq_rc=$?

  if [ "$type_jq_rc" -ne 0 ]; then
    overall_fail=1
    echo "[FAIL] 任意フィールド-型 — jq評価エラー(rc=${type_jq_rc})。マニフェスト構造を確認してください" >&2
  elif [ -n "$type_issues" ]; then
    overall_fail=1
    echo "[FAIL] 任意フィールド-型 — 型違反: ${type_issues}" >&2
  else
    echo "[PASS] 任意フィールド-型 — 拡張任意フィールドの型違反0件" >&2
  fi

  # ---------------------------------------------------------------------------
  # 9. 名称-一意性
  #    表示名(screen: confirmedScreenName優先・無ければscreenNameGuess / screen以外: unitNameGuess)が
  #    空でない要素間で重複していないかを検査する。名称から内部識別子(モジュール接頭辞・ユニットキー併記等)を
  #    除去する改修を行うと業務名だけでは一意性が担保されなくなるため、生成・検証の両工程で機械的に検知する。
  #    任意フィールド nameScope(未指定は空文字列扱い)が要素に存在する場合、判定範囲を
  #    nameScope単位に限定する(例: 画面はサイト、バッチは配置ディレクトリ)。異なるnameScope間の
  #    同名は許容し、同一nameScope内の重複だけをFAILとする。nameScope不在の要素は全件が
  #    同一の既定スコープ("")に属するため、従来どおりマニフェスト全体で判定される(1-124)。
  # ---------------------------------------------------------------------------
  local dup_names name_label="名称-一意性"
  dup_names="$(jq -r --arg items "$ITEMS_KEY" --arg keyfield "$ITEM_KEY_FIELD" --arg kind "$UNIT_KIND" '
    def itemname:
      if $kind == "screen" then (.confirmedScreenName // .screenNameGuess // "")
      else (.unitNameGuess // "")
      end;
    [ .[$items][]? | {name: itemname, scope: (.nameScope // ""), key: (.[$keyfield] // "?")} ]
    | map(select(.name != ""))
    | group_by([.scope, .name])
    | map(select(length > 1))
    | map((if .[0].scope != "" then .[0].name + "(scope=" + .[0].scope + ")" else .[0].name end) + ":[" + (map(.key) | join(",")) + "]")
    | join("; ")
  ' "$MANIFEST" 2>/dev/null)"

  if [ -n "$dup_names" ]; then
    overall_fail=1
    echo "[FAIL] ${name_label} — 名称重複: ${dup_names}" >&2
  else
    echo "[PASS] ${name_label} — 名称重複0件" >&2
  fi

  # ---------------------------------------------------------------------------
  # 10. 実装参照-統合候補
  #     同一の実装参照(screen: entryFile / screen以外: sourceFile)を持つ要素が2件以上あるグループのうち、
  #     identifier(screen: route)がいずれも引数プレースホルダ(`:name`または`{name}`)による分岐を
  #     示していないグループを統合候補として列挙する。自動統合はしない(常にPASS。利用者判断に委ねる)。
  # ---------------------------------------------------------------------------
  local impl_ref_candidates impl_ref_label="実装参照-統合候補"
  impl_ref_candidates="$(jq -r --arg items "$ITEMS_KEY" --arg keyfield "$ITEM_KEY_FIELD" --arg idf "$IDENTIFIER_FIELD" --arg srcf "$SOURCE_FIELD" '
    def has_param: test(":[A-Za-z_][A-Za-z0-9_]*") or test("\\{[A-Za-z_][A-Za-z0-9_]*\\}");
    [ .[$items][]? | select((.[$srcf] // "") != "") | {key: (.[$keyfield] // "?"), src: .[$srcf], ident: (.[$idf] // "")} ]
    | group_by(.src)
    | map(select(length > 1))
    | map(select(all(.[]; (.ident | has_param) | not)))
    | map(.[0].src + ":[" + (map(.key) | join(",")) + "]")
    | join("; ")
  ' "$MANIFEST" 2>/dev/null)"

  if [ -n "$impl_ref_candidates" ]; then
    echo "[PASS] ${impl_ref_label} — 統合候補(自動統合はしない・利用者判断): ${impl_ref_candidates}" >&2
  else
    echo "[PASS] ${impl_ref_label} — 統合候補0件" >&2
  fi

  # ---------------------------------------------------------------------------
  # 11〜13. 分類軸の値域検査(screen専用。screen以外はskip)。
  #    値域の正本は宣言(shared/references/unit-axes.json。プロジェクト上書き可。
  #    詳細はshared/references/manifest-schema-extensions.md参照)である。
  #    宣言が解決できない場合、または該当軸のvaluesが空(壊れている)場合は、
  #    axes_closed_valuesが空文字を返すため、その軸だけハードコード値域へフォールバックする。
  #    項目数(total_items)は増やさない。screenType/accountGroup/accountSubType以外の
  #    closed/identifier軸(device等)は項目12(accountGroup-値域)にまとめて検査する。
  # ---------------------------------------------------------------------------
  local total_items=13
  if [ "$UNIT_KIND" = "screen" ]; then
    total_items=17

    local axes_json="" axes_resolved
    if axes_resolved="$(resolve_unit_axes "$MANIFEST" "${AXES_FILE:-}" 2>/dev/null)"; then
      axes_json="$(unit_axes_for_kind "$axes_resolved" "$UNIT_KIND")"
    fi

    # 11. screenType-必須+値域
    local screen_type_values_json
    screen_type_values_json="$(axes_closed_values "$axes_json" "screenType")"
    if [ -z "$screen_type_values_json" ] || [ "$screen_type_values_json" = "[]" ] || [ "$screen_type_values_json" = "null" ]; then
      screen_type_values_json='["list","detail","form","confirm","complete","error","top","processing_endpoint"]'
    fi

    local screen_type_issues
    screen_type_issues="$(jq -r --argjson allowed "$screen_type_values_json" '
      [ .screens[]? |
          (.screenKey // "?") as $k
          | (.screenType) as $st
          | if (has("screenType") | not) or ($st == null) then
              $k + ":screenType不在"
            elif ($allowed | index($st)) == null then
              $k + ":screenType=" + ($st | tostring) + "(値域外)"
            else
              empty
            end
        ] | join("; ")
    ' "$MANIFEST")"

    if [ -n "$screen_type_issues" ]; then
      overall_fail=1
      echo "[FAIL] screenType-必須+値域 — ${screen_type_issues}" >&2
    else
      echo "[PASS] screenType-必須+値域 — 全screensにscreenType存在し値域内" >&2
    fi

    # 12. accountGroup-値域
    #     accountGroup以外のclosed/identifier軸(device等。screenType/accountSubTypeを除く)は、
    #     項目数を増やさずこの項目の枠内で検査するが、[FAIL]行は違反した軸ごとに
    #     <軸キー>-値域として個別に出力する(検査名から違反軸を取り違えないようにするため)。
    #     全軸PASSの場合のみ、従来どおりaccountGroup-値域の[PASS]行を1行出す。
    local account_group_values_json account_group_values_str
    account_group_values_json="$(axes_closed_values "$axes_json" "accountGroup")"
    if [ -z "$account_group_values_json" ] || [ "$account_group_values_json" = "[]" ] || [ "$account_group_values_json" = "null" ]; then
      account_group_values_json='["user","admin","editor","report","common"]'
    fi
    account_group_values_str="$(printf '%s' "$account_group_values_json" | jq -r 'join("/")')"

    local account_group_issues
    account_group_issues="$(jq -r --argjson allowed "$account_group_values_json" '
      [ .screens[]? | select(has("accountGroup") and .accountGroup != null)
          | .accountGroup as $group
          | select(($group | type) != "string" or (($allowed | index($group)) == null))
          | (.screenKey // "?") + ":accountGroup=" + ($group | tostring) + "(値域外)"
        ] | join("; ")
    ' "$MANIFEST" 2>/dev/null)"

    local extra_axis_keys any_axis_issue=0
    extra_axis_keys="$(printf '%s' "$axes_json" | jq -r '
      .axes[]?
      | select(.key!="screenType" and .key!="accountGroup" and .key!="accountSubType")
      | select(.valuePolicy=="closed" or .valuePolicy=="identifier")
      | .key
    ' 2>/dev/null)"

    if [ -n "$account_group_issues" ]; then
      overall_fail=1
      any_axis_issue=1
      echo "[FAIL] accountGroup-値域 — ${account_group_issues}" >&2
    fi

    if [ -n "$extra_axis_keys" ]; then
      while IFS= read -r axis_key; do
        [ -z "$axis_key" ] && continue
        local axis_policy axis_values_json axis_issue
        axis_policy="$(printf '%s' "$axes_json" | jq -r --arg k "$axis_key" '.axes[]? | select(.key==$k) | .valuePolicy' 2>/dev/null)"
        if [ "$axis_policy" = "closed" ]; then
          axis_values_json="$(axes_closed_values "$axes_json" "$axis_key")"
          [ -z "$axis_values_json" ] && axis_values_json='[]'
          axis_issue="$(jq -r --arg f "$axis_key" --argjson allowed "$axis_values_json" '
            [ .screens[]? | select(has($f) and .[$f] != null)
              | .[$f] as $v
              | select(($v | type) != "string" or (($allowed | index($v)) == null))
              | (.screenKey // "?") + ":" + $f + "=" + ($v | tostring) + "(値域外)"
            ] | join("; ")
          ' "$MANIFEST" 2>/dev/null)"
        else
          axis_issue="$(jq -r --arg f "$axis_key" '
            [ .screens[]? | select(has($f) and .[$f] != null)
              | .[$f] as $v
              | select(($v | type) != "string" or ($v | test("^[A-Za-z_][A-Za-z0-9_]*$") | not))
              | (.screenKey // "?") + ":" + $f + "=" + ($v | tostring) + "(値域外)"
            ] | join("; ")
          ' "$MANIFEST" 2>/dev/null)"
        fi
        if [ -n "$axis_issue" ]; then
          overall_fail=1
          any_axis_issue=1
          echo "[FAIL] ${axis_key}-値域 — ${axis_issue}" >&2
        fi
      done <<< "$extra_axis_keys"
    fi

    if [ "$any_axis_issue" -eq 0 ]; then
      echo "[PASS] accountGroup-値域 — ${account_group_values_str}のみ" >&2
    fi

    # 13. accountSubType-値域(screen専用)
    #     detect-screens.shの抽出値はrole名(識別子形式)またはcommon/role_checkedのいずれかであり、
    #     accountGroupのような固定小集合ではないため、宣言のvaluePolicyがidentifierの場合は
    #     型と識別子形式(^[A-Za-z_][A-Za-z0-9_]*$)を検査する(既定宣言と同じ挙動)。
    local account_sub_type_policy
    account_sub_type_policy="$(printf '%s' "$axes_json" | jq -r '.axes[]? | select(.key=="accountSubType") | .valuePolicy' 2>/dev/null)"
    [ -z "$account_sub_type_policy" ] && account_sub_type_policy="identifier"

    local account_sub_type_issues
    if [ "$account_sub_type_policy" = "closed" ]; then
      local account_sub_type_values_json
      account_sub_type_values_json="$(axes_closed_values "$axes_json" "accountSubType")"
      [ -z "$account_sub_type_values_json" ] && account_sub_type_values_json='[]'
      account_sub_type_issues="$(jq -r --argjson allowed "$account_sub_type_values_json" '
        [ .screens[]? |
            (.screenKey // "?") as $k
            | if (has("accountSubType") | not) or (.accountSubType == null) then
                empty
              elif (.accountSubType | type) != "string" then
                $k + ":accountSubType=" + (.accountSubType | tostring) + "(型不正)"
              elif ($allowed | index(.accountSubType)) == null then
                $k + ":accountSubType=" + .accountSubType + "(値域外)"
              else
                empty
              end
          ] | join("; ")
      ' "$MANIFEST" 2>/dev/null)"
    else
      account_sub_type_issues="$(jq -r '
        [ .screens[]? |
            (.screenKey // "?") as $k
            | if (has("accountSubType") | not) or (.accountSubType == null) then
                empty
              elif (.accountSubType | type) != "string" then
                $k + ":accountSubType=" + (.accountSubType | tostring) + "(型不正)"
              elif (.accountSubType | test("^[A-Za-z_][A-Za-z0-9_]*$") | not) then
                $k + ":accountSubType=" + .accountSubType + "(値域外)"
              else
                empty
              end
          ] | join("; ")
      ' "$MANIFEST" 2>/dev/null)"
    fi

    if [ -n "$account_sub_type_issues" ]; then
      overall_fail=1
      echo "[FAIL] accountSubType-値域 — ${account_sub_type_issues}" >&2
    else
      echo "[PASS] accountSubType-値域 — 文字列かつ識別子形式" >&2
    fi

    # 14. parent-child参照(screen専用)
    local parent_child_issues
    parent_child_issues="$(jq -r '
      (.screens // []) as $screens
      | ($screens | map(.screenKey // "")) as $keys
      | (
          [ $screens[]
            | select(.parentScreen != null)
            | .parentScreen as $parent
            | select(($keys | index($parent)) == null)
            | (.screenKey // "?") + ":parentScreen=" + ($parent | tostring) + "が不在"
          ]
          +
          [ $screens[] as $parent
            | if ($parent | has("childComponents")) and (($parent.childComponents | type) != "array") then
                ($parent.screenKey // "?") + ":childComponentsが配列でない"
              else
                ($parent.childComponents // [])[]?
                  | if (type != "object") then
                      ($parent.screenKey // "?") + ":childComponentがobjectでない"
                    elif ((.screenKey // "") as $child | ($keys | index($child)) == null) then
                      ($parent.screenKey // "?") + ":childComponentのscreenKeyが不在"
                    elif (.componentType // "") as $component
                      | (["modal","popup","iframe"] | index($component)) == null then
                      ($parent.screenKey // "?") + ":componentTypeが値域外"
                    else empty end
              end
          ]
          +
          [ $screens[] as $parent
            | ($parent.childComponents // [] | if type == "array" then . else [] end)[]?
            | select(type == "object" and (.screenKey | type) == "string")
            | .screenKey as $child_key
            | ($screens | map(select(.screenKey == $child_key) | .parentScreen) | index($parent.screenKey)) as $has_reverse_parent
            | select($has_reverse_parent == null)
            | $parent.screenKey + ":childComponents=" + $child_key + "の子→親不一致"
          ]
          +
          [ $screens[] as $child
            | select($child.parentScreen != null)
            | ($child.parentScreen) as $parent_key
            | ($screens | map(select(.screenKey == $parent_key) | (.childComponents // [] | if type == "array" then . else [] end)[]? | select(type == "object") | .screenKey) | index($child.screenKey)) as $has_reverse_child
            | select($has_reverse_child == null)
            | $child.screenKey + ":parentScreen=" + $parent_key + "の親→子不一致"
          ]
        ) | join("; ")
    ' "$MANIFEST" 2>/dev/null)"
    if [ -n "$parent_child_issues" ]; then
      overall_fail=1
      echo "[FAIL] parent-child参照 — ${parent_child_issues}" >&2
    else
      echo "[PASS] parent-child参照 — screenKey・componentType・双方向参照が整合" >&2
    fi
  fi

  # ---------------------------------------------------------------------------
  # 15. unitKey-一意性
  #     集約キー(unitKey)の重複0件を検査する。screenの要素はunitKeyフィールドを持たないため
  #     自然にスキップされPASS扱いとなる(screen以外はITEM_KEY_FIELD=unitKeyのため実質検査される)。
  #     unitKeyを持つ要素が0件・1件の場合も重複は起こりえないためPASS扱いとする。
  # ---------------------------------------------------------------------------
  local dup_unit_keys unit_key_label="unitKey-一意性"
  dup_unit_keys="$(jq -r --arg items "$ITEMS_KEY" '
    [ .[$items][]? | select(has("unitKey") and (.unitKey != null) and ((.unitKey | type) == "string") and ((.unitKey | length) > 0)) | .unitKey ]
    | group_by(.) | map(select(length > 1) | .[0]) | join(", ")
  ' "$MANIFEST" 2>/dev/null)"

  if [ -n "$dup_unit_keys" ]; then
    overall_fail=1
    echo "[FAIL] ${unit_key_label} — 重複キー: ${dup_unit_keys}" >&2
  else
    echo "[PASS] ${unit_key_label} — unitKey重複0件(unitKey不在の要素のみの場合・0/1件の場合はスキップしPASS扱い)" >&2
  fi

  # ---------------------------------------------------------------------------
  # 16. 置換文字-非混入(1-135)
  #     マニフェスト全体(トップレベル・要素配列問わず)の全文字列値を走査し、置換文字
  #     (U+FFFD)が1件でも含まれていないかを検査する。非UTF-8原本を誤ってUTF-8として
  #     読み込んだ場合に生じる文字化けが、整合検証を無警告で通過することを防ぐ。
  #     screen/screen以外を問わず共通の検査(total_itemsを両方+1する)。
  # ---------------------------------------------------------------------------
  local replacement_issues replacement_label="置換文字-非混入"
  replacement_issues="$(jq -r '
    [ paths(scalars) as $p
      | getpath($p) as $v
      | select(($v | type) == "string")
      | ([$v | scan("�")] | length) as $cnt
      | select($cnt > 0)
      | ($p | map(tostring) | join(".")) + ":" + ($cnt | tostring) + "件"
    ] | join("; ")
  ' "$MANIFEST" 2>/dev/null)"

  if [ -n "$replacement_issues" ]; then
    overall_fail=1
    echo "[FAIL] ${replacement_label} — 置換文字(U+FFFD)混入: ${replacement_issues}" >&2
  else
    echo "[PASS] ${replacement_label} — 置換文字(U+FFFD)混入0件" >&2
  fi

  # ---------------------------------------------------------------------------
  # 17(screen)/13(screen以外). valueProvenance-値域(1-170)
  #     各要素のvalueProvenance(存在する場合のみ)について、objectの各値が
  #     measured/inferred/confirmedの3語彙のいずれかであることを検査する。
  #     nameConfidenceフィールドは既存の2値(confirmed/inferred)のままであり
  #     本検査の対象外(3値厳格検査は新規valueProvenanceにのみ適用する)。
  # ---------------------------------------------------------------------------
  local value_provenance_issues value_provenance_label="valueProvenance-値域"
  value_provenance_issues="$(jq -r --arg items "$ITEMS_KEY" --arg keyfield "$ITEM_KEY_FIELD" '
    [ .[$items][]? | select(has("valueProvenance") and (.valueProvenance != null))
      | (.[$keyfield] // .screenKey // "?") as $k
      | .valueProvenance | to_entries[]
      | . as $e
      | select((["measured","inferred","confirmed"] | index($e.value)) == null)
      | $k + ":valueProvenance." + $e.key + "=" + ($e.value | tostring) + "(値域外)"
    ] | join("; ")
  ' "$MANIFEST" 2>/dev/null)"

  if [ -n "$value_provenance_issues" ]; then
    overall_fail=1
    echo "[FAIL] ${value_provenance_label} — ${value_provenance_issues}" >&2
  else
    echo "[PASS] ${value_provenance_label} — measured/inferred/confirmedのいずれかのみ" >&2
  fi

  # ---------------------------------------------------------------------------
  if [ "$overall_fail" -eq 0 ]; then
    echo "[OK] validate-manifest: 全${total_items}項目PASS" >&2
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
      "confidence": "high",
      "screenType": "top",
      "accountGroup": "common",
      "accountSubType": "common",
      "hasTemplate": true,
      "parentScreen": null,
      "childComponents": [],
      "isProcessingEndpoint": false
    }
  ]
}
JSON

  if run_validate "$screen_pass" "" "screen" >/dev/null 2>&1; then
    echo "  [PASS] screen陽性: 既定unitKind(screen)で全15項目PASS"
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

  local screen_bad_generated_at="$tmp/screen-bad-generated-at.json"
  jq '.generatedAt = null' "$screen_pass" > "$screen_bad_generated_at"
  if run_validate "$screen_bad_generated_at" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] screen陰性: generatedAt=nullを受け入れた" >&2
    rc=1
  else
    echo "  [PASS] screen陰性: generatedAt=nullでFAIL"
  fi

  local screen_bad_kind="$tmp/screen-bad-kind.json"
  jq '.unitKind = "api"' "$screen_pass" > "$screen_bad_kind"
  if run_validate "$screen_bad_kind" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] screen陰性: unitKind=apiをscreenとして受け入れた" >&2
    rc=1
  else
    echo "  [PASS] screen陰性: unitKind=apiをscreen指定でFAIL"
  fi

  # ---- 検査9(screenType-必須+値域)の確認 ----
  local screen_missing_type="$tmp/screen-missing-type.json"
  jq '.screens[0] |= del(.screenType)' "$screen_pass" > "$screen_missing_type"
  if run_validate "$screen_missing_type" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] screenType陰性(不在): screenType不在なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] screenType陰性(不在): screenType不在でFAIL"
  fi

  local screen_bad_type="$tmp/screen-bad-type.json"
  jq '.screens[0].screenType = "invalid-value"' "$screen_pass" > "$screen_bad_type"
  if run_validate "$screen_bad_type" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] screenType陰性(値域外): screenType値域外なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] screenType陰性(値域外): screenType値域外でFAIL"
  fi

  # ---- 分類値域と親子双方向参照の確認 ----
  local screen_bad_group="$tmp/screen-bad-group.json"
  jq '.screens[0].accountGroup = "feature_phone"' "$screen_pass" > "$screen_bad_group"
  if run_validate "$screen_bad_group" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] accountGroup陰性(値域外): 無効値なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] accountGroup陰性(値域外): 無効値でFAIL"
  fi

  # ---- accountSubType-値域・hasTemplate/isProcessingEndpoint-型の確認(1-71) ----
  local screen_bad_account_sub_type="$tmp/screen-bad-account-sub-type.json"
  jq '.screens[0].accountSubType = "editor role"' "$screen_pass" > "$screen_bad_account_sub_type"
  if run_validate "$screen_bad_account_sub_type" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] accountSubType陰性(値域外): 識別子形式でない値なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] accountSubType陰性(値域外): 識別子形式でない値でFAIL"
  fi

  local screen_bad_has_template="$tmp/screen-bad-has-template.json"
  jq '.screens[0].hasTemplate = "yes"' "$screen_pass" > "$screen_bad_has_template"
  if run_validate "$screen_bad_has_template" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] hasTemplate陰性(型不正): 文字列なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] hasTemplate陰性(型不正): 文字列でFAIL"
  fi

  local screen_bad_is_processing_endpoint="$tmp/screen-bad-is-processing-endpoint.json"
  jq '.screens[0].isProcessingEndpoint = "no"' "$screen_pass" > "$screen_bad_is_processing_endpoint"
  if run_validate "$screen_bad_is_processing_endpoint" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] isProcessingEndpoint陰性(型不正): 文字列なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] isProcessingEndpoint陰性(型不正): 文字列でFAIL"
  fi

  # ---- 名称-一意性の確認(1-51) ----
  local screen_dup_name="$tmp/screen-dup-name.json"
  jq '.detectionSummary.screenCount = 2
      | .screens[0].screenNameGuess = "ホーム画面"
      | .screens += [{screenKey:"home-alt", kind:"route", route:"/home-alt", entryFile:"src/screens/Home.tsx", confidence:"high", screenType:"top", accountGroup:"common", accountSubType:"common", hasTemplate:true, parentScreen:null, childComponents:[], isProcessingEndpoint:false, screenNameGuess:"ホーム画面"}]' "$screen_pass" > "$screen_dup_name"
  if run_validate "$screen_dup_name" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] 名称-一意性陰性: screenNameGuessが重複するのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] 名称-一意性陰性: screenNameGuessの重複でFAIL"
  fi

  local screen_unique_name="$tmp/screen-unique-name.json"
  jq '.detectionSummary.screenCount = 2
      | .screens[0].screenNameGuess = "ホーム画面"
      | .screens += [{screenKey:"home-alt", kind:"route", route:"/home-alt", entryFile:"src/screens/Home.tsx", confidence:"high", screenType:"top", accountGroup:"common", accountSubType:"common", hasTemplate:true, parentScreen:null, childComponents:[], isProcessingEndpoint:false, screenNameGuess:"別画面"}]' "$screen_pass" > "$screen_unique_name"
  if run_validate "$screen_unique_name" "" "screen" >/dev/null 2>&1; then
    echo "  [PASS] 名称-一意性陽性: screenNameGuessが一意なら全項目PASS"
  else
    echo "  [FAIL] 名称-一意性陽性: 一意なscreenNameGuessがFAILした" >&2
    rc=1
  fi

  # ---- 名称-一意性のスコープ限定の確認(1-124) ----
  local screen_dup_name_diff_scope="$tmp/screen-dup-name-diff-scope.json"
  jq '.detectionSummary.screenCount = 2
      | .screens[0].screenNameGuess = "ユーザー一覧"
      | .screens[0].nameScope = "site-a"
      | .screens += [{screenKey:"home-alt", kind:"route", route:"/home-alt", entryFile:"src/screens/Home.tsx", confidence:"high", screenType:"top", accountGroup:"common", accountSubType:"common", hasTemplate:true, parentScreen:null, childComponents:[], isProcessingEndpoint:false, screenNameGuess:"ユーザー一覧", nameScope:"site-b"}]' "$screen_pass" > "$screen_dup_name_diff_scope"
  if run_validate "$screen_dup_name_diff_scope" "" "screen" >/dev/null 2>&1; then
    echo "  [PASS] 名称-一意性スコープ限定陽性: 異なるnameScope間の同名はPASS"
  else
    echo "  [FAIL] 名称-一意性スコープ限定陽性: 異なるnameScope間の同名なのにFAILした" >&2
    rc=1
  fi

  local screen_dup_name_same_scope="$tmp/screen-dup-name-same-scope.json"
  jq '.detectionSummary.screenCount = 2
      | .screens[0].screenNameGuess = "ユーザー一覧"
      | .screens[0].nameScope = "site-a"
      | .screens += [{screenKey:"home-alt", kind:"route", route:"/home-alt", entryFile:"src/screens/Home.tsx", confidence:"high", screenType:"top", accountGroup:"common", accountSubType:"common", hasTemplate:true, parentScreen:null, childComponents:[], isProcessingEndpoint:false, screenNameGuess:"ユーザー一覧", nameScope:"site-a"}]' "$screen_pass" > "$screen_dup_name_same_scope"
  if run_validate "$screen_dup_name_same_scope" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] 名称-一意性スコープ限定陰性: 同一nameScope内の同名なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] 名称-一意性スコープ限定陰性: 同一nameScope内の同名でFAIL"
  fi

  local screen_parent_child="$tmp/screen-parent-child.json"
  jq '.detectionSummary.screenCount = 2
      | .screens += [{screenKey:"home-modal", kind:"route", route:"/home/modal", entryFile:"src/screens/Home.tsx", confidence:"high", screenType:"form", accountGroup:"common", accountSubType:"common", hasTemplate:true, parentScreen:"home-screen", childComponents:[], isProcessingEndpoint:false}]
      | .screens[0].childComponents = [{screenKey:"home-modal", componentType:"modal"}]' "$screen_pass" > "$screen_parent_child"
  if run_validate "$screen_parent_child" "" "screen" >/dev/null 2>&1; then
    echo "  [PASS] parent-child陽性: 双方向参照とcomponentTypeが整合"
  else
    echo "  [FAIL] parent-child陽性: 正当な双方向参照がFAILした" >&2
    rc=1
  fi

  local screen_missing_parent_link="$tmp/screen-missing-parent-link.json"
  jq '.screens[1].parentScreen = null' "$screen_parent_child" > "$screen_missing_parent_link"
  if run_validate "$screen_missing_parent_link" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] parent-child陰性(親のみ): 子→親不一致なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] parent-child陰性(親のみ): 子→親不一致でFAIL"
  fi

  local screen_missing_child_link="$tmp/screen-missing-child-link.json"
  jq '.screens[0].childComponents = []' "$screen_parent_child" > "$screen_missing_child_link"
  if run_validate "$screen_missing_child_link" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] parent-child陰性(子のみ): 親→子不一致なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] parent-child陰性(子のみ): 親→子不一致でFAIL"
  fi

  local screen_bad_component_type="$tmp/screen-bad-component-type.json"
  jq '.screens[0].childComponents[0].componentType = "drawer"' "$screen_parent_child" > "$screen_bad_component_type"
  if run_validate "$screen_bad_component_type" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] componentType陰性(値域外): 無効値なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] componentType陰性(値域外): 無効値でFAIL"
  fi

  # ---- 設計書リンクの安全な相対URL契約 ----
  local screen_safe_doc_urls="$tmp/screen-safe-doc-urls.json"
  jq '.screens[0] += {
        designDocPath: "../../画面/home/基本設計.html",
        detailDocPath: "../../画面/home/詳細設計.html",
        sequencePath: "../../画面/home/シーケンス図.html",
        testCasePath: "../../画面/home/テスト仕様書.html",
        unitTestViewpointPath: "../../画面/home/単体テスト観点表.html",
        integrationTestViewpointPath: "../../画面/home/結合テスト観点表.html",
        integrationTestCasePath: "../../画面/home/結合テスト仕様書.html",
        scenarioPath: "../../画面/home/操作シナリオ仕様書.html"
      }' "$screen_pass" > "$screen_safe_doc_urls"
  if run_validate "$screen_safe_doc_urls" "" "screen" >/dev/null 2>&1; then
    echo "  [PASS] 設計書URL陽性: 安全な相対URLを受け入れる"
  else
    echo "  [FAIL] 設計書URL陽性: 安全な相対URLを拒否した" >&2
    rc=1
  fi

  local screen_bad_doc_urls="$tmp/screen-bad-doc-urls.json"
  jq '.screens[0] += {
        designDocPath: "javascript:alert(1)",
        detailDocPath: "https://attacker.invalid/doc.html",
        sequencePath: "//attacker.invalid/sequence.html",
        unitTestViewpointPath: "javascript:alert(2)",
        integrationTestViewpointPath: "https://attacker.invalid/viewpoint.html",
        integrationTestCasePath: "//attacker.invalid/integration.html",
        scenarioPath: "/absolute/scenario.html",
        testCasePath: "unsafe\u000aurl.html"
      }' "$screen_pass" > "$screen_bad_doc_urls"
  if run_validate "$screen_bad_doc_urls" "" "screen" >/dev/null 2>&1; then
    echo "  [FAIL] 設計書URL陰性: scheme・//・制御文字を含むURLを受け入れた" >&2
    rc=1
  else
    echo "  [PASS] 設計書URL陰性: scheme・//・制御文字を含むURLをFAIL"
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
    echo "  [PASS] api陽性: unitKind=apiで全11項目PASS"
  else
    echo "  [FAIL] api陽性: 正当なapiマニフェストがFAILした" >&2
    rc=1
  fi

  # ---- 検査15(unitKey-一意性)の確認 ----
  local api_dup_unit_key="$tmp/api-dup-unit-key.json"
  jq '.units[1].unitKey = "users-list"' "$api_pass" > "$api_dup_unit_key"
  local dup_unit_key_output
  dup_unit_key_output="$(run_validate "$api_dup_unit_key" "" "api" 2>&1)"
  if echo "$dup_unit_key_output" | grep -q '\[FAIL\] unitKey-一意性.*users-list'; then
    echo "  [PASS] unitKey-一意性陰性: unitKeyの重複でFAIL"
  else
    echo "  [FAIL] unitKey-一意性陰性: unitKeyが重複するのにPASSした(またはFAIL文言不一致)" >&2
    rc=1
  fi

  local api_unique_unit_key="$tmp/api-unique-unit-key.json"
  cp "$api_pass" "$api_unique_unit_key"
  local unique_unit_key_output
  unique_unit_key_output="$(run_validate "$api_unique_unit_key" "" "api" 2>&1)"
  if echo "$unique_unit_key_output" | grep -q '\[PASS\] unitKey-一意性'; then
    echo "  [PASS] unitKey-一意性陽性: unitKeyが一意なら重複なしでPASS"
  else
    echo "  [FAIL] unitKey-一意性陽性: 一意なunitKeyがFAILした" >&2
    rc=1
  fi

  local api_bad_kind="$tmp/api-bad-kind.json"
  jq '.unitKind = "table"' "$api_pass" > "$api_bad_kind"
  if run_validate "$api_bad_kind" "" "api" >/dev/null 2>&1; then
    echo "  [FAIL] api陰性: unitKind=tableをapiとして受け入れた" >&2
    rc=1
  else
    echo "  [PASS] api陰性: unitKind=tableをapi指定でFAIL"
  fi

  local api_bad_generated_at="$tmp/api-bad-generated-at.json"
  jq '.generatedAt = ""' "$api_pass" > "$api_bad_generated_at"
  if run_validate "$api_bad_generated_at" "" "api" >/dev/null 2>&1; then
    echo "  [FAIL] api陰性: generatedAt空文字を受け入れた" >&2
    rc=1
  else
    echo "  [PASS] api陰性: generatedAt空文字でFAIL"
  fi

  local api_missing_id_regex="$tmp/api-missing-id-regex.json"
  jq 'del(.strategy.unitIdRegex)' "$api_pass" > "$api_missing_id_regex"
  if run_validate "$api_missing_id_regex" "" "api" >/dev/null 2>&1; then
    echo "  [FAIL] api陰性: strategy.unitIdRegex欠落を受け入れた" >&2
    rc=1
  else
    echo "  [PASS] api陰性: strategy.unitIdRegex欠落でFAIL"
  fi

  local api_bad_id_regex="$tmp/api-bad-id-regex.json"
  jq '.strategy.unitIdRegex = 1' "$api_pass" > "$api_bad_id_regex"
  if run_validate "$api_bad_id_regex" "" "api" >/dev/null 2>&1; then
    echo "  [FAIL] api陰性: strategy.unitIdRegex数値を受け入れた" >&2
    rc=1
  else
    echo "  [PASS] api陰性: strategy.unitIdRegex数値でFAIL"
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

  # ---- 検査8(任意フィールド-型)の確認 ----
  # 正常系: スキーマ拡張の任意フィールド(正しい型)を付与してもPASSのまま
  local api_ext_pass="$tmp/api-ext-pass.json"
  jq '.units[0] += {
        "method": "GET",
        "authRequired": true,
        "callers": ["home-screen"],
        "ioSummary": "ユーザー一覧を返す"
      }' "$api_pass" > "$api_ext_pass"
  if run_validate "$api_ext_pass" "" "api" >/dev/null 2>&1; then
    echo "  [PASS] 拡張フィールド陽性: 正しい型の任意フィールド付きでも全11項目PASS"
  else
    echo "  [FAIL] 拡張フィールド陽性: 正しい型の任意フィールドがFAILした" >&2
    rc=1
  fi

  # 型違反系: authRequiredが文字列・callersが文字列配列でない場合はFAIL
  local api_ext_bad="$tmp/api-ext-bad.json"
  jq '.units[0] += {"authRequired": "yes", "callers": [1, 2]}' "$api_pass" > "$api_ext_bad"
  if run_validate "$api_ext_bad" "" "api" >/dev/null 2>&1; then
    echo "  [FAIL] 拡張フィールド陰性: 型違反(authRequired文字列/callers数値配列)なのにPASSした" >&2
    rc=1
  else
    echo "  [PASS] 拡張フィールド陰性: 型違反でFAIL"
  fi

  # null陽性系: 任意フィールドが明示的nullを持つユニットで型検査がエラーにならないこと
  local api_ext_null="$tmp/api-ext-null.json"
  jq '.units[0] += {"category": null, "authRequired": null, "columnCount": null}' "$api_pass" > "$api_ext_null"
  if run_validate "$api_ext_null" "" "api" >/dev/null 2>&1; then
    echo "  [PASS] 拡張フィールドnull陽性: 任意フィールドが明示的nullでも全11項目PASS"
  else
    echo "  [FAIL] 拡張フィールドnull陽性: 任意フィールドの明示的nullがFAILした" >&2
    rc=1
  fi

  # ---- 検査10(実装参照-統合候補)の確認(1-54) ----
  # 分岐なしペア(同一sourceFileを引数プレースホルダなしの異なるidentifierで参照)は統合候補として列挙し、
  # 分岐ありペア(users-list/users-detailは同一sourceFileだが:idで分岐)は列挙しないことを確認する。
  cat > "$tmp/api-src/routes/legacy.ts" <<'EOF'
export function legacyUsers() {}
EOF

  local impl_ref_manifest="$tmp/impl-ref.json"
  jq --arg legacy "$tmp/api-src/routes/legacy.ts" --arg users "$tmp/api-src/routes/users.ts" '
    .units = [
      {unitKey:"legacy-portal-x", kind:"endpoint", identifier:"GET /portal-x/users", sourceFile:$legacy, confidence:"high"},
      {unitKey:"legacy-portal-y", kind:"endpoint", identifier:"GET /portal-y/users", sourceFile:$legacy, confidence:"high"},
      {unitKey:"users-list", kind:"endpoint", identifier:"GET /api/users", sourceFile:$users, confidence:"high"},
      {unitKey:"users-detail", kind:"endpoint", identifier:"GET /api/users/:id", sourceFile:$users, confidence:"high"}
    ]
    | .detectionSummary.unitCount = 4
    | .detectionSummary.unresolvedCount = 0
  ' "$api_pass" > "$impl_ref_manifest"

  local impl_ref_output
  impl_ref_output="$(run_validate "$impl_ref_manifest" "" "api" 2>&1)"
  if echo "$impl_ref_output" | grep -q '実装参照-統合候補.*legacy-portal-x,legacy-portal-y' \
    && ! echo "$impl_ref_output" | grep -q 'users-list,users-detail'; then
    echo "  [PASS] 実装参照-統合候補: 分岐なしペアのみ列挙し引数分岐ペアは列挙しない"
  else
    echo "  [FAIL] 実装参照-統合候補: 期待どおりの列挙にならなかった" >&2
    echo "$impl_ref_output" | grep '実装参照-統合候補' >&2
    rc=1
  fi

  # ---- 検査16(置換文字-非混入)の確認(1-135) ----
  # 陰性: 置換文字(U+FFFD)を含む合成マニフェストでexit 1になり、件数が列挙されること
  local api_replacement_char="$tmp/api-replacement-char.json"
  jq '.units[0].unitNameGuess = "利用者一覧�"' "$api_pass" > "$api_replacement_char"
  local replacement_char_output
  replacement_char_output="$(run_validate "$api_replacement_char" "" "api" 2>&1)"
  if run_validate "$api_replacement_char" "" "api" >/dev/null 2>&1; then
    echo "  [FAIL] 置換文字-非混入陰性: 置換文字を含むのにPASSした" >&2
    rc=1
  elif echo "$replacement_char_output" | grep -q '\[FAIL\] 置換文字-非混入.*1件'; then
    echo "  [PASS] 置換文字-非混入陰性: 置換文字混入でFAILし件数が列挙される"
  else
    echo "  [FAIL] 置換文字-非混入陰性: FAILしたが件数が出力に含まれない" >&2
    echo "$replacement_char_output" | grep '置換文字-非混入' >&2
    rc=1
  fi

  # 陽性: 置換文字を含まない合成マニフェストでは従来どおり通過すること
  if run_validate "$api_pass" "" "api" >/dev/null 2>&1; then
    echo "  [PASS] 置換文字-非混入陽性: 置換文字を含まないマニフェストは従来どおりPASS"
  else
    echo "  [FAIL] 置換文字-非混入陽性: 置換文字を含まないのにFAILした" >&2
    rc=1
  fi

  # ---- 検査(valueProvenance-値域)の確認(1-170) ----
  # 陽性: measured/inferred/confirmedの3値のみを持つマニフェストはPASSすること
  local vp_pass="$tmp/api-value-provenance-pass.json"
  jq '.units[0].valueProvenance = {permissions: "measured"}
      | .units[1].valueProvenance = {schedule: "inferred", relatedField: "confirmed"}' \
    "$api_pass" > "$vp_pass"
  if run_validate "$vp_pass" "" "api" >/dev/null 2>&1; then
    echo "  [PASS] valueProvenance-値域陽性: measured/inferred/confirmedのみならPASS"
  else
    echo "  [FAIL] valueProvenance-値域陽性: 正しい3値のみなのにFAILした" >&2
    rc=1
  fi

  # 陰性: 値域外の値を含むマニフェストはFAILし、該当キーが列挙されること
  local vp_fail="$tmp/api-value-provenance-fail.json"
  jq '.units[0].valueProvenance = {permissions: "guessed"}' "$api_pass" > "$vp_fail"
  local vp_fail_output
  vp_fail_output="$(run_validate "$vp_fail" "" "api" 2>&1)"
  if run_validate "$vp_fail" "" "api" >/dev/null 2>&1; then
    echo "  [FAIL] valueProvenance-値域陰性: 値域外の値を含むのにPASSした" >&2
    rc=1
  elif echo "$vp_fail_output" | grep -q '\[FAIL\] valueProvenance-値域.*valueProvenance\.permissions=guessed'; then
    echo "  [PASS] valueProvenance-値域陰性: 値域外の値でFAILし該当キーが列挙される"
  else
    echo "  [FAIL] valueProvenance-値域陰性: FAILしたが該当キーが出力に含まれない" >&2
    echo "$vp_fail_output" | grep 'valueProvenance-値域' >&2
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
AXES_FILE=""
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
    --axes)
      AXES_FILE="${2:-}"
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
