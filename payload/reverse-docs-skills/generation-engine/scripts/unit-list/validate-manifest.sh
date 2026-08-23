#!/usr/bin/env bash
# 種別別一覧スキル群(generating-<種別>-list-for-reverse-docs)共通エンジン: ユニットマニフェスト(screen-manifest.json 等)の独立検証(7項目)。
# 抽出元(組み込みスクリプト/Claude手書き)・ユニット種別(screen/api/table/batch/report/external)を
# 問わずマニフェスト品質を機械保証する。unit_kind=screen(デフォルト)の場合は従来と完全に同じ
# 出力・挙動を保証する。
#
# Usage: validate-manifest.sh <manifest.json> [--fix <fixed-out.json>] [--unit-kind <kind>] [--axes <file>]
#                              [--migrations-dir <dir>] [--repo-root <path>]
#        validate-manifest.sh --self-test
#
# --axes <file> は分類軸・任意列の宣言ファイルを受理する(現時点では受理するのみで検査には未使用)。
#
# --migrations-dir <dir> は unit_kind=table のときだけ意味を持つ。指定すると、検証対象マニフェスト
# を extract-table-metadata.sh で同じ migrations-dir から再計算し、再計算値と検証対象マニフェストの
# columnCount/mainColumns/foreignKeys が一致するかを追加検査する(項目「table-メタデータ-履歴突き合わせ」)。
# unit_kind!=table、または本オプション未指定の場合は当該検査をスキップしPASS扱いとする。
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
#                                  (unit_kind=messageのみ例外でapprovedByUser == falseを要求する。
#                                   定義書からの機械的な転記で人間承認の工程が無いため。1-17)
#   3. 重複-route+entryFile     : (route, entryFile) 組の重複0件
#                                  (screen以外は (identifier, sourceFile) 組の重複0件)
#   4. entryFile-実在           : kind=route/embedded-view の entryFile がファイルとして実在するか
#                                  (screen以外は kind!=unresolved の sourceFile が実在するかを検査。
#                                   sourceDirが相対パスの場合はマニフェストファイル自身の所在
#                                   ディレクトリを基準に解決する(1-10)。
#                                   strategy.sourceExternal=trueの場合は対象コードが別リポジトリに
#                                   あり参照できない宣言として実在確認自体を省略しPASS扱い(1-18)。
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
#   8. 任意フィールド-型         : スキーマ拡張(delivery-payload/references/manifest-schema-extensions.md
#                                   「種別ごとの追加フィールド定義」が正本)の任意フィールドが要素に
#                                   存在する場合のみ型を検査する(不在はエラーにしない。後方互換):
#                                   - 文字列配列: permissions/confirmedPermissions/relatedApis/callers/
#                                     foreignKeys/mainColumns/targetTables/downstreamJobs
#                                   - boolean: authRequired/hasTemplate/isProcessingEndpoint/triggerConfirmed
#                                     / 数値: columnCount/retryCount
#                                   - 文字列: method/ioSummary/designDocStatus/category/format/
#                                     trigger/direction/protocol/authMethod/execMethod/operationClass/
#                                     businessClass/responseTimeout
#                                   - object({cron, readable}を持つ): schedule/confirmedSchedule
#                                   - 2値制約: designDocStatus(着手済/未着手)・trigger(画面/バッチ)・
#                                     direction(送信/受信)
#   8.5 kind-値域(1-9)          : kindは業務区分ではなく検証器の制御フィールド(項目4の絞り込み等に
#                                   使う技術的な種類)である。table/api/batch/external/reportの5種別は
#                                   各*-detection.mdが規約する固定小集合(例: table は
#                                   table/view/migration/unresolved)の値域外をFAILする。
#                                   screen/feature/message等は対象外でスキップしPASS扱い
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
#  18(screen)/14(screen以外). table-メタデータ-履歴突き合わせ : unit_kind=table かつ --migrations-dir
#                                   指定時のみ実行する。extract-table-metadata.sh を同じ migrations-dir
#                                   で再実行し、columnCount/mainColumns/foreignKeys が検証対象マニフェスト
#                                   の値と一致するかを検査する。unit_kind!=table または未指定時はスキップ
#                                   しPASS扱い(screen/screen以外を問わず共通の1項目としてtotal_itemsを
#                                   両方+1する)
#
# 全項目(total_itemsを参照。screen: 19項目 / screen以外: 15項目)PASSでexit 0。1件でもFAILがあれば
# exit 1(--fixで解消された項目4はPASS扱い。項目10は常にPASSする情報列挙)。

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
# shellcheck source=../output-layout.sh
. "$SCRIPT_DIR/../output-layout.sh"
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
  local MIGRATIONS_DIR="${4:-}"
  local REPO_ROOT="${5:-}"

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
  #    approvedByUserの期待値はunit_kindで切り替える(1-17)。screen/api/table/batch/report/
  #    external/featureは検出戦略をAskUserQuestionで人間が承認する工程を経るためtrueを要求する。
  #    messageは定義書からの機械的な転記(convert-message-doc-to-manifest.sh)であり人間承認の
  #    工程が無いため、その事実をfalseとして正直に記録することを要求する(専用検証器
  #    validate-message-manifest.shの要求と統一する)。
  # ---------------------------------------------------------------------------
  local extraction_nonempty approved_ok id_regex_contract_ok expected_approved_label expected_approved_query
  extraction_nonempty="$(jq -r '((.strategy.extractionMethod // "") | length) > 0' "$MANIFEST")"
  if [ "$UNIT_KIND" = "message" ]; then
    expected_approved_label="false(機械的な転記のため人間承認の工程が無い)"
    expected_approved_query='(.strategy.approvedByUser == false)'
  else
    expected_approved_label="true"
    expected_approved_query='(.strategy.approvedByUser == true)'
  fi
  approved_ok="$(jq -r "$expected_approved_query" "$MANIFEST")"
  id_regex_contract_ok="$(jq -r --arg f "$ID_REGEX_FIELD" '(.strategy | has($f)) and ((.strategy[$f] == null) or (.strategy[$f] | type) == "string")' "$MANIFEST" 2>/dev/null || echo false)"

  if [ "$extraction_nonempty" != "true" ] || [ "$approved_ok" != "true" ] || [ "$id_regex_contract_ok" != "true" ]; then
    overall_fail=1
    echo "[FAIL] strategy-承認 — extractionMethod・approvedByUser=${expected_approved_label}・${ID_REGEX_FIELD}(nullまたは文字列)が必要です" >&2
  else
    echo "[PASS] strategy-承認 — extractionMethod設定済み・approvedByUser=${expected_approved_label}・${ID_REGEX_FIELD}が契約どおり" >&2
  fi

  # ---------------------------------------------------------------------------
  # 3. 重複-<identifier>+<source> (screen: route+entryFile / screen以外: identifier+sourceFile)
  # ---------------------------------------------------------------------------
  local dup_list dup_label
  dup_label="重複-${IDENTIFIER_FIELD}+${SOURCE_FIELD}"
  # 出典ファイルは種別により文字列と配列の両方がありうる。配列の場合は要素を
  # つないだ文字列にしてから重複判定のキーへ含める。文字列前提のまま連結すると
  # jq がエラーで終了し、重複を検出できないまま素通りする。
  dup_list="$(jq -r --arg items "$ITEMS_KEY" --arg idf "$IDENTIFIER_FIELD" --arg srcf "$SOURCE_FIELD" '
    [ .[$items][]? | (.[$idf] // "") + "|" + (if (.[$srcf] | type) == "array" then (.[$srcf] | join(",")) else (.[$srcf] // "") end) ]
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
  #    sourceDirが相対パスの場合、解決の基準は対象リポジトリのルートとする。マニフェストの
  #    所在ディレクトリから上へ辿り、最初に .git を持つディレクトリ、または配布物の境界目印
  #    （generation-engine/DESIGN.md。理由は下記）を持つディレクトリをルートとみなす。見つから
  #    ない場合はマニフェスト自身の所在ディレクトリを基準にする(呼び出し元のカレントディレクトリには
  #    依存しない。改善課題: マニフェストが対象リポジトリの外(一時ディレクトリ等)にあり.git祖先が
  #    見つからない場合、以前は呼び出し元のカレントディレクトリへフォールバックしていたため、同じ
  #    引数でも実行時のカレントディレクトリ次第で合否が変わっていた)。sourceDirが絶対パスの場合は
  #    従来どおりsourceDirをそのまま基準にする。
  #    マニフェスト自身の所在ディレクトリを基準にすると、sourceDirを対象リポジトリのルート
  #    起点で書く既存の書式が二重に連結されて解決に失敗する。
  #    strategy.sourceExternal=trueの場合、対象コードが別リポジトリにあり参照できないことの
  #    宣言として扱い、実在確認そのものを省略してPASS扱いで記録だけ残す(1-18)。
  #
  #    配布物の境界目印について(docs/tasks/配布先で自己テストが通るようにする指示書.md 3.1):
  #    配布物(このリポジトリ)が公開リポジトリや対象プロジェクトの中へ一区画として
  #    埋め込まれると、埋め込み先には配布物自身の .git が無いため、.git 祖先探索が配布物の
  #    境界を越えて外側のリポジトリへ到達し、配布物自身のルート起点で書かれたsourceDir
  #    (generation-engine/samples 配下の見本マニフェスト)の解決に失敗する。
  #    generation-engine/DESIGN.md は次の理由で境界目印に採用する。
  #      - 配布物に必ず含まれる(公開の同期対象に generation-engine 一式が含まれる)
  #      - 対象プロジェクトが偶然同じ組み合わせ(直下の generation-engine ディレクトリの中に
  #        DESIGN.md というファイル)を持つ可能性は極めて低い
  #      - 配布物の一番上の階層(リポジトリ直下の generation-engine)に置かれている
  #    実利用(対象プロジェクトの docs 配下に置かれる実マニフェスト)では、この目印は
  #    祖先のどこにも現れないため、従来どおり対象プロジェクト自身の .git で止まる。
  # ---------------------------------------------------------------------------
  local source_dir check4_label manifest_dir resolve_base probe source_external
  source_dir="$(jq -r '.sourceDir // ""' "$MANIFEST")"
  check4_label="${SOURCE_FIELD}-実在"
  manifest_dir="$(cd "$(dirname "$MANIFEST")" && pwd)"
  if [ -n "$REPO_ROOT" ]; then
    resolve_base="$REPO_ROOT"
  else
    resolve_base=""
    probe="$manifest_dir"
    while [ -n "$probe" ] && [ "$probe" != "/" ]; do
      if [ -e "$probe/.git" ] || [ -f "$probe/generation-engine/DESIGN.md" ]; then
        resolve_base="$probe"
        break
      fi
      probe="$(dirname "$probe")"
    done
  fi
  # 呼び出し元のカレントディレクトリ($PWD)には依存しない。.git祖先が見つからない場合は
  # マニフェスト自身の所在ディレクトリ(manifest_dir。$MANIFESTの絶対パスから一意に決まり、
  # 実行時のカレントディレクトリには依存しない)を基準にする。
  [ -z "$resolve_base" ] && resolve_base="$manifest_dir"
  source_external="$(jq -r '(.strategy.sourceExternal == true)' "$MANIFEST" 2>/dev/null || echo false)"

  local missing_keys_raw="" missing_detail="" row key ef path ef_list row_missing
  if [ "$source_external" = "true" ]; then
    echo "[PASS] ${check4_label} — strategy.sourceExternal=trueのため実在確認を省略(対象コードは別リポジトリにあり参照不可という宣言を記録)" >&2
  else
    while IFS= read -r row; do
      [ -z "$row" ] && continue
      key="$(jq -r --arg f "$ITEM_KEY_FIELD" '.[$f] // "?"' <<<"$row")"
      # 出典ファイルは種別により単一の文字列と文字列の配列の両方がありうる。
      # 生成エンジン（build-unit-list.sh）も両方を分岐して扱うため、検証も両方を受け付ける。
      # 配列なら各要素を、文字列なら1件を、それぞれ1行ずつ取り出して実在を確かめる。
      ef_list="$(jq -r --arg f "$SOURCE_FIELD" '(.[$f] // "") | if type == "array" then .[] else . end' <<<"$row")"
      if [ -z "$ef_list" ]; then
        missing_keys_raw="${missing_keys_raw}${key}
"
        missing_detail="${missing_detail}${key}:(empty ${SOURCE_FIELD}); "
        continue
      fi
      row_missing=0
      while IFS= read -r ef; do
        [ -z "$ef" ] && continue
        case "$ef" in
          /*) path="$ef" ;;
          *)
            case "$source_dir" in
              /*) path="${source_dir%/}/$ef" ;;
              "") path="${resolve_base%/}/$ef" ;;
              *) path="${resolve_base%/}/${source_dir%/}/$ef" ;;
            esac
            ;;
        esac
        if [ ! -f "$path" ]; then
          row_missing=1
          missing_detail="${missing_detail}${key}:${ef} (解決後: ${path}); "
        fi
      done <<<"$ef_list"
      if [ "$row_missing" -eq 1 ]; then
        missing_keys_raw="${missing_keys_raw}${key}
"
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
          [ ("permissions","confirmedPermissions","relatedApis","callers","foreignKeys","mainColumns","targetTables","downstreamJobs") as $f
            | select(has($f) and (.[$f] != null)) | select((.[$f] | is_str_arr) | not)
            | $f + "が文字列配列でない" ]
        + [ ("authRequired","hasTemplate","isProcessingEndpoint","triggerConfirmed") as $f
            | select(has($f) and (.[$f] != null)) | select((.[$f] | type) != "boolean")
            | $f + "がbooleanでない" ]
        + [ ("columnCount") as $f
            | select(has($f) and (.[$f] != null)) | select((.[$f] | type) != "number")
            | $f + "が数値でない" ]
        + [ select(has("retryCount") and (.retryCount != null))
            | select(((.retryCount | type) != "number") and (.retryCount != "未確認"))
            | "retryCountが数値、または文字列\"未確認\"でない" ]
        + [ ("method","ioSummary","designDocStatus","category","format","trigger","direction","protocol","authMethod","execMethod","operationClass","businessClass","responseTimeout") as $f
            | select(has($f) and (.[$f] != null)) | select((.[$f] | type) != "string")
            | $f + "が文字列でない" ]
        + [ ("designDocPath","detailDocPath","sequencePath","testCasePath",
             "unitTestViewpointPath","integrationTestViewpointPath","integrationTestCasePath","scenarioPath","confirmationPath") as $f
            | select(has($f) and (.[$f] != null))
            | select((.[$f] | is_safe_relative_url) | not)
            | $f + "が安全な相対URLでない" ]
        + [ select(has("schedule") and (.schedule != null))
            | select(((.schedule | type) != "object") or (((.schedule | has("cron")) and (.schedule | has("readable"))) | not))
            | "scheduleが{cron, readable}を持つobjectでない" ]
        + [ select(has("confirmedSchedule") and (.confirmedSchedule != null))
            | select(((.confirmedSchedule | type) != "object") or (((.confirmedSchedule | has("cron")) and (.confirmedSchedule | has("readable"))) | not))
            | "confirmedScheduleが{cron, readable}を持つobjectでない" ]
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
  # 8.5. kind-値域(1-9)
  #    kindは検証器の制御フィールド(項目4のentryFile/sourceFile実在検査の絞り込み等に使う
  #    技術的な種類)であり、業務区分(マスタ/トランザクション等)を混入させると項目4の
  #    unresolved除外が機能しなくなる。値域は各generating-<種別>-list-for-reverse-docsの
  #    検出手順書(*-detection.md)が規約する固定小集合であり、宣言ファイル(unit-axes.json)には
  #    置かない(1つのkeyに対し種別ごとに異なる値域を持たせられないため。同じ理由で
  #    businessClass等の業務区分は別フィールドへ分離し、kindの値域はここで直接検査する)。
  #    対象外のunit_kind(screen/feature/message等)はスキップしPASS扱いとする。
  # ---------------------------------------------------------------------------
  local kind_domain_issues kind_domain_label="kind-値域"
  if [ "$UNIT_KIND" = "screen" ]; then
    : # screenはscreens[].kindの値域を検査対象としない(route/embedded-view/unresolved等は別観点)
    echo "[PASS] ${kind_domain_label} — screenは対象外のためスキップ" >&2
  else
    kind_domain_issues="$(jq -r --arg items "$ITEMS_KEY" --arg keyfield "$ITEM_KEY_FIELD" --arg kind "$UNIT_KIND" '
      def kind_allowed:
        {
          "table":    ["table","view","migration","unresolved"],
          "api":      ["endpoint","entrypoint","dispatch-entry","exported-function","middleware","unresolved"],
          "batch":    ["scheduled","triggered","unresolved"],
          "external": ["client","webhook","unresolved"],
          "report":   ["template","generator","unresolved"]
        };
      (kind_allowed[$kind]) as $allowed
      | if $allowed == null then []
        else
          [ .[$items][]? |
            (.[$keyfield] // "?") as $k
            | (.kind // "") as $v
            | select(($allowed | index($v)) == null)
            | $k + ":kind=" + $v + "(値域外)"
          ]
        end
      | join("; ")
    ' "$MANIFEST" 2>/dev/null)"

    if [ -n "$kind_domain_issues" ]; then
      overall_fail=1
      echo "[FAIL] ${kind_domain_label} — ${kind_domain_issues}" >&2
    else
      case "$UNIT_KIND" in
        table|api|batch|external|report)
          echo "[PASS] ${kind_domain_label} — 全kindが規約値域内" >&2
          ;;
        *)
          echo "[PASS] ${kind_domain_label} — unit_kind=${UNIT_KIND}は値域検査の対象外のためスキップ" >&2
          ;;
      esac
    fi
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
  #    値域の正本は宣言(delivery-payload/references/unit-axes.json。プロジェクト上書き可。
  #    詳細はdelivery-payload/references/manifest-schema-extensions.md参照)である。
  #    宣言が解決できない場合、または該当軸のvaluesが空(壊れている)場合は、
  #    axes_closed_valuesが空文字を返すため、その軸だけハードコード値域へフォールバックする。
  #    項目数(total_items)は増やさない。screenType/accountGroup/accountSubType以外の
  #    closed/identifier軸(device等)は項目12(accountGroup-値域)にまとめて検査する。
  # ---------------------------------------------------------------------------
  local total_items=15
  if [ "$UNIT_KIND" = "screen" ]; then
    total_items=19

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
  # 18(screen)/14(screen以外). table-メタデータ-履歴突き合わせ
  #     改善課題「マニフェスト検証-履歴を突き合わせない」への対応。unit_kind=table かつ
  #     --migrations-dir 指定時のみ実行する。extract-table-metadata.sh を同じ migrations-dir
  #     で再実行し、再計算した columnCount/mainColumns/foreignKeys が検証対象マニフェストの
  #     値と一致するかを検査する。マイグレーション履歴に追随しない抽出結果(列数の未追随・
  #     外部キーの過不足・列名誤読)は、この検査を経由しない限り他の13項目のどれにも
  #     引っかからず素通りしていた。unit_kind!=table または --migrations-dir 未指定の場合は
  #     対象外としてスキップしPASS扱いとする。
  #     既知の限界: 本検査は extract-table-metadata.sh を再実行した結果と検証対象マニフェストの
  #     突き合わせであり、両者の一致は「検証対象マニフェストが最新の抽出結果と一致している」ことの
  #     証明にしかならない。extract-table-metadata.sh 自体の抽出ロジックが誤っている場合、
  #     再計算値も検証対象マニフェストと同じ誤りを含みうるため本検査は一致でPASSしてしまう
  #     (抽出エンジンの正しさそのものは extract-table-metadata.sh --self-test が担保する)。
  # ---------------------------------------------------------------------------
  local table_history_label="table-メタデータ-履歴突き合わせ"
  if [ "$UNIT_KIND" != "table" ] || [ -z "$MIGRATIONS_DIR" ]; then
    echo "[PASS] ${table_history_label} — unit_kind!=tableまたは--migrations-dir未指定のためスキップ" >&2
  else
    local extract_script recompute_out table_history_issues table_history_rc _recompute_out_base
    extract_script="$SCRIPT_DIR/../extract/extract-table-metadata.sh"
    if [ ! -e "$MIGRATIONS_DIR" ]; then
      overall_fail=1
      echo "[FAIL] ${table_history_label} — migrations-dirが実在しません: ${MIGRATIONS_DIR}" >&2
    elif [ ! -f "$extract_script" ]; then
      overall_fail=1
      echo "[FAIL] ${table_history_label} — extract-table-metadata.shが見つかりません: ${extract_script}" >&2
    else
      # mktempのテンプレートへ直接".json"を後置する形(XXXXXX.json)は乱数展開が
      # 効かない環境があり、コミット93eb2d6793dd30f0ae8320b372c823177c8f301c
      # 「一時ファイル名の乱数展開を効かせる」で拡張子なしのmktemp+mvの2段へ改めた。
      # 単純化して1回のmktempへ戻すな。
      _recompute_out_base="$(mktemp "${TMPDIR:-/tmp}/validate-manifest-table-history.XXXXXX")"
      recompute_out="${_recompute_out_base}.json"
      mv "$_recompute_out_base" "$recompute_out"
      local _table_history_extract_out
      if ! _table_history_extract_out="$(bash "$extract_script" "$MANIFEST" "$MIGRATIONS_DIR" "$recompute_out" 2>&1)"; then
        overall_fail=1
        echo "[FAIL] ${table_history_label} — extract-table-metadata.shの再実行に失敗しました" >&2
        printf '%s\n' "$_table_history_extract_out" | sed 's/^/    /' >&2
      else
        table_history_issues="$(jq -rs --arg items "$ITEMS_KEY" --arg keyfield "$ITEM_KEY_FIELD" '
          (.[0][$items]) as $orig
          | (.[1][$items]) as $recalced
          | [ $orig[]? | select(.kind != "unresolved") | . as $o
              | ($o | .[$keyfield]) as $k
              | (($recalced[]? | select((.[$keyfield]) == $k)) // null) as $r
              | ["columnCount","mainColumns","foreignKeys"][] as $field
              | ($o | .[$field]) as $ov
              | (if $r == null then null else ($r | .[$field]) end) as $rv
              | select($ov != $rv)
              | ($k + "." + $field + ": manifest=" + ($ov | tostring) + " 再計算=" + ($rv | tostring))
          ] | join("; ")
        ' "$MANIFEST" "$recompute_out" 2>/dev/null)"
        table_history_rc=$?
        rm -f "$recompute_out"
        if [ "$table_history_rc" -ne 0 ]; then
          overall_fail=1
          echo "[FAIL] ${table_history_label} — jq評価エラー(rc=${table_history_rc})。マニフェスト構造を確認してください" >&2
        elif [ -n "$table_history_issues" ]; then
          overall_fail=1
          echo "[FAIL] ${table_history_label} — マイグレーション履歴からの再計算値と不一致: ${table_history_issues}" >&2
        else
          echo "[PASS] ${table_history_label} — columnCount/mainColumns/foreignKeysがマイグレーション履歴からの再計算値と一致" >&2
        fi
      fi
    fi
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
  # TMPDIR が末尾スラッシュ付きの場合(例: macOSの既定/var/folders/.../T/)、
  # mktempの返り値に二重スラッシュが混入する。本体側は解決時にcd && pwdで
  # パスを組み立てており、cdが二重スラッシュを暗黙に正規化するため、比較に
  # そのまま$tmpの生値を使うと一致しない。以降の比較・フィクスチャ生成で
  # 本体側と同じ正規化済みの値を使うよう、生成直後にここで揃える。
  tmp="$(cd "$tmp" && pwd)"
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

  if _rv_out="$(run_validate "$screen_pass" "" "screen" 2>&1)"; then
    echo "  [PASS] screen陽性: 既定unitKind(screen)で全15項目PASS"
  else
    echo "  [FAIL] screen陽性: 正当なscreenマニフェストがFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  fi

  local screen_missing_top="$tmp/screen-missing-top.json"
  jq 'del(.screens)' "$screen_pass" > "$screen_missing_top"
  if _rv_out="$(run_validate "$screen_missing_top" "" "screen" 2>&1)"; then
    echo "  [FAIL] screen陰性: screens欠落マニフェストがPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] screen陰性: screens欠落でFAIL"
  fi

  local screen_bad_generated_at="$tmp/screen-bad-generated-at.json"
  jq '.generatedAt = null' "$screen_pass" > "$screen_bad_generated_at"
  if _rv_out="$(run_validate "$screen_bad_generated_at" "" "screen" 2>&1)"; then
    echo "  [FAIL] screen陰性: generatedAt=nullを受け入れた" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] screen陰性: generatedAt=nullでFAIL"
  fi

  local screen_bad_kind="$tmp/screen-bad-kind.json"
  jq '.unitKind = "api"' "$screen_pass" > "$screen_bad_kind"
  if _rv_out="$(run_validate "$screen_bad_kind" "" "screen" 2>&1)"; then
    echo "  [FAIL] screen陰性: unitKind=apiをscreenとして受け入れた" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] screen陰性: unitKind=apiをscreen指定でFAIL"
  fi

  # ---- 検査9(screenType-必須+値域)の確認 ----
  local screen_missing_type="$tmp/screen-missing-type.json"
  jq '.screens[0] |= del(.screenType)' "$screen_pass" > "$screen_missing_type"
  if _rv_out="$(run_validate "$screen_missing_type" "" "screen" 2>&1)"; then
    echo "  [FAIL] screenType陰性(不在): screenType不在なのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] screenType陰性(不在): screenType不在でFAIL"
  fi

  local screen_bad_type="$tmp/screen-bad-type.json"
  jq '.screens[0].screenType = "invalid-value"' "$screen_pass" > "$screen_bad_type"
  if _rv_out="$(run_validate "$screen_bad_type" "" "screen" 2>&1)"; then
    echo "  [FAIL] screenType陰性(値域外): screenType値域外なのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] screenType陰性(値域外): screenType値域外でFAIL"
  fi

  # ---- 分類値域と親子双方向参照の確認 ----
  local screen_bad_group="$tmp/screen-bad-group.json"
  jq '.screens[0].accountGroup = "feature_phone"' "$screen_pass" > "$screen_bad_group"
  if _rv_out="$(run_validate "$screen_bad_group" "" "screen" 2>&1)"; then
    echo "  [FAIL] accountGroup陰性(値域外): 無効値なのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] accountGroup陰性(値域外): 無効値でFAIL"
  fi

  # ---- accountSubType-値域・hasTemplate/isProcessingEndpoint-型の確認(1-71) ----
  local screen_bad_account_sub_type="$tmp/screen-bad-account-sub-type.json"
  jq '.screens[0].accountSubType = "editor role"' "$screen_pass" > "$screen_bad_account_sub_type"
  if _rv_out="$(run_validate "$screen_bad_account_sub_type" "" "screen" 2>&1)"; then
    echo "  [FAIL] accountSubType陰性(値域外): 識別子形式でない値なのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] accountSubType陰性(値域外): 識別子形式でない値でFAIL"
  fi

  local screen_bad_has_template="$tmp/screen-bad-has-template.json"
  jq '.screens[0].hasTemplate = "yes"' "$screen_pass" > "$screen_bad_has_template"
  if _rv_out="$(run_validate "$screen_bad_has_template" "" "screen" 2>&1)"; then
    echo "  [FAIL] hasTemplate陰性(型不正): 文字列なのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] hasTemplate陰性(型不正): 文字列でFAIL"
  fi

  local screen_bad_is_processing_endpoint="$tmp/screen-bad-is-processing-endpoint.json"
  jq '.screens[0].isProcessingEndpoint = "no"' "$screen_pass" > "$screen_bad_is_processing_endpoint"
  if _rv_out="$(run_validate "$screen_bad_is_processing_endpoint" "" "screen" 2>&1)"; then
    echo "  [FAIL] isProcessingEndpoint陰性(型不正): 文字列なのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] isProcessingEndpoint陰性(型不正): 文字列でFAIL"
  fi

  # ---- 名称-一意性の確認(1-51) ----
  local screen_dup_name="$tmp/screen-dup-name.json"
  jq '.detectionSummary.screenCount = 2
      | .screens[0].screenNameGuess = "ホーム画面"
      | .screens += [{screenKey:"home-alt", kind:"route", route:"/home-alt", entryFile:"src/screens/Home.tsx", confidence:"high", screenType:"top", accountGroup:"common", accountSubType:"common", hasTemplate:true, parentScreen:null, childComponents:[], isProcessingEndpoint:false, screenNameGuess:"ホーム画面"}]' "$screen_pass" > "$screen_dup_name"
  if _rv_out="$(run_validate "$screen_dup_name" "" "screen" 2>&1)"; then
    echo "  [FAIL] 名称-一意性陰性: screenNameGuessが重複するのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 名称-一意性陰性: screenNameGuessの重複でFAIL"
  fi

  local screen_unique_name="$tmp/screen-unique-name.json"
  jq '.detectionSummary.screenCount = 2
      | .screens[0].screenNameGuess = "ホーム画面"
      | .screens += [{screenKey:"home-alt", kind:"route", route:"/home-alt", entryFile:"src/screens/Home.tsx", confidence:"high", screenType:"top", accountGroup:"common", accountSubType:"common", hasTemplate:true, parentScreen:null, childComponents:[], isProcessingEndpoint:false, screenNameGuess:"別画面"}]' "$screen_pass" > "$screen_unique_name"
  if _rv_out="$(run_validate "$screen_unique_name" "" "screen" 2>&1)"; then
    echo "  [PASS] 名称-一意性陽性: screenNameGuessが一意なら全項目PASS"
  else
    echo "  [FAIL] 名称-一意性陽性: 一意なscreenNameGuessがFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # ---- 名称-一意性のスコープ限定の確認(1-124) ----
  local screen_dup_name_diff_scope="$tmp/screen-dup-name-diff-scope.json"
  jq '.detectionSummary.screenCount = 2
      | .screens[0].screenNameGuess = "ユーザー一覧"
      | .screens[0].nameScope = "site-a"
      | .screens += [{screenKey:"home-alt", kind:"route", route:"/home-alt", entryFile:"src/screens/Home.tsx", confidence:"high", screenType:"top", accountGroup:"common", accountSubType:"common", hasTemplate:true, parentScreen:null, childComponents:[], isProcessingEndpoint:false, screenNameGuess:"ユーザー一覧", nameScope:"site-b"}]' "$screen_pass" > "$screen_dup_name_diff_scope"
  if _rv_out="$(run_validate "$screen_dup_name_diff_scope" "" "screen" 2>&1)"; then
    echo "  [PASS] 名称-一意性スコープ限定陽性: 異なるnameScope間の同名はPASS"
  else
    echo "  [FAIL] 名称-一意性スコープ限定陽性: 異なるnameScope間の同名なのにFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  fi

  local screen_dup_name_same_scope="$tmp/screen-dup-name-same-scope.json"
  jq '.detectionSummary.screenCount = 2
      | .screens[0].screenNameGuess = "ユーザー一覧"
      | .screens[0].nameScope = "site-a"
      | .screens += [{screenKey:"home-alt", kind:"route", route:"/home-alt", entryFile:"src/screens/Home.tsx", confidence:"high", screenType:"top", accountGroup:"common", accountSubType:"common", hasTemplate:true, parentScreen:null, childComponents:[], isProcessingEndpoint:false, screenNameGuess:"ユーザー一覧", nameScope:"site-a"}]' "$screen_pass" > "$screen_dup_name_same_scope"
  if _rv_out="$(run_validate "$screen_dup_name_same_scope" "" "screen" 2>&1)"; then
    echo "  [FAIL] 名称-一意性スコープ限定陰性: 同一nameScope内の同名なのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 名称-一意性スコープ限定陰性: 同一nameScope内の同名でFAIL"
  fi

  local screen_parent_child="$tmp/screen-parent-child.json"
  jq '.detectionSummary.screenCount = 2
      | .screens += [{screenKey:"home-modal", kind:"route", route:"/home/modal", entryFile:"src/screens/Home.tsx", confidence:"high", screenType:"form", accountGroup:"common", accountSubType:"common", hasTemplate:true, parentScreen:"home-screen", childComponents:[], isProcessingEndpoint:false}]
      | .screens[0].childComponents = [{screenKey:"home-modal", componentType:"modal"}]' "$screen_pass" > "$screen_parent_child"
  if _rv_out="$(run_validate "$screen_parent_child" "" "screen" 2>&1)"; then
    echo "  [PASS] parent-child陽性: 双方向参照とcomponentTypeが整合"
  else
    echo "  [FAIL] parent-child陽性: 正当な双方向参照がFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  fi

  local screen_missing_parent_link="$tmp/screen-missing-parent-link.json"
  jq '.screens[1].parentScreen = null' "$screen_parent_child" > "$screen_missing_parent_link"
  if _rv_out="$(run_validate "$screen_missing_parent_link" "" "screen" 2>&1)"; then
    echo "  [FAIL] parent-child陰性(親のみ): 子→親不一致なのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] parent-child陰性(親のみ): 子→親不一致でFAIL"
  fi

  local screen_missing_child_link="$tmp/screen-missing-child-link.json"
  jq '.screens[0].childComponents = []' "$screen_parent_child" > "$screen_missing_child_link"
  if _rv_out="$(run_validate "$screen_missing_child_link" "" "screen" 2>&1)"; then
    echo "  [FAIL] parent-child陰性(子のみ): 親→子不一致なのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] parent-child陰性(子のみ): 親→子不一致でFAIL"
  fi

  local screen_bad_component_type="$tmp/screen-bad-component-type.json"
  jq '.screens[0].childComponents[0].componentType = "drawer"' "$screen_parent_child" > "$screen_bad_component_type"
  if _rv_out="$(run_validate "$screen_bad_component_type" "" "screen" 2>&1)"; then
    echo "  [FAIL] componentType陰性(値域外): 無効値なのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
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
        scenarioPath: "../../画面/home/操作シナリオ仕様書.html",
        confirmationPath: "../../画面/home/要確認事項台帳.json"
      }' "$screen_pass" > "$screen_safe_doc_urls"
  if _rv_out="$(run_validate "$screen_safe_doc_urls" "" "screen" 2>&1)"; then
    echo "  [PASS] 設計書URL陽性: 安全な相対URLを受け入れる"
  else
    echo "  [FAIL] 設計書URL陽性: 安全な相対URLを拒否した" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
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
        confirmationPath: "data:application/json,unsafe",
        testCasePath: "unsafe\u000aurl.html"
      }' "$screen_pass" > "$screen_bad_doc_urls"
  if _rv_out="$(run_validate "$screen_bad_doc_urls" "" "screen" 2>&1)"; then
    echo "  [FAIL] 設計書URL陰性: scheme・//・制御文字を含むURLを受け入れた" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 設計書URL陰性: scheme・//・制御文字を含むURLをFAIL"
  fi

  # ---- entryFile-実在の相対sourceDir解決基準確認 ----
  # sourceDirを対象リポジトリのルート起点で書いたマニフェストを、リポジトリ内の下層
  # ディレクトリへ置く。呼び出し元のカレントディレクトリを変えても、リポジトリのルートを
  # 基準に解決することを確認する。
  mkdir -p "$tmp/fake-repo/.git" "$tmp/fake-repo/rel-src/src/screens" "$tmp/fake-repo/docs/list"
  cat > "$tmp/fake-repo/rel-src/src/screens/Home.tsx" <<'EOF'
export function Home() { return null; }
EOF
  local screen_relative_manifest="$tmp/fake-repo/docs/list/screen-manifest.json"
  jq '.sourceDir = "rel-src"' "$screen_pass" > "$screen_relative_manifest"
  if _rv_out="$(cd /tmp && run_validate "$screen_relative_manifest" "" "screen" 2>&1)"; then
    echo "  [PASS] entryFile-実在(相対sourceDir): 対象リポジトリのルート基準で解決しcwdに依存しない"
  else
    echo "  [FAIL] entryFile-実在(相対sourceDir): 対象リポジトリのルート基準の解決に失敗した" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  fi

  local screen_relative_missing="$tmp/fake-repo/docs/list/screen-manifest-missing.json"
  jq '.screens[0].entryFile = "src/screens/DoesNotExist.tsx"' "$screen_relative_manifest" > "$screen_relative_missing"
  local relative_missing_output relative_missing_rc
  if relative_missing_output="$(run_validate "$screen_relative_missing" "" "screen" 2>&1)"; then
    relative_missing_rc=0
  else
    relative_missing_rc=$?
  fi
  if [ "$relative_missing_rc" -eq 0 ]; then
    echo "  [FAIL] entryFile-実在失敗メッセージ: 実在しないentryFileなのにPASSした" >&2
    printf '%s\n' "$relative_missing_output" | sed 's/^/    /' >&2
    rc=1
  elif echo "$relative_missing_output" | grep -q "解決後: $tmp/fake-repo/rel-src/src/screens/DoesNotExist.tsx"; then
    echo "  [PASS] entryFile-実在失敗メッセージ: 解決後の絶対パスがFAILメッセージに含まれる"
  else
    echo "  [FAIL] entryFile-実在失敗メッセージ: 解決後パスがメッセージに含まれない" >&2
    echo "$relative_missing_output" | grep "${SOURCE_FIELD:-entryFile}-実在" >&2
    rc=1
  fi

  # ---- 配布物のサンプルが実在検査を通ることの確認 ----
  # sourceDirは見本のルート(generation-engine/samples)起点で書かれているため、
  # --repo-rootへ見本のルートを渡して解決する。渡さない場合は既定の.git祖先探索が
  # リポジトリのルートを基準にしてしまい、sourceDirが二重連結されず解決に失敗する。
  local gold_repo_root gold_samples_root gold_layout_json gold_screen_manifest_rel
  gold_repo_root="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  gold_samples_root="$gold_repo_root/generation-engine/samples"
  gold_layout_json="$(resolve_output_layout "$gold_samples_root")" || return 1
  gold_screen_manifest_rel="$(output_layout_get "$gold_layout_json" screenManifest)" || return 1
  local gold_screen_manifest="$gold_samples_root/$gold_screen_manifest_rel"
  if [ -f "$gold_screen_manifest" ]; then
    local gold_output
    gold_output="$(cd /tmp && run_validate "$gold_screen_manifest" "" "screen" "" "$gold_samples_root" 2>&1)"
    if echo "$gold_output" | grep -q '^\[PASS\] entryFile-実在'; then
      echo "  [PASS] entryFile-実在(サンプル): 見本のルート起点sourceDirが正しく解決される"
    else
      echo "  [FAIL] entryFile-実在(サンプル): 見本のルート起点sourceDirの解決に失敗した" >&2
      rc=1
    fi
  else
    echo "  [FAIL] entryFile-実在(サンプル): サンプルのマニフェストが見つからない: $gold_screen_manifest" >&2
    rc=1
  fi

  # ---- <source>-実在の解決基準: git祖先が無い場合はcwdに依存しない(改善課題) ----
  # マニフェストが対象リポジトリの外(.git祖先の無いディレクトリ。生成直後の一時ディレクトリ等)に
  # ある場合、修正前は.git祖先探索に失敗した際の最終フォールバックが呼び出し元のカレント
  # ディレクトリ($PWD)だったため、同じ引数でも実行時のカレントディレクトリ次第で合否が変わって
  # いた(cwd=マニフェスト自身の所在ディレクトリならPASS、別cwdからだとFAIL)。修正後はマニフェスト
  # 自身の所在ディレクトリを基準にするため、どちらのcwdからでも同じ結果(PASS)になることを確認する。
  mkdir -p "$tmp/nogit-proj/src"
  cat > "$tmp/nogit-proj/src/foo.py" <<'EOF'
print(1)
EOF
  local nogit_manifest="$tmp/nogit-proj/manifest.json"
  jq -n --arg sf "foo.py" '{
    generatedAt: "2026-01-01T00:00:00Z", sourceDir: "src", unitKind: "api",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [
      {unitKey: "u1", kind: "endpoint", identifier: "GET /x", unitNameGuess: "x",
       sourceFile: $sf, confidence: "high", fileCount: 1, detectionMethod: "manual"}
    ]
  }' > "$nogit_manifest"
  mkdir -p "$tmp/elsewhere"

  local nogit_from_outside=0 nogit_from_inside=0
  local nogit_outside_out nogit_inside_out
  nogit_outside_out="$(cd "$tmp/elsewhere" && run_validate "$nogit_manifest" "" "api" 2>&1)" && nogit_from_outside=1
  nogit_inside_out="$(cd "$tmp/nogit-proj" && run_validate "$nogit_manifest" "" "api" 2>&1)" && nogit_from_inside=1

  if [ "$nogit_from_outside" -eq 1 ] && [ "$nogit_from_inside" -eq 1 ]; then
    echo "  [PASS] sourceFile-実在(git祖先なし): 対象リポジトリ外のマニフェストでも呼び出し元cwdに関わらずPASS"
  else
    echo "  [FAIL] sourceFile-実在(git祖先なし): cwd=elsewhere(${nogit_from_outside}) / cwd=manifest_dir(${nogit_from_inside})で結果が食い違うか、いずれかがFAILした" >&2
    [ "$nogit_from_outside" -eq 1 ] || printf '%s\n' "$nogit_outside_out" | sed 's/^/    [elsewhere] /' >&2
    [ "$nogit_from_inside" -eq 1 ] || printf '%s\n' "$nogit_inside_out" | sed 's/^/    [nogit-proj] /' >&2
    rc=1
  fi

  # ---- --repo-root: 納品フォルダ基準で相対sourceDirを解決できること(1-70) ----
  # 納品フォルダ自身に.gitが無く、その外側の管理リポジトリが祖先にある配置を再現する。
  # 既定の祖先探索では管理リポジトリ基準となって不在、--repo-root指定時だけ納品フォルダ
  # 基準で実在する。sourceDirは納品物に記録できる相対値のまま保持する。
  mkdir -p "$tmp/managed-repo/.git" "$tmp/managed-repo/delivery/docs/design/apis" "$tmp/managed-repo/delivery/manifests"
  printf '%s\n' 'export function api() {}' > "$tmp/managed-repo/delivery/docs/design/apis/users.ts"
  local delivery_manifest="$tmp/managed-repo/delivery/manifests/api-manifest.json"
  jq -n '{
    generatedAt: "2026-01-01T00:00:00Z", sourceDir: "docs/design/apis", unitKind: "api",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [{unitKey: "users-api", kind: "endpoint", identifier: "GET /users", unitNameGuess: "users", sourceFile: "users.ts", confidence: "high"}]
  }' > "$delivery_manifest"
  local repo_root_default_out repo_root_scoped_out
  if repo_root_default_out="$(run_validate "$delivery_manifest" "" "api" 2>&1)"; then
    echo "  [FAIL] --repo-root既定: 管理リポジトリ基準で不在のsourceFileをPASSした" >&2
    printf '%s\n' "$repo_root_default_out" | sed 's/^/    /' >&2
    rc=1
  elif repo_root_scoped_out="$(run_validate "$delivery_manifest" "" "api" "" "$tmp/managed-repo/delivery" 2>&1)"; then
    echo "  [PASS] --repo-root指定: 納品フォルダ基準のsourceDirでsourceFileを解決"
  else
    echo "  [FAIL] --repo-root指定: 納品フォルダ基準のsourceDirを解決できない" >&2
    printf '%s\n' "$repo_root_scoped_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # ---- strategy.sourceExternal=trueで実在確認を省略することの確認(1-18) ----
  local screen_external="$tmp/screen-external.json"
  jq '.strategy.sourceExternal = true | .screens[0].entryFile = "src/screens/DoesNotExist.tsx"' "$screen_pass" > "$screen_external"
  if _rv_out="$(run_validate "$screen_external" "" "screen" 2>&1)"; then
    echo "  [PASS] sourceExternal陽性: 別リポジトリ宣言時は実在しないentryFileでもPASS"
  else
    echo "  [FAIL] sourceExternal陽性: strategy.sourceExternal=trueなのにFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  fi

  local screen_external_absent="$tmp/screen-external-absent.json"
  jq '.screens[0].entryFile = "src/screens/DoesNotExist.tsx"' "$screen_pass" > "$screen_external_absent"
  if _rv_out="$(run_validate "$screen_external_absent" "" "screen" 2>&1)"; then
    echo "  [FAIL] sourceExternal既定: 宣言なしで実在しないentryFileなのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] sourceExternal既定: 宣言なしは従来どおり実在確認しFAIL"
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

  if _rv_out="$(run_validate "$api_pass" "" "api" 2>&1)"; then
    echo "  [PASS] api陽性: unitKind=apiで全11項目PASS"
  else
    echo "  [FAIL] api陽性: 正当なapiマニフェストがFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
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
  if _rv_out="$(run_validate "$api_bad_kind" "" "api" 2>&1)"; then
    echo "  [FAIL] api陰性: unitKind=tableをapiとして受け入れた" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] api陰性: unitKind=tableをapi指定でFAIL"
  fi

  local api_bad_generated_at="$tmp/api-bad-generated-at.json"
  jq '.generatedAt = ""' "$api_pass" > "$api_bad_generated_at"
  if _rv_out="$(run_validate "$api_bad_generated_at" "" "api" 2>&1)"; then
    echo "  [FAIL] api陰性: generatedAt空文字を受け入れた" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] api陰性: generatedAt空文字でFAIL"
  fi

  local api_missing_id_regex="$tmp/api-missing-id-regex.json"
  jq 'del(.strategy.unitIdRegex)' "$api_pass" > "$api_missing_id_regex"
  if _rv_out="$(run_validate "$api_missing_id_regex" "" "api" 2>&1)"; then
    echo "  [FAIL] api陰性: strategy.unitIdRegex欠落を受け入れた" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] api陰性: strategy.unitIdRegex欠落でFAIL"
  fi

  local api_bad_id_regex="$tmp/api-bad-id-regex.json"
  jq '.strategy.unitIdRegex = 1' "$api_pass" > "$api_bad_id_regex"
  if _rv_out="$(run_validate "$api_bad_id_regex" "" "api" 2>&1)"; then
    echo "  [FAIL] api陰性: strategy.unitIdRegex数値を受け入れた" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
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

  # ---- strategy-承認: unitKind=messageのapprovedByUser期待値切り替えの確認(1-17) ----
  local message_pass="$tmp/message-pass.json"
  jq '.unitKind = "message" | .strategy.approvedByUser = false' "$api_pass" > "$message_pass"
  if _rv_out="$(run_validate "$message_pass" "" "message" 2>&1)"; then
    echo "  [PASS] strategy-承認message陽性: unitKind=messageはapprovedByUser=falseでPASS"
  else
    echo "  [FAIL] strategy-承認message陽性: unitKind=messageのapprovedByUser=falseがFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  fi

  local message_bad_approved="$tmp/message-bad-approved.json"
  jq '.unitKind = "message" | .strategy.approvedByUser = true' "$api_pass" > "$message_bad_approved"
  if _rv_out="$(run_validate "$message_bad_approved" "" "message" 2>&1)"; then
    echo "  [FAIL] strategy-承認message陰性: unitKind=messageでapprovedByUser=trueを受け入れた" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] strategy-承認message陰性: unitKind=messageのapprovedByUser=trueでFAIL"
  fi

  # 検査4(sourceFile-実在)のFAIL確認: sourceFileが実在しないunitsを混入させる
  local api_missing_source="$tmp/api-missing-source.json"
  jq --arg f "$tmp/api-src/routes/does-not-exist.ts" '.units[0].sourceFile = $f' "$api_pass" > "$api_missing_source"
  if _rv_out="$(run_validate "$api_missing_source" "" "api" 2>&1)"; then
    echo "  [FAIL] api陰性: sourceFile不在なのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] api陰性: sourceFile不在でFAIL"
  fi

  # --fixでunresolvedへ降格しPASSすることを確認
  local api_fixed="$tmp/api-fixed.json"
  if _rv_out="$(run_validate "$api_missing_source" "$api_fixed" "api" 2>&1)"; then
    echo "  [PASS] api --fix: sourceFile不在エントリをunresolvedへ降格しPASS"
  else
    echo "  [FAIL] api --fix: --fix指定時もFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
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
  if _rv_out="$(run_validate "$api_ext_pass" "" "api" 2>&1)"; then
    echo "  [PASS] 拡張フィールド陽性: 正しい型の任意フィールド付きでも全11項目PASS"
  else
    echo "  [FAIL] 拡張フィールド陽性: 正しい型の任意フィールドがFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # 型違反系: authRequiredが文字列・callersが文字列配列でない場合はFAIL
  local api_ext_bad="$tmp/api-ext-bad.json"
  jq '.units[0] += {"authRequired": "yes", "callers": [1, 2]}' "$api_pass" > "$api_ext_bad"
  if _rv_out="$(run_validate "$api_ext_bad" "" "api" 2>&1)"; then
    echo "  [FAIL] 拡張フィールド陰性: 型違反(authRequired文字列/callers数値配列)なのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 拡張フィールド陰性: 型違反でFAIL"
  fi

  # null陽性系: 任意フィールドが明示的nullを持つユニットで型検査がエラーにならないこと
  local api_ext_null="$tmp/api-ext-null.json"
  jq '.units[0] += {"category": null, "authRequired": null, "columnCount": null}' "$api_pass" > "$api_ext_null"
  if _rv_out="$(run_validate "$api_ext_null" "" "api" 2>&1)"; then
    echo "  [PASS] 拡張フィールドnull陽性: 任意フィールドが明示的nullでも全11項目PASS"
  else
    echo "  [FAIL] 拡張フィールドnull陽性: 任意フィールドの明示的nullがFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # ---- 1-170: confirmedPermissions/confirmedScheduleの型検査の確認 ----
  local api_confirmed_pass="$tmp/api-confirmed-pass.json"
  jq '.units[0] += {"confirmedPermissions": ["admin"], "confirmedSchedule": {"cron": "0 3 * * *", "readable": "毎日 3:00"}}' \
    "$api_pass" > "$api_confirmed_pass"
  if _rv_out="$(run_validate "$api_confirmed_pass" "" "api" 2>&1)"; then
    echo "  [PASS] 1-170: confirmedPermissions(文字列配列)・confirmedSchedule(cron/readable)が正しい型ならPASS"
  else
    echo "  [FAIL] 1-170: 正しい型のconfirmedPermissions/confirmedScheduleがFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  fi

  local api_confirmed_bad="$tmp/api-confirmed-bad.json"
  jq '.units[0] += {"confirmedPermissions": [1, 2], "confirmedSchedule": {"cron": "0 3 * * *"}}' \
    "$api_pass" > "$api_confirmed_bad"
  if _rv_out="$(run_validate "$api_confirmed_bad" "" "api" 2>&1)"; then
    echo "  [FAIL] 1-170: confirmedPermissions(数値配列)・confirmedSchedule(readable欠落)なのにPASSした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 1-170: confirmedPermissions/confirmedScheduleの型違反でFAIL"
  fi

  # confirmationPathはscreen以外も同じ安全な相対URL契約で検査する。
  local api_confirmation_safe="$tmp/api-confirmation-safe.json"
  jq '.units[0].confirmationPath = "../../API/api-users/要確認事項台帳.json"' \
    "$api_pass" > "$api_confirmation_safe"
  if _rv_out="$(run_validate "$api_confirmation_safe" "" "api" 2>&1)"; then
    echo "  [PASS] confirmationPath陽性(api): 安全な相対JSONパスを受け入れる"
  else
    echo "  [FAIL] confirmationPath陽性(api): 安全な相対JSONパスを拒否した" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  fi

  local api_confirmation_bad="$tmp/api-confirmation-bad.json"
  jq '.units[0].confirmationPath = "https://attacker.invalid/ledger.json"' \
    "$api_pass" > "$api_confirmation_bad"
  if _rv_out="$(run_validate "$api_confirmation_bad" "" "api" 2>&1)"; then
    echo "  [FAIL] confirmationPath陰性(api): scheme付きURLを受け入れた" >&2
    rc=1
  else
    echo "  [PASS] confirmationPath陰性(api): scheme付きURLをFAIL"
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
  local replacement_char_output replacement_char_rc
  if replacement_char_output="$(run_validate "$api_replacement_char" "" "api" 2>&1)"; then
    replacement_char_rc=0
  else
    replacement_char_rc=$?
  fi
  if [ "$replacement_char_rc" -eq 0 ]; then
    echo "  [FAIL] 置換文字-非混入陰性: 置換文字を含むのにPASSした" >&2
    printf '%s\n' "$replacement_char_output" | sed 's/^/    /' >&2
    rc=1
  elif echo "$replacement_char_output" | grep -q '\[FAIL\] 置換文字-非混入.*1件'; then
    echo "  [PASS] 置換文字-非混入陰性: 置換文字混入でFAILし件数が列挙される"
  else
    echo "  [FAIL] 置換文字-非混入陰性: FAILしたが件数が出力に含まれない" >&2
    echo "$replacement_char_output" | grep '置換文字-非混入' >&2
    rc=1
  fi

  # 陽性: 置換文字を含まない合成マニフェストでは従来どおり通過すること
  if _rv_out="$(run_validate "$api_pass" "" "api" 2>&1)"; then
    echo "  [PASS] 置換文字-非混入陽性: 置換文字を含まないマニフェストは従来どおりPASS"
  else
    echo "  [FAIL] 置換文字-非混入陽性: 置換文字を含まないのにFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # ---- 検査(valueProvenance-値域)の確認(1-170) ----
  # 陽性: measured/inferred/confirmedの3値のみを持つマニフェストはPASSすること
  local vp_pass="$tmp/api-value-provenance-pass.json"
  jq '.units[0].valueProvenance = {permissions: "measured"}
      | .units[1].valueProvenance = {schedule: "inferred", relatedField: "confirmed"}' \
    "$api_pass" > "$vp_pass"
  if _rv_out="$(run_validate "$vp_pass" "" "api" 2>&1)"; then
    echo "  [PASS] valueProvenance-値域陽性: measured/inferred/confirmedのみならPASS"
  else
    echo "  [FAIL] valueProvenance-値域陽性: 正しい3値のみなのにFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # 陰性: 値域外の値を含むマニフェストはFAILし、該当キーが列挙されること
  local vp_fail="$tmp/api-value-provenance-fail.json"
  jq '.units[0].valueProvenance = {permissions: "guessed"}' "$api_pass" > "$vp_fail"
  local vp_fail_output vp_fail_rc
  if vp_fail_output="$(run_validate "$vp_fail" "" "api" 2>&1)"; then
    vp_fail_rc=0
  else
    vp_fail_rc=$?
  fi
  if [ "$vp_fail_rc" -eq 0 ]; then
    echo "  [FAIL] valueProvenance-値域陰性: 値域外の値を含むのにPASSした" >&2
    printf '%s\n' "$vp_fail_output" | sed 's/^/    /' >&2
    rc=1
  elif echo "$vp_fail_output" | grep -q '\[FAIL\] valueProvenance-値域.*valueProvenance\.permissions=guessed'; then
    echo "  [PASS] valueProvenance-値域陰性: 値域外の値でFAILし該当キーが列挙される"
  else
    echo "  [FAIL] valueProvenance-値域陰性: FAILしたが該当キーが出力に含まれない" >&2
    echo "$vp_fail_output" | grep 'valueProvenance-値域' >&2
    rc=1
  fi

  # ---- 検査(table-メタデータ-履歴突き合わせ)の確認: 改善課題「マニフェスト検証-履歴を
  #      突き合わせない」への対応。extract-table-metadata.sh を実際に呼び出し、再計算値との
  #      一致/不一致でPASS/FAILが切り替わることを確認する ----
  local table_hist_dir="$tmp/table-history"
  mkdir -p "$table_hist_dir/migrations"
  cat > "$table_hist_dir/migrations/001_create_widget.sql" <<'EOF'
CREATE TABLE widget (
  id BIGINT NOT NULL,
  name VARCHAR(100) NOT NULL,
  PRIMARY KEY (id)
);
EOF
  cat > "$table_hist_dir/migrations/002_add_widget_columns.sql" <<'EOF'
ALTER TABLE widget ADD COLUMN weight_scale REAL;
EOF
  local table_hist_manifest="$table_hist_dir/table-manifest.json"
  jq -n --arg sourceDir "$table_hist_dir/migrations" --arg widgetFile "$table_hist_dir/migrations/001_create_widget.sql" '{
    generatedAt: "2026-01-01T00:00:00Z", sourceDir: $sourceDir, unitKind: "table",
    strategy: {extractionMethod: "migration-sql", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [{unitKey: "widget", kind: "table", identifier: "widget", unitNameGuess: "ウィジェット",
             sourceFile: $widgetFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"}]
  }' > "$table_hist_manifest"

  # extract-table-metadata.sh 本体で拡張マニフェストを作る(再計算値そのものを検証対象にする=陽性)
  local extract_script table_hist_ext
  extract_script="$SCRIPT_DIR/../extract/extract-table-metadata.sh"
  table_hist_ext="$table_hist_dir/table-manifest.ext.json"
  bash "$extract_script" "$table_hist_manifest" "$table_hist_dir/migrations" "$table_hist_ext" >/dev/null 2>&1

  if _rv_out="$(run_validate "$table_hist_ext" "" "table" "$table_hist_dir/migrations" 2>&1)"; then
    echo "  [PASS] table-メタデータ-履歴突き合わせ陽性: extract-table-metadata.shの再計算値そのものはPASS"
  else
    echo "  [FAIL] table-メタデータ-履歴突き合わせ陽性: 再計算値と自分自身の突き合わせでFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # 陰性: columnCountを手動で古い値(後続ALTERを反映しない値)へ書き換えたマニフェストはFAILすること
  local table_hist_stale="$table_hist_dir/table-manifest.stale.json"
  jq '.units[0].columnCount = 2 | .units[0].mainColumns = ["id", "name"]' "$table_hist_ext" > "$table_hist_stale"
  local table_hist_stale_output table_hist_stale_rc
  if table_hist_stale_output="$(run_validate "$table_hist_stale" "" "table" "$table_hist_dir/migrations" 2>&1)"; then
    table_hist_stale_rc=0
  else
    table_hist_stale_rc=$?
  fi
  if [ "$table_hist_stale_rc" -eq 0 ]; then
    echo "  [FAIL] table-メタデータ-履歴突き合わせ陰性: 後続ALTERを反映しない古いcolumnCountなのにPASSした" >&2
    printf '%s\n' "$table_hist_stale_output" | sed 's/^/    /' >&2
    rc=1
  elif echo "$table_hist_stale_output" | grep -q '\[FAIL\] table-メタデータ-履歴突き合わせ.*widget\.columnCount: manifest=2 再計算=3'; then
    echo "  [PASS] table-メタデータ-履歴突き合わせ陰性: 古いcolumnCountでFAILし再計算値との差が列挙される"
  else
    echo "  [FAIL] table-メタデータ-履歴突き合わせ陰性: FAILしたが差分が出力に含まれない" >&2
    echo "$table_hist_stale_output" | grep 'table-メタデータ-履歴突き合わせ' >&2
    rc=1
  fi

  # スキップ: --migrations-dir未指定、またはunit_kind!=tableの場合はPASS扱い(素通りではなく明示スキップ)
  if _rv_out="$(run_validate "$table_hist_ext" "" "table" 2>&1)"; then
    echo "  [PASS] table-メタデータ-履歴突き合わせスキップ: --migrations-dir未指定ならPASS扱い"
  else
    echo "  [FAIL] table-メタデータ-履歴突き合わせスキップ: --migrations-dir未指定なのにFAILした" >&2
    printf '%s\n' "$_rv_out" | sed 's/^/    /' >&2
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
MIGRATIONS_DIR_ARG=""
REPO_ROOT_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fix)
      FIX_OUT="${2:-}"
      if [ -z "$FIX_OUT" ]; then
        echo "Usage: validate-manifest.sh <manifest.json> [--fix <fixed-out.json>] [--unit-kind <kind>] [--migrations-dir <dir>]" >&2
        exit 1
      fi
      shift 2
      ;;
    --unit-kind)
      UNIT_KIND_ARG="${2:-}"
      if [ -z "$UNIT_KIND_ARG" ]; then
        echo "Usage: validate-manifest.sh <manifest.json> [--fix <fixed-out.json>] [--unit-kind <kind>] [--migrations-dir <dir>]" >&2
        exit 1
      fi
      shift 2
      ;;
    --axes)
      AXES_FILE="${2:-}"
      shift 2
      ;;
    --migrations-dir)
      MIGRATIONS_DIR_ARG="${2:-}"
      if [ -z "$MIGRATIONS_DIR_ARG" ]; then
        echo "Usage: validate-manifest.sh <manifest.json> [--fix <fixed-out.json>] [--unit-kind <kind>] [--migrations-dir <dir>]" >&2
        exit 1
      fi
      shift 2
      ;;
    --repo-root)
      REPO_ROOT_ARG="${2:-}"
      if [ -z "$REPO_ROOT_ARG" ]; then
        echo "Usage: validate-manifest.sh <manifest.json> [--fix <fixed-out.json>] [--unit-kind <kind>] [--migrations-dir <dir>] [--repo-root <path>]" >&2
        exit 1
      fi
      shift 2
      ;;
    *)
      echo "Usage: validate-manifest.sh <manifest.json> [--fix <fixed-out.json>] [--unit-kind <kind>] [--migrations-dir <dir>]" >&2
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

if [ -n "$REPO_ROOT_ARG" ]; then
  if [ ! -d "$REPO_ROOT_ARG" ]; then
    echo "ERROR: --repo-root is not a directory: $REPO_ROOT_ARG" >&2
    exit 1
  fi
  REPO_ROOT_ARG="$(cd "$REPO_ROOT_ARG" && pwd)"
fi

if [ -n "$UNIT_KIND_ARG" ]; then
  UNIT_KIND="$UNIT_KIND_ARG"
else
  UNIT_KIND="$(jq -r '.unitKind // empty' "$MANIFEST")"
  [ -z "$UNIT_KIND" ] && UNIT_KIND="screen"
fi

run_validate "$MANIFEST" "$FIX_OUT" "$UNIT_KIND" "$MIGRATIONS_DIR_ARG" "$REPO_ROOT_ARG"
exit $?
