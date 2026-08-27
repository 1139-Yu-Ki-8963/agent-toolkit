#!/usr/bin/env bash
# run-layer-full-pipeline.sh — 第3層（一気通貫）の生成連鎖スクリプト
#
# 目的:
#   往復検証の第3層として、疑似入力の配置から設計文書のマニフェスト組み立て・種別別抽出・
#   一覧生成・マトリクス生成・デザイン系ページ生成・規約定義の展開・ポータル生成までを、
#   既存の決定的スクリプト群を順に呼んで一気通貫で実行する。1段が失敗しても後続を続け、
#   最後に段ごとの結果を集計する。
#
# 使い方:
#   run-layer-full-pipeline.sh --output <出力先> [--repo <リポジトリのパス>] \
#     [--input <疑似入力の位置>] [--keep] [--self-test]
#
#   --output <path>  生成物の出力先(必須)。版管理下のパス(git リポジトリの中)なら
#                     何も実行せず exit 1 で拒否する
#   --repo <path>     往復検証の対象リポジトリ(原本コード)のパス。省略時は本スクリプト
#                      自身が属するリポジトリ(reverse-docs-skills)のルートを使う
#   --input <path>    疑似入力の配置先を明示したい場合に prepare-verification-input.sh へ渡す
#   --keep            終了時にスクラッチ作業領域(verification-env.sh管理)を残す(失敗調査用)。
#                      --output で指定した生成物自体は常に残る
#   --self-test       実際の生成は行わず、引数検査・段定義・依存スクリプト実在・
#                      確認事項台帳の収集経路などの軽量な自己診断のみを行う
#
# 段の構成(10段。段2は prepare-verification-input.sh が無ければ SKIP して後続を続ける):
#   1. 出力先の用意(verification-env.sh)
#   2. 疑似入力の配置(prepare-verification-input.sh。存在しなければ SKIP)
#   3. portal-input/build-manifests-from-docs.sh
#   4. 種別別の抽出(unit-list/detect-screens.sh + extract/ 配下の各抽出)
#   5. 一覧の生成(unit-list/build-screen-list.sh・build-unit-list.sh・build-feature-list.sh)
#   6. マトリクスの生成(extract/build-matrix-data.sh → matrix/build-matrix-pages.sh)
#   7. デザイン系の抽出と生成(extract/extract-design-tokens-from-designmd.sh 等 →
#      detail-pages/build-detail-page.sh)。関連図3種(状態遷移図・ER図・画面遷移図)の
#      抽出(portal-input/extract-entity-state-page-data.sh 等)もこの段で行う
#      (一覧の生成が終わり詳細ページを作る段という位置づけが同じため)
#   8. rules/scaffold-rule-definitions.sh --apply
#   9. build-portal.sh
#   10. 結果の集計
#
# 失敗の扱い: ある段が失敗しても後続の段は必ず実行する。1段でも失敗があれば最終的に exit 1。
#
# 保守責任者: 人手(ユーザー)。呼び出す既存スクリプトの引数契約が変わった場合は、本ファイルの
# 各 stage_* 関数と self-test を同時に更新する。
# macOS bash 3.2 互換(連想配列・declare -A・${var^^} は使わない)。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"

# shellcheck source=./verification-env.sh
. "${SCRIPT_DIR}/verification-env.sh"
# shellcheck source=../output-layout.sh
. "${SCRIPT_DIR}/../output-layout.sh"

LAST_OUTPUT=""
LAST_RC=0
RESULT_KEYS=()
RESULT_STATUS=()
RESULT_DETAIL=()
SCRATCH_BASE=""
REPO_EXPLICIT=0
SURVEY_LEDGER_ARGS=()

# ---- 段の定義 -----------------------------------------------------------

stage_keys() {
  cat <<'EOS'
prepare-output
prepare-input
build-manifests
type-extraction
unit-lists
matrix
design-pages
rules-scaffold
portal-build
aggregate
EOS
}

stage_name() {
  case "$1" in
    prepare-output) echo "出力先の用意" ;;
    prepare-input) echo "疑似入力の配置" ;;
    build-manifests) echo "設計文書からのマニフェスト組み立て" ;;
    type-extraction) echo "種別別の抽出" ;;
    unit-lists) echo "一覧の生成" ;;
    matrix) echo "マトリクスの生成" ;;
    design-pages) echo "デザイン系の抽出と生成" ;;
    rules-scaffold) echo "規約定義の展開" ;;
    portal-build) echo "ポータルの生成" ;;
    aggregate) echo "結果の集計" ;;
    *) echo "$1" ;;
  esac
}

# 呼び出す既存スクリプトの一覧(依存実在チェックと実行の両方で共用)。
# 引数: <this repository root>(このパイプラインスクリプト自身が属するリポジトリのルート)
dependency_scripts() {
  local repo="$1"
  cat <<EOS
${repo}/generation-engine/scripts/verification/verification-env.sh
${repo}/generation-engine/scripts/portal-input/build-manifests-from-docs.sh
${repo}/generation-engine/scripts/unit-list/detect-screens.sh
${repo}/generation-engine/scripts/extract/extract-api-metadata.sh
${repo}/generation-engine/scripts/extract/extract-table-metadata.sh
${repo}/generation-engine/scripts/extract/extract-batch-metadata.sh
${repo}/generation-engine/scripts/extract/extract-report-metadata.sh
${repo}/generation-engine/scripts/extract/extract-external-metadata.sh
${repo}/generation-engine/scripts/extract/extract-feature-metadata.sh
${repo}/generation-engine/scripts/unit-list/build-screen-list.sh
${repo}/generation-engine/scripts/unit-list/build-unit-list.sh
${repo}/generation-engine/scripts/unit-list/build-feature-list.sh
${repo}/generation-engine/scripts/generate-integration-test-spec.sh
${repo}/generation-engine/scripts/extract/build-matrix-data.sh
${repo}/generation-engine/scripts/extract/build-permission-function-data.sh
${repo}/generation-engine/scripts/matrix/build-matrix-pages.sh
${repo}/generation-engine/scripts/extract/extract-design-tokens-from-designmd.sh
${repo}/generation-engine/scripts/extract/extract-component-inventory.sh
${repo}/generation-engine/scripts/extract/extract-icon-usage.sh
${repo}/generation-engine/scripts/extract/extract-ai-assets.sh
${repo}/generation-engine/scripts/detail-pages/build-detail-page.sh
${repo}/generation-engine/scripts/portal-input/extract-entity-state-page-data.sh
${repo}/generation-engine/scripts/portal-input/extract-er-page-data.sh
${repo}/generation-engine/scripts/portal-input/extract-transition-page-data.sh
${repo}/generation-engine/scripts/rules/scaffold-rule-definitions.sh
${repo}/generation-engine/scripts/rules/build-rule-flow-map.sh
${repo}/generation-engine/scripts/build-portal.sh
${repo}/generation-engine/scripts/extract/extract-screen-metadata.sh
${repo}/generation-engine/scripts/extract/convert-message-doc-to-manifest.sh
${repo}/generation-engine/scripts/extract/aggregate-test-viewpoints.sh
${repo}/generation-engine/scripts/extract/aggregate-test-cases.sh
${repo}/generation-engine/scripts/extract/build-confirmation-survey-data.sh
EOS
}

record_result() {
  RESULT_KEYS+=("$1")
  RESULT_STATUS+=("$2")
  RESULT_DETAIL+=("$3")
}

run_cmd() {
  LAST_OUTPUT="$("$@" 2>&1)"
  LAST_RC=$?
}

# 画面検出失敗時の続行用の空マニフェストを書き出す。
# 構造は非画面6種別(build-manifests-from-docs.sh の出力)と同じ骨格
# (generatedAt/sourceDir/unitKind/strategy/detectionSummary.unitCount/units)に、
# build-screen-list.sh・build-matrix-data.sh が読む画面固有キー(screens 配列と
# detectionSummary.screenCount 等。いずれも `// 0`・`// []` で既定値を補うため
# 欠けても壊れないが、実際の検出結果と同じ形に揃えておく)を足したもの。
# 失敗を隠さないよう、note に続行理由を記録する。
write_empty_screen_manifest() {
  local dest="$1"
  local generated_at
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n \
    --arg generatedAt "${generated_at}" \
    --arg sourceDir "${REPO}" \
    --arg note "画面の検出に失敗したため空のマニフェストで続行する" \
    '{
      generatedAt: $generatedAt,
      sourceDir: $sourceDir,
      unitKind: "screen",
      note: $note,
      strategy: { extractionMethod: "detection-failed", approvedByUser: true, screenIdRegex: null, unitIdRegex: null },
      detectionSummary: {
        unitCount: 0, unresolvedCount: 0,
        method: "detection-failed", screenCount: 0, clusterCount: 0,
        sharedScreenCount: 0, embeddedCandidateCount: 0
      },
      screens: [],
      units: []
    }' > "${dest}"
}

pick_manifest() {
  local kind="$1"
  if [ -f "${MANIFESTS_DIR}/${kind}-manifest.ext.json" ]; then
    echo "${MANIFESTS_DIR}/${kind}-manifest.ext.json"
  elif [ -f "${MANIFESTS_DIR}/${kind}-manifest.json" ]; then
    echo "${MANIFESTS_DIR}/${kind}-manifest.json"
  fi
}

# 出力レイアウトの画面設計単位ルートから要確認事項台帳を辞書順で列挙する。
# 画面ルートが存在しない場合は成功・空出力とし、解決・探索の失敗は呼び出し元へ返す。
collect_confirmation_ledgers() {
  local output_dir="$1"
  local layout_json screen_unit_root screen_unit_path

  layout_json="$(resolve_output_layout "${output_dir}")" || return $?
  screen_unit_root="$(output_layout_get "${layout_json}" screenUnitRoot)" || return $?
  screen_unit_path="${output_dir}/${screen_unit_root}"
  [ -d "${screen_unit_path}" ] || return 0

  find "${screen_unit_path}" -type f -name '要確認事項台帳.json' -print | LC_ALL=C sort
}

# 台帳パスの改行区切り出力を、builderへそのまま渡せる通常配列へ変換する。
build_confirmation_ledger_args() {
  local output_dir="$1"
  local ledger_paths ledger rc
  SURVEY_LEDGER_ARGS=()

  ledger_paths="$(collect_confirmation_ledgers "${output_dir}")" || {
    rc=$?
    return "${rc}"
  }
  while IFS= read -r ledger; do
    [ -n "${ledger}" ] && SURVEY_LEDGER_ARGS+=(--confirmation-ledger "${ledger}")
  done <<LEDGERS
${ledger_paths}
LEDGERS
  return 0
}

# 種別別の抽出(stage_type_extraction)のうち api/table/batch/report/external/feature の
# 6種別が使う起点を種別ごとに解決する(screen は対象外。stage_type_extraction 内の
# コメント参照)。--repo が明示された場合(REPO_EXPLICIT=1)は常に ${REPO} を使う(従来どおり)。
# prepare-verification-input.sh が ${OUTPUT_DIR}/verification-source/<kind> へ
# 疑似コードを配置済みなら、--repo の明示有無にかかわらずそちらを使う。
# 疑似入力の配置に失敗・スキップした場合は ${REPO} へフォールバックする。
resolve_extraction_source_dir() {
  local kind_en="$1"
  local staged="${OUTPUT_DIR}/verification-source/${kind_en}"
  if [ -d "${staged}" ]; then
    printf '%s' "${staged}"
  else
    printf '%s' "${REPO}"
  fi
}

excluded_kinds_file() {
  # 一覧の置き場は英字（lists）へ移した。日本語（一覧）は移行前の名前であり、
  # 既に配った成果物のために残す。実測（2026-08-28）で、英字を探さないため
  # 画面0件の見本に対する生成連鎖が3段落ちていた。
  local candidate
  for candidate in \
    "${OUTPUT_DIR}/docs/scope-and-progress/excluded-kinds.json" \
    "${OUTPUT_DIR}/lists/excluded-kinds.json" \
    "${OUTPUT_DIR}/一覧/excluded-kinds.json" \
    "${REPO}/docs/scope-and-progress/excluded-kinds.json" \
    "${REPO}/lists/excluded-kinds.json" \
    "${REPO}/一覧/excluded-kinds.json"; do
    if [ -f "${candidate}" ]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

kind_is_excluded() {
  local kind="$1" file
  file="$(excluded_kinds_file)" || return 1
  jq -e --arg kind "${kind}" \
    'any((.excludedKinds // [])[]; .kind == $kind)' "${file}" >/dev/null 2>&1
}

# ---- 各段の実行 ----------------------------------------------------------

stage_prepare_output() {
  mkdir -p "${OUTPUT_DIR}" "${MANIFESTS_DIR}" "${PORTAL_DIR}" 2>/dev/null
  local id
  id="$(verification_env_new_id)"
  SCRATCH_BASE="$(verification_env_setup "$id")"
  if [ -n "${SCRATCH_BASE}" ] && [ -d "${OUTPUT_DIR}" ]; then
    record_result prepare-output OK "出力先 ${OUTPUT_DIR} とスクラッチ ${SCRATCH_BASE} を用意した"
  else
    record_result prepare-output FAIL "出力先またはスクラッチの用意に失敗した"
  fi
}

stage_prepare_input() {
  local script="${REPO_SELF}/generation-engine/scripts/verification/prepare-verification-input.sh"
  if [ ! -f "${script}" ]; then
    record_result prepare-input SKIP "prepare-verification-input.sh が存在しない"
    return 0
  fi
  local excluded_source excluded_destination
  if excluded_source="$(excluded_kinds_file)"; then
    excluded_destination="${OUTPUT_DIR}/docs/scope-and-progress/excluded-kinds.json"
    if [ "${excluded_source}" != "${excluded_destination}" ]; then
      mkdir -p "$(dirname "${excluded_destination}")"
      cp "${excluded_source}" "${excluded_destination}"
    fi
    run_cmd bash "${script}" --repo "${REPO_SELF}" --output "${OUTPUT_DIR}" --common-design-only
    if [ "${LAST_RC}" -ne 0 ]; then
      record_result prepare-input FAIL "担当する共通設計文書5件の配置に失敗した。終了コード ${LAST_RC}"
      return 0
    fi
    record_result prepare-input OK "対象側の対象外宣言を維持し、共通設計文書5件だけを配置した"
    return 0
  fi
  # --repo はテンプレートの置き場を探す起点であり、このリポジトリ自身を指す。
  # 対象側（${REPO}）を渡すと、対象側にテンプレートが無いため必ず落ちる。
  # 実測（2026-08-28）で、対象外宣言を持たない見本に対して3段が落ちていた。
  # 対象外宣言を持つ経路は既に ${REPO_SELF} を渡しており、そちらが正しい。
  local args=("--repo" "${REPO_SELF}" "--output" "${OUTPUT_DIR}")
  [ -n "${INPUT_LOCATION}" ] && args+=("--input" "${INPUT_LOCATION}")
  run_cmd bash "${script}" "${args[@]}"
  if [ "${LAST_RC}" -eq 0 ]; then
    record_result prepare-input OK "疑似入力を配置した"
  else
    record_result prepare-input FAIL "終了コード ${LAST_RC}"
  fi
}

stage_build_manifests() {
  local script="${REPO_SELF}/generation-engine/scripts/portal-input/build-manifests-from-docs.sh"
  if [ ! -f "${script}" ]; then
    record_result build-manifests FAIL "スクリプトが存在しない: ${script}"
    return 0
  fi
  local source_file_root="${OUTPUT_DIR}/verification-source/project"
  [ -d "${source_file_root}" ] || source_file_root="${REPO}"
  run_cmd bash "${script}" "${OUTPUT_DIR}" "${MANIFESTS_DIR}" --source-file-root "${source_file_root}"
  if [ "${LAST_RC}" -eq 0 ]; then
    record_result build-manifests OK "非画面6種別のマニフェストを組み立てた"
  else
    record_result build-manifests FAIL "終了コード ${LAST_RC}"
  fi
}

stage_type_extraction() {
  local any_fail=0 detail=""
  # 画面(screen)は detect-screens.sh がディレクトリ規約から検出する専用方式であり、
  # 疑似コードの寄せ集め(verification-source/screen)を渡すと弱いフォールバック検出
  # (builtin-fallback-directory)が発火し、後続の一覧生成が validate-manifest.sh で
  # 拒否される新規の失敗を招く(entryFile が実ファイルでなくディレクトリになる等)。
  # 完了条件が求める6種別(api/table/batch/report/external/feature)には影響しないため、
  # 画面だけは対象外とし ${REPO} を渡す従来どおりの挙動を維持する。
  #
  # generation-engine/samples 配下は --exclude で必ず除外する。この配下の一覧見本
  # (samples/project-portal/lists/screens 等)・画面見本(samples/project-portal/
  # screens/screen-* 等)・画面設計文書見本(samples/docs/design/screens 等)は、
  # 置き場を英字へ揃えた結果、detect-screens.sh のフォールバック規約
  # (pages/screens/views ディレクトリ直下を1画面とみなす)に一致するようになった。
  # 除外しないと ${REPO}(このリポジトリ自身)を検出対象にした際、これらの見本を
  # 画面として誤検出し、entryFile がディレクトリ(見本フォルダそのもの)を指す不正な
  # マニフェストになる(2026-08-24 実測)。この誤検出により「このリポジトリ自身の
  # ようにアプリケーションコードを持たない対象では検出が必ず0件になる」という
  # 下記コメントの前提が破れていたため、除外で前提を復元する。
  local scr_script="${REPO_SELF}/generation-engine/scripts/unit-list/detect-screens.sh"
  local screen_manifest_path="${MANIFESTS_DIR}/screen-manifest.json"
  if [ -f "${scr_script}" ]; then
    if kind_is_excluded screen; then
      write_empty_screen_manifest "${screen_manifest_path}"
      detail="${detail}screen=0(対象外宣言に基づき抽出を実行しない); "
    else
    # detect-screens.sh に出力先を直接渡すと、検出0件の結果(exit 0で0件・または
    # 検出失敗で0件相当の内容だけ書いて後続処理でexit非0になる場合の両方を含む)で
    # 既存の一覧を無条件に上書きしてしまう(このリポジトリ自身のようにアプリケーション
    # コードを持たない対象では検出が必ず0件になり、prepare-verification-input.sh が
    # 組み立てた疑似入力の画面一覧を消す)。判断は detect-screens.sh 自身に持たせず、
    # 呼ぶ側であるこの段が既存件数と検出件数(exit codeではなく実際に書かれた内容)を
    # 比べてから書き込み先を決める。
    local screen_existing_count=0
    if [ -f "${screen_manifest_path}" ]; then
      screen_existing_count="$(jq -r '(.screens // []) | length' "${screen_manifest_path}" 2>/dev/null)"
      case "${screen_existing_count}" in ''|*[!0-9]*) screen_existing_count=0 ;; esac
    fi
    local screen_detected_path="${MANIFESTS_DIR}/screen-manifest.detected.json"
    rm -f "${screen_detected_path}"
    run_cmd bash "${scr_script}" "${REPO}" "${screen_detected_path}" \
      --exclude '(^|/)generation-engine/samples(/|$)'
    local screen_rc="${LAST_RC}"

    local screen_detected_count=0
    if [ -f "${screen_detected_path}" ]; then
      screen_detected_count="$(jq -r '(.screens // []) | length' "${screen_detected_path}" 2>/dev/null)"
      case "${screen_detected_count}" in ''|*[!0-9]*) screen_detected_count=0 ;; esac
    fi

    if [ "${screen_detected_count}" -eq 0 ] && [ "${screen_existing_count}" -ge 1 ]; then
      # 検出0件(検出失敗を含む)・既存1件以上のときは上書きせず既存を残す。
      rm -f "${screen_detected_path}"
      detail="${detail}screen=${screen_rc}(検出0件・既存${screen_existing_count}件のため既存を残した); "
    elif [ -f "${screen_detected_path}" ]; then
      [ "${screen_rc}" -ne 0 ] && any_fail=1
      # 検出が1件以上、または既存も0件のときはこれまでどおり検出の結果で置き換える。
      mv -f "${screen_detected_path}" "${screen_manifest_path}"
      detail="${detail}screen=${screen_rc}; "
    else
      [ "${screen_rc}" -ne 0 ] && any_fail=1
      # 検出失敗でマニフェスト自体が書かれず、既存も0件のときは、後続の段
      # (一覧・マトリクス)が入力不足で巻き込み判定不能にならないよう
      # 空の妥当なマニフェストで続行する。
      write_empty_screen_manifest "${screen_manifest_path}"
      detail="${detail}screen=${screen_rc}(空マニフェストで続行); "
    fi
    fi
  else
    any_fail=1
    detail="${detail}screen=missing-script; "
  fi

  local kind script manifest kind_source_dir
  for kind in api table batch report external feature; do
    case "${kind}" in
      api) script="${REPO_SELF}/generation-engine/scripts/extract/extract-api-metadata.sh" ;;
      table) script="${REPO_SELF}/generation-engine/scripts/extract/extract-table-metadata.sh" ;;
      batch) script="${REPO_SELF}/generation-engine/scripts/extract/extract-batch-metadata.sh" ;;
      report) script="${REPO_SELF}/generation-engine/scripts/extract/extract-report-metadata.sh" ;;
      external) script="${REPO_SELF}/generation-engine/scripts/extract/extract-external-metadata.sh" ;;
      feature) script="${REPO_SELF}/generation-engine/scripts/extract/extract-feature-metadata.sh" ;;
    esac
    manifest="${MANIFESTS_DIR}/${kind}-manifest.json"
    if [ ! -f "${script}" ]; then
      any_fail=1
      detail="${detail}${kind}=missing-script; "
      continue
    fi
    if [ ! -f "${manifest}" ]; then
      detail="${detail}${kind}=skip(no-manifest); "
      continue
    fi
    kind_source_dir="$(resolve_extraction_source_dir "${kind}")"
    if [ "${kind}" = "feature" ]; then
      run_cmd bash "${script}" "${manifest}" "${MANIFESTS_DIR}/${kind}-manifest.ext.json" --source-dir "${kind_source_dir}"
    else
      run_cmd bash "${script}" "${manifest}" "${kind_source_dir}" "${MANIFESTS_DIR}/${kind}-manifest.ext.json"
    fi
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}${kind}=${LAST_RC}; "
  done

  # 画面拡張マニフェスト(api-manifestが揃った後にscreens[]へメタデータを追加する。
  # relatedApisの解決にapi-manifestを要するため、上のkindループ完了後に呼ぶ)。
  local screen_ext_script="${REPO_SELF}/generation-engine/scripts/extract/extract-screen-metadata.sh"
  local screen_raw="${MANIFESTS_DIR}/screen-manifest.json"
  if [ -f "${screen_ext_script}" ] && [ -f "${screen_raw}" ]; then
    local screen_api_m screen_ext_args
    screen_api_m="$(pick_manifest api)"
    screen_ext_args=("${screen_raw}" "${REPO}" "${MANIFESTS_DIR}/screen-manifest.ext.json")
    [ -n "${screen_api_m}" ] && screen_ext_args+=(--api-manifest "${screen_api_m}")
    run_cmd bash "${screen_ext_script}" "${screen_ext_args[@]}"
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}screen-ext=${LAST_RC}; "
  else
    detail="${detail}screen-ext=skip; "
  fi

  # メッセージ一覧マニフェスト(共通設計書配下のメッセージ定義書.mdから変換する)。
  local message_script="${REPO_SELF}/generation-engine/scripts/extract/convert-message-doc-to-manifest.sh"
  local message_layout_json message_doc
  message_layout_json="$(resolve_output_layout "${OUTPUT_DIR}")" || message_layout_json=""
  message_doc="$(output_layout_get "${message_layout_json}" messageDoc 2>/dev/null)" || message_doc=""
  [ -z "${message_doc}" ] && message_doc="docs/design/common/メッセージ定義書.md"
  message_doc="${OUTPUT_DIR}/${message_doc}"
  if [ -f "${message_script}" ] && [ -f "${message_doc}" ]; then
    run_cmd bash "${message_script}" "${message_doc}" "${MANIFESTS_DIR}/message-manifest.json"
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}message=${LAST_RC}; "
  else
    detail="${detail}message=skip; "
  fi

  # テスト観点表・テストケース一覧マニフェスト(OUTPUT_DIR配下のscreen-*/を横断集約する。
  # 対象ファイルが1件も無くてもfail-safeでunits:[]の妥当なJSONを出力する)。
  local viewpoint_script="${REPO_SELF}/generation-engine/scripts/extract/aggregate-test-viewpoints.sh"
  if [ -f "${viewpoint_script}" ]; then
    run_cmd bash "${viewpoint_script}" "${OUTPUT_DIR}" "${MANIFESTS_DIR}/test_viewpoint-manifest.json"
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}test-viewpoint=${LAST_RC}; "
  else
    any_fail=1
    detail="${detail}test-viewpoint=missing-script; "
  fi

  local testcase_script="${REPO_SELF}/generation-engine/scripts/extract/aggregate-test-cases.sh"
  if [ -f "${testcase_script}" ]; then
    run_cmd bash "${testcase_script}" "${OUTPUT_DIR}" "${MANIFESTS_DIR}/test_case-manifest.json"
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}test-case=${LAST_RC}; "
  else
    any_fail=1
    detail="${detail}test-case=missing-script; "
  fi

  if [ "${any_fail}" -eq 0 ]; then
    record_result type-extraction OK "${detail}"
  else
    record_result type-extraction FAIL "${detail}"
  fi
}

stage_unit_lists() {
  local any_fail=0 detail=""

  # 出力先は output-layout.json から解決する。project-portal 配下の日本語
  # ルートを直書きすると、unitsRoot を project-portal/lists
  # （英字）へ差し戻した現行定義と食い違い、build-portal.sh の discovery
  # （portal-catalog.json の各blueprint.discovery.glob）が生成物を見失う
  # （実測: 直書きのままcheck-coverage.shを実行すると10件すべてMISSINGになった）。
  local unit_layout_json
  unit_layout_json="$(resolve_output_layout "${OUTPUT_DIR}")" || unit_layout_json=""
  local units_root
  units_root="$(output_layout_get "${unit_layout_json}" unitsRoot 2>/dev/null)" || units_root="project-portal/lists"

  local screen_manifest="${MANIFESTS_DIR}/screen-manifest.json"
  local screen_script="${REPO_SELF}/generation-engine/scripts/unit-list/build-screen-list.sh"
  local screen_html_rel
  screen_html_rel="$(output_layout_get "${unit_layout_json}" screenListHtml 2>/dev/null)" || screen_html_rel="${units_root}/screens/画面一覧.html"
  if kind_is_excluded screen; then
    detail="${detail}screen=対象外; "
  elif [ -f "${screen_script}" ] && [ -f "${screen_manifest}" ]; then
    mkdir -p "$(dirname "${OUTPUT_DIR}/${screen_html_rel}")"
    run_cmd bash "${screen_script}" "${screen_manifest}" "${OUTPUT_DIR}/${screen_html_rel}" --source-file-root "${REPO}"
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}screen=${LAST_RC}; "
  else
    detail="${detail}screen=skip; "
  fi

  local feature_manifest="${MANIFESTS_DIR}/feature-manifest.json"
  local feature_script="${REPO_SELF}/generation-engine/scripts/unit-list/build-feature-list.sh"
  local feature_html_rel
  feature_html_rel="$(output_layout_get "${unit_layout_json}" unitListHtml 機能 2>/dev/null)" || feature_html_rel="${units_root}/features/機能一覧.html"
  if [ -f "${feature_script}" ] && [ -f "${feature_manifest}" ]; then
    mkdir -p "$(dirname "${OUTPUT_DIR}/${feature_html_rel}")"
    run_cmd bash "${feature_script}" "${feature_manifest}" "${OUTPUT_DIR}/${feature_html_rel}" --source-file-root "$(resolve_extraction_source_dir feature)"
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}feature=${LAST_RC}; "
  else
    detail="${detail}feature=skip; "
  fi

  local unit_script="${REPO_SELF}/generation-engine/scripts/unit-list/build-unit-list.sh"
  local kind manifest label html_rel
  for kind in api table batch report external; do
    case "${kind}" in
      api) label="API" ;;
      table) label="テーブル" ;;
      batch) label="バッチ" ;;
      report) label="帳票" ;;
      external) label="外部連携" ;;
    esac
    manifest="${MANIFESTS_DIR}/${kind}-manifest.json"
    html_rel="$(output_layout_get "${unit_layout_json}" unitListHtml "${label}" 2>/dev/null)" || html_rel="${units_root}/${label}一覧/${label}一覧.html"
    if [ -f "${unit_script}" ] && [ -f "${manifest}" ]; then
      mkdir -p "$(dirname "${OUTPUT_DIR}/${html_rel}")"
      run_cmd bash "${unit_script}" "${manifest}" "${OUTPUT_DIR}/${html_rel}" --unit-kind "${kind}" --source-file-root "$(resolve_extraction_source_dir "${kind}")"
      [ "${LAST_RC}" -ne 0 ] && any_fail=1
      detail="${detail}${kind}=${LAST_RC}; "
    else
      detail="${detail}${kind}=skip; "
    fi
  done

  # メッセージ一覧・テスト観点表・テストケース一覧は、portal-catalog.json の
  # 該当blueprint（message-list・test-viewpoint-list・test-case-list）が
  # discovery.glob で1段下のサブディレクトリ名を英字（message-list・
  # test-viewpoint-list・test-case-list）へ直接宣言している
  # （ディレクトリ名の方針が実態と食い違う問題を直す指示書.mdで解消済み。
  # generation-engine/scripts/extract/aggregate-test-cases.sh の設計コメントを
  # 参照）。ここでの出力先も同じ英字のサブディレクトリ名に揃える。
  local message_manifest="${MANIFESTS_DIR}/message-manifest.json"
  local message_html_rel="${units_root}/message-list/メッセージ一覧.html"
  if [ -f "${unit_script}" ] && [ -f "${message_manifest}" ]; then
    mkdir -p "$(dirname "${OUTPUT_DIR}/${message_html_rel}")"
    run_cmd bash "${unit_script}" "${message_manifest}" "${OUTPUT_DIR}/${message_html_rel}" --unit-kind message
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}message=${LAST_RC}; "
  else
    detail="${detail}message=skip; "
  fi

  local viewpoint_manifest="${MANIFESTS_DIR}/test_viewpoint-manifest.json"
  local viewpoint_html_rel="${units_root}/test-viewpoint-list/テスト観点表.html"
  if kind_is_excluded screen; then
    detail="${detail}test-viewpoint=対象外; "
  elif [ -f "${unit_script}" ] && [ -f "${viewpoint_manifest}" ]; then
    mkdir -p "$(dirname "${OUTPUT_DIR}/${viewpoint_html_rel}")"
    run_cmd bash "${unit_script}" "${viewpoint_manifest}" "${OUTPUT_DIR}/${viewpoint_html_rel}" --unit-kind test_viewpoint
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}test-viewpoint=${LAST_RC}; "
  else
    detail="${detail}test-viewpoint=skip; "
  fi

  local testcase_manifest="${MANIFESTS_DIR}/test_case-manifest.json"
  local testcase_html_rel="${units_root}/test-case-list/テストケース一覧.html"
  if kind_is_excluded screen; then
    detail="${detail}test-case=対象外; "
  elif [ -f "${unit_script}" ] && [ -f "${testcase_manifest}" ]; then
    mkdir -p "$(dirname "${OUTPUT_DIR}/${testcase_html_rel}")"
    run_cmd bash "${unit_script}" "${testcase_manifest}" "${OUTPUT_DIR}/${testcase_html_rel}" --unit-kind test_case
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}test-case=${LAST_RC}; "
  else
    detail="${detail}test-case=skip; "
  fi

  # プロジェクト全体で1冊の結合テスト仕様書を生成する。portal-catalog.json の
  # integration-test-spec が網羅の分母に含める docs/test-cases 配下の成果物であり、
  # 単位別一覧とは別の文書だが、ポータル生成より前に成果物を揃える本段で生成する。
  local integration_spec_script="${REPO_SELF}/generation-engine/scripts/generate-integration-test-spec.sh"
  local integration_spec_output="${OUTPUT_DIR}/docs/test-cases/結合テスト仕様書.md"
  if [ -f "${integration_spec_script}" ]; then
    rm -f "${integration_spec_output}"
    run_cmd bash "${integration_spec_script}" "${OUTPUT_DIR}" "検証用プロジェクト"
    if [ "${LAST_RC}" -eq 0 ]; then
      [ -s "${integration_spec_output}" ] || LAST_RC=1
      grep -q '^# 検証用プロジェクト 結合テスト仕様書$' "${integration_spec_output}" 2>/dev/null || LAST_RC=1
      grep -q '^## テストケース一覧$' "${integration_spec_output}" 2>/dev/null || LAST_RC=1
    fi
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}integration-test-spec=${LAST_RC}; "
  else
    any_fail=1
    detail="${detail}integration-test-spec=missing; "
  fi

  if [ "${any_fail}" -eq 0 ]; then
    record_result unit-lists OK "${detail}"
  else
    record_result unit-lists FAIL "${detail}"
  fi
}

stage_matrix() {
  local any_fail=0 detail=""
  if kind_is_excluded screen; then
    record_result matrix OK "画面依存の5納品物=対象外"
    return 0
  fi
  local data_script="${REPO_SELF}/generation-engine/scripts/extract/build-matrix-data.sh"
  local pages_script="${REPO_SELF}/generation-engine/scripts/matrix/build-matrix-pages.sh"
  local convert_script="${REPO_SELF}/generation-engine/scripts/extract/build-permission-function-data.sh"
  local screen_m api_m table_m feature_m matrix_out
  # 出力先は output-layout.json から解決する。matrixDir 配下に「対応表」のような
  # 旧来の日本語ルートを直書きすると、matrixDir を project-portal/matrices
  # （英字）へ揃えた現行定義と食い違い、build-portal.sh の discovery
  # （portal-catalog.json の各blueprint.discovery.glob）が生成物を見失う
  # （stage_unit_lists の units_root と同じ理由。一覧の置き場が三者三様に
  # なっている問題を直す指示書.md の対応を踏襲する）。
  local matrix_layout_json matrix_root
  matrix_layout_json="$(resolve_output_layout "${OUTPUT_DIR}")" || matrix_layout_json=""
  matrix_root="$(output_layout_get "${matrix_layout_json}" matrixDir 2>/dev/null)" || matrix_root="project-portal/matrices"
  screen_m="$(pick_manifest screen)"
  api_m="$(pick_manifest api)"
  table_m="$(pick_manifest table)"
  feature_m="$(pick_manifest feature)"
  matrix_out="${OUTPUT_DIR}/.matrix-data"
  mkdir -p "${matrix_out}"

  if [ -f "${data_script}" ] && [ -n "${screen_m}" ] && [ -n "${api_m}" ]; then
    local args=("${matrix_out}" --screen-manifest "${screen_m}" --api-manifest "${api_m}")
    [ -n "${table_m}" ] && args+=(--table-manifest "${table_m}")
    [ -n "${feature_m}" ] && args+=(--feature-manifest "${feature_m}")
    run_cmd bash "${data_script}" "${args[@]}"
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}data=${LAST_RC}; "
  else
    any_fail=1
    detail="${detail}data=skip(missing-input); "
  fi

  # 権限機能マトリクスは permission-matrix.json をそのまま build-matrix-pages.sh
  # permission-function へ渡せない(roles と functions を要求するが permission-matrix.json
  # は functions を持たない)。build-permission-function-data.sh で変換した
  # permission-function-matrix.json を渡す(rebuild-screen-derived-pages.sh の呼び出し順序に倣う)。
  local pf_data="${matrix_out}/permission-matrix.json"
  local pf_out="${matrix_out}/permission-function-matrix.json"
  local pf_ready=0
  if [ -f "${convert_script}" ] && [ -f "${pf_data}" ]; then
    local pf_generated_at pf_hash
    pf_generated_at="$(jq -r '.generatedAt // empty' "${pf_data}" 2>/dev/null)"
    [ -n "${pf_generated_at}" ] || pf_generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    # generatedAt(生成時刻)を含んだままハッシュを取ると、同じ入力でも実行の
    # たびに値が変わる。rebuild-screen-derived-pages.sh が raw manifest に
    # manifestContentHash を含めさせない(時刻由来の値をハッシュ対象から除く)のと
    # 同じ考え方で、ここでも時刻由来のフィールドを除いてから計算する。
    if command -v shasum >/dev/null 2>&1; then
      pf_hash="$(jq -cjS 'del(.generatedAt, .manifestContentHash)' "${pf_data}" | shasum -a 256 | awk '{print $1}')"
    else
      pf_hash="$(jq -cjS 'del(.generatedAt, .manifestContentHash)' "${pf_data}" | sha256sum | awk '{print $1}')"
    fi
    run_cmd bash "${convert_script}" "${pf_data}" "${pf_out}" \
      --generated-at "${pf_generated_at}" --manifest-content-hash "${pf_hash}"
    if [ "${LAST_RC}" -eq 0 ]; then
      pf_ready=1
    else
      any_fail=1
      detail="${detail}permission-function-convert=${LAST_RC}; "
    fi
  else
    detail="${detail}permission-function-convert=skip; "
  fi

  # 確認事項質問票データ(推定名称・要手動確認・権限未設定を、種別横断の
  # unit-manifest群とpermission-matrix.jsonから集約する。画面設計単位ルートに
  # 要確認事項台帳があれば、パスの辞書順で収集して入力する)。
  local survey_script="${REPO_SELF}/generation-engine/scripts/extract/build-confirmation-survey-data.sh"
  local survey_out="${matrix_out}/confirmation-survey.json"
  local survey_ready=0
  if [ -f "${survey_script}" ]; then
    local survey_args=("${survey_out}")
    local batch_m report_m external_m sm
    local ledger_collect_rc
    batch_m="$(pick_manifest batch)"
    report_m="$(pick_manifest report)"
    external_m="$(pick_manifest external)"
    for sm in "${screen_m}" "${api_m}" "${table_m}" "${feature_m}" "${batch_m}" "${report_m}" "${external_m}"; do
      [ -n "${sm}" ] && survey_args+=(--unit-manifest "${sm}")
    done
    [ -f "${pf_data}" ] && survey_args+=(--permission-matrix "${pf_data}")
    if build_confirmation_ledger_args "${OUTPUT_DIR}"; then
      survey_args+=("${SURVEY_LEDGER_ARGS[@]}")
      run_cmd bash "${survey_script}" "${survey_args[@]}"
      if [ "${LAST_RC}" -eq 0 ]; then
        survey_ready=1
      else
        any_fail=1
      fi
      detail="${detail}confirmation-survey-data=${LAST_RC}; "
    else
      ledger_collect_rc=$?
      any_fail=1
      detail="${detail}confirmation-ledger-collect=${ledger_collect_rc}; "
      detail="${detail}confirmation-survey-data=skip; "
    fi
  else
    any_fail=1
    detail="${detail}confirmation-survey-data=missing-script; "
  fi

  if [ -f "${pages_script}" ]; then
    local pt pt_file pt_out pt_label
    for pt in permission-screen permission-function crud traceability confirmation-survey; do
      case "${pt}" in
        permission-screen) pt_file="${matrix_out}/permission-matrix.json"; pt_label="権限画面マトリクス" ;;
        permission-function)
          if [ "${pf_ready}" -eq 1 ]; then
            pt_file="${pf_out}"
          else
            pt_file=""
          fi
          pt_label="権限機能マトリクス"
          ;;
        crud) pt_file="${matrix_out}/crud-matrix.json"; pt_label="CRUD図" ;;
        traceability) pt_file="${matrix_out}/traceability.json"; pt_label="画面-API-テーブル対応表" ;;
        confirmation-survey)
          if [ "${survey_ready}" -eq 1 ]; then
            pt_file="${survey_out}"
          else
            pt_file=""
          fi
          pt_label="確認事項質問票"
          ;;
      esac
      pt_out="${OUTPUT_DIR}/${matrix_root}/${pt}/${pt_label}.html"
      mkdir -p "${OUTPUT_DIR}/${matrix_root}/${pt}"
      if [ -n "${pt_file}" ] && [ -f "${pt_file}" ]; then
        run_cmd bash "${pages_script}" "${pt}" "${pt_file}" "${pt_out}"
        [ "${LAST_RC}" -ne 0 ] && any_fail=1
        detail="${detail}${pt}=${LAST_RC}; "
      else
        detail="${detail}${pt}=skip; "
      fi
    done
  else
    any_fail=1
    detail="${detail}pages-script=missing; "
  fi

  if [ "${any_fail}" -eq 0 ]; then
    record_result matrix OK "${detail}"
  else
    record_result matrix FAIL "${detail}"
  fi
}

stage_design_pages() {
  local any_fail=0 detail=""
  local tok_script="${REPO_SELF}/generation-engine/scripts/extract/extract-design-tokens-from-designmd.sh"
  local comp_script="${REPO_SELF}/generation-engine/scripts/extract/extract-component-inventory.sh"
  local icon_script="${REPO_SELF}/generation-engine/scripts/extract/extract-icon-usage.sh"
  local detail_script="${REPO_SELF}/generation-engine/scripts/detail-pages/build-detail-page.sh"
  # 共通の DESIGN.md は ${REPO}(原本コード)直下ではなく、出力先の commonRoot
  # (output-layout.json の宣言。既定 docs/design/common)配下に配置される
  # (prepare-verification-input.sh の COMMON_ROOT と同じ解決経路)。
  local design_layout_json common_root
  design_layout_json="$(resolve_output_layout "${OUTPUT_DIR}")" || design_layout_json=""
  common_root="$(output_layout_get "${design_layout_json}" commonRoot 2>/dev/null)" || common_root=""
  [ -z "${common_root}" ] && common_root="docs/design/common"
  # foundationDir・diagramDir も同じ理由で output-layout.json から解決する
  # （stage_matrix の matrix_root と同じ対応。「基盤」「図」のような
  # 旧来の日本語ルートを直書きすると現行定義と食い違う）。
  local foundation_root diagram_root
  foundation_root="$(output_layout_get "${design_layout_json}" foundationDir 2>/dev/null)" || foundation_root="project-portal/foundation"
  diagram_root="$(output_layout_get "${design_layout_json}" diagramDir 2>/dev/null)" || diagram_root="project-portal/diagrams"
  local design_md="${OUTPUT_DIR}/${common_root}/DESIGN.md"
  local tok_json="${OUTPUT_DIR}/.design-tokens.json"
  local comp_json="${OUTPUT_DIR}/.component-inventory.json"
  local icon_json="${OUTPUT_DIR}/.icon-usage.json"

  if kind_is_excluded screen; then
    detail="${detail}tokens=対象外; "
  elif [ -f "${tok_script}" ] && [ -f "${design_md}" ]; then
    run_cmd bash "${tok_script}" "${design_md}" "${tok_json}"
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}tokens=${LAST_RC}; "
  else
    detail="${detail}tokens=skip; "
  fi

  if kind_is_excluded screen; then
    detail="${detail}components=対象外; "
  elif [ -f "${comp_script}" ]; then
    run_cmd bash "${comp_script}" "${REPO}" "${comp_json}"
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}components=${LAST_RC}; "
  else
    any_fail=1
    detail="${detail}components=missing-script; "
  fi

  if kind_is_excluded screen; then
    detail="${detail}icons=対象外; "
  elif [ -f "${icon_script}" ]; then
    run_cmd bash "${icon_script}" "${REPO}" "${icon_json}"
    [ "${LAST_RC}" -ne 0 ] && any_fail=1
    detail="${detail}icons=${LAST_RC}; "
  else
    any_fail=1
    detail="${detail}icons=missing-script; "
  fi

  if [ -f "${detail_script}" ]; then
    local foundation_dir="${OUTPUT_DIR}/${foundation_root}"
    mkdir -p "${foundation_dir}"
    if [ -f "${tok_json}" ]; then
      run_cmd bash "${detail_script}" "${tok_json}" "${foundation_dir}" --page design-system --portal-dir "${PORTAL_DIR}"
      [ "${LAST_RC}" -ne 0 ] && any_fail=1
      detail="${detail}page-design-system=${LAST_RC}; "
    fi
    if [ -f "${comp_json}" ]; then
      run_cmd bash "${detail_script}" "${comp_json}" "${foundation_dir}" --page component-inventory --portal-dir "${PORTAL_DIR}"
      [ "${LAST_RC}" -ne 0 ] && any_fail=1
      detail="${detail}page-components=${LAST_RC}; "
    fi
    if [ -f "${icon_json}" ]; then
      run_cmd bash "${detail_script}" "${icon_json}" "${foundation_dir}" --page icon-catalog --portal-dir "${PORTAL_DIR}"
      [ "${LAST_RC}" -ne 0 ] && any_fail=1
      detail="${detail}page-icons=${LAST_RC}; "
    fi

    # 関連図3種(状態遷移図・ER図・画面遷移図)。抽出器はいずれも output_dir 引数に
    # ${OUTPUT_DIR}(prepare-verification-input.sh が設計文書を配置した先)を渡す。
    # entity-state/er は材料が無くても(データ設計.md・テーブル定義書.mdが雛形の
    # プレースホルダ行のみ等)WARNを出しつつexit 0で空のpage-data.jsonを書くため、
    # 段を失敗にしない(捏造しない設計をそのまま活かす)。transitionはscreen-manifest.json
    # 自体が不在・不正な場合のみexit 1になる(材料が無いのとは別の失敗として扱う)。
    local diagrams_dir="${OUTPUT_DIR}/${diagram_root}"
    mkdir -p "${diagrams_dir}"

    local es_script="${REPO_SELF}/generation-engine/scripts/portal-input/extract-entity-state-page-data.sh"
    local es_json="${OUTPUT_DIR}/.entity-state-page-data.json"
    if [ -f "${es_script}" ]; then
      run_cmd bash "${es_script}" "${OUTPUT_DIR}" "${es_json}"
      if [ "${LAST_RC}" -eq 0 ] && [ -f "${es_json}" ]; then
        run_cmd bash "${detail_script}" "${es_json}" "${diagrams_dir}" --page entity-state --portal-dir "${PORTAL_DIR}"
        [ "${LAST_RC}" -ne 0 ] && any_fail=1
        detail="${detail}page-entity-state=${LAST_RC}; "
      else
        any_fail=1
        detail="${detail}extract-entity-state=${LAST_RC}; "
      fi
    else
      any_fail=1
      detail="${detail}extract-entity-state=missing-script; "
    fi

    local er_script="${REPO_SELF}/generation-engine/scripts/portal-input/extract-er-page-data.sh"
    local er_json="${OUTPUT_DIR}/.er-page-data.json"
    if [ -f "${er_script}" ]; then
      run_cmd bash "${er_script}" "${OUTPUT_DIR}" "${er_json}"
      if [ "${LAST_RC}" -eq 0 ] && [ -f "${er_json}" ]; then
        run_cmd bash "${detail_script}" "${er_json}" "${diagrams_dir}" --page er --portal-dir "${PORTAL_DIR}"
        [ "${LAST_RC}" -ne 0 ] && any_fail=1
        detail="${detail}page-er=${LAST_RC}; "
      else
        any_fail=1
        detail="${detail}extract-er=${LAST_RC}; "
      fi
    else
      any_fail=1
      detail="${detail}extract-er=missing-script; "
    fi

    local tr_script="${REPO_SELF}/generation-engine/scripts/portal-input/extract-transition-page-data.sh"
    local tr_json="${OUTPUT_DIR}/.transition-page-data.json"
    if kind_is_excluded screen; then
      detail="${detail}page-transition=対象外; "
    elif [ -f "${tr_script}" ]; then
      run_cmd bash "${tr_script}" "${OUTPUT_DIR}" "${tr_json}"
      if [ "${LAST_RC}" -eq 0 ] && [ -f "${tr_json}" ]; then
        run_cmd bash "${detail_script}" "${tr_json}" "${diagrams_dir}" --page transition --portal-dir "${PORTAL_DIR}"
        [ "${LAST_RC}" -ne 0 ] && any_fail=1
        detail="${detail}page-transition=${LAST_RC}; "
      else
        any_fail=1
        detail="${detail}extract-transition=${LAST_RC}; "
      fi
    else
      any_fail=1
      detail="${detail}extract-transition=missing-script; "
    fi
  else
    any_fail=1
    detail="${detail}build-detail-page=missing-script; "
  fi

  if [ "${any_fail}" -eq 0 ]; then
    record_result design-pages OK "${detail}"
  else
    record_result design-pages FAIL "${detail}"
  fi
}

stage_rules_scaffold() {
  local script="${REPO_SELF}/generation-engine/scripts/rules/scaffold-rule-definitions.sh"
  if [ ! -f "${script}" ]; then
    record_result rules-scaffold FAIL "スクリプトが存在しない: ${script}"
    return 0
  fi
  # --apply を条件分岐なしで常に付ける理由: scaffold-rule-definitions.sh は --apply を
  # 付け忘れると規約が0件のまま試行実行(dry-run)で終わる。この事故は
  # .claude/rules/scoped/portal/page-conventions/rule.md の設計判断節に既知の事故パターン
  # として記録済みだが、本スクリプト自身には理由が無かった。本スクリプトは第3層(一気通貫)を
  # 無人で繰り返し実行する経路であり、呼び出し側が毎回フラグを判断する余地を残すと
  # 同じ事故を再現しうるため、この段の呼び出しからは選択の余地を無くしてある。
  # 環境依存: しない(呼び出し手順の問題であり実行環境には依存しない)。
  # 過去に消えて再発した経緯: 記録なし(この段自体が新設時から --apply 固定で書かれている)。
  run_cmd bash "${script}" "${OUTPUT_DIR}" --apply
  if [ "${LAST_RC}" -ne 0 ]; then
    record_result rules-scaffold FAIL "規約定義の展開=終了コード ${LAST_RC}"
    return 0
  fi

  # 基盤情報5件は画面の有無に依存しない。規約ページは展開済みの規約を入力にするため、
  # scaffoldの直後、portal-buildの直前で生成する。
  local layout_json common_root manifests_root foundation_dir detail_dir generated_at
  layout_json="$(resolve_output_layout "${OUTPUT_DIR}")" || layout_json=""
  common_root="$(output_layout_get "${layout_json}" commonRoot 2>/dev/null)" || common_root="docs/design/common"
  manifests_root="$(output_layout_get "${layout_json}" manifestsRoot 2>/dev/null)" || manifests_root="manifests"
  foundation_dir="${OUTPUT_DIR}/project-portal/foundation"
  detail_dir="${OUTPUT_DIR}/${manifests_root}/detail-pages"
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "${OUTPUT_DIR}/${common_root}" "${foundation_dir}" "${detail_dir}"

  cat > "${OUTPUT_DIR}/${common_root}/アーキテクチャ調査書.md" <<EOF
# アーキテクチャ調査書

## 調査メタ

対象リポジトリ \`$(basename "${REPO}")\` を生成の一連で調査した記録です。

## 技術スタック

| 項目 | 内容 | 参照先 |
|---|---|---|
| 定義ファイル | 実在しない（主要な技術定義ファイルを検出していません） | \`$(basename "${REPO}")\` |

## ビルドと起動

リポジトリ全体を対象とする単一のビルドコマンドと起動コマンドは検出していません。

## ディレクトリ責務マップ

| ディレクトリ | 責務 | 参照先 |
|---|---|---|
| \`.\` | 調査対象のルート | \`$(basename "${REPO}")\` |
EOF

  jq -n --arg generatedAt "${generated_at}" --arg source "${OUTPUT_DIR}/${common_root}/アーキテクチャ調査書.md#技術スタック" '{
    pageKind:"techstack", generatedAt:$generatedAt, title:"技術スタック",
    description:"対象リポジトリから確認できた技術定義を整理した結果です。",
    tiles:[], columns:["項目","内容","根拠"], rows:[],
    absentRows:[{item:"技術定義",value:"実在しない（主要な技術定義ファイルを検出していません）",sourceRef:$source}]
  }' > "${detail_dir}/techstack-page-data.json"
  jq -n --arg generatedAt "${generated_at}" '{
    pageKind:"env", generatedAt:$generatedAt, title:"環境構築手順",
    description:"対象リポジトリから確認できた環境構築情報を整理した結果です。",
    prerequisites:[], steps:[{order:1,command:"該当なし",note:"単一の環境構築コマンドは検出していません"}], allocations:[]
  }' > "${detail_dir}/env-page-data.json"
  jq -n --arg generatedAt "${generated_at}" '{
    pageKind:"release-notes", generatedAt:$generatedAt, title:"リリースノート",
    description:"対象リポジトリの変更履歴です。", releases:[]
  }' > "${detail_dir}/release-notes-page-data.json"
  jq -n --arg generatedAt "${generated_at}" '{
    pageKind:"glossary", generatedAt:$generatedAt, title:"用語辞書",
    description:"承認済みの用語を示します。現在の承認済み用語は0件です。",
    projectionVersion:"0.2", glossarySchemaVersion:"1.0.0", glossaryContentVersion:"0.0.0",
    categories:[
      {key:"entity",label:"エンティティ"},{key:"attribute",label:"属性"},
      {key:"value",label:"値"},{key:"process",label:"処理"},
      {key:"event",label:"イベント"},{key:"role",label:"役割"},
      {key:"rule",label:"ルール"},{key:"metric",label:"指標"}
    ], terms:[]
  }' > "${detail_dir}/glossary-page-data.json"

  local detail_script="${REPO_SELF}/generation-engine/scripts/detail-pages/build-detail-page.sh"
  local validate_script="${REPO_SELF}/generation-engine/scripts/detail-pages/validate-page-data.sh"
  local any_fail=0 page
  for page in techstack env release-notes; do
    run_cmd bash "${validate_script}" "${detail_dir}/${page}-page-data.json" --target-repo "${REPO}"
    if [ "${LAST_RC}" -eq 0 ]; then
      run_cmd bash "${detail_script}" "${detail_dir}/${page}-page-data.json" "${foundation_dir}" --page "${page}" --portal-dir "${PORTAL_DIR}"
    fi
    [ "${LAST_RC}" -eq 0 ] || any_fail=1
  done

  local rule_map_script="${REPO_SELF}/generation-engine/scripts/rules/build-rule-flow-map.sh"
  run_cmd bash "${rule_map_script}" "${REPO_SELF}/delivery-payload/references/rule-taxonomy.json" \
    "${foundation_dir}/規約とフローの対応.html" --generated-at "${generated_at}" \
    --target-root "${OUTPUT_DIR}/docs/rules"
  [ "${LAST_RC}" -eq 0 ] || any_fail=1

  if [ "${any_fail}" -eq 0 ]; then
    record_result rules-scaffold OK "規約定義を展開し、画面非依存の基盤情報5件を生成した"
  else
    record_result rules-scaffold FAIL "規約定義は展開したが、画面非依存の基盤情報生成に失敗した"
  fi
}

stage_portal_build() {
  local script="${REPO_SELF}/generation-engine/scripts/build-portal.sh"
  if [ ! -f "${script}" ]; then
    record_result portal-build FAIL "スクリプトが存在しない: ${script}"
    return 0
  fi
  run_cmd bash "${script}" "${REPO}" "${OUTPUT_DIR}" "${PORTAL_DIR}"
  if [ "${LAST_RC}" -ne 0 ]; then
    record_result portal-build FAIL "終了コード ${LAST_RC}"
    return 0
  fi

  # 対象にAI設定資産が無い場合も、走査結果0件を未生成と区別できるページにする。
  # build-portal.shの通常生成後に決定的抽出器とページ生成器を呼び、portal-onlyで
  # 新しいページを索引へ反映する。資産が実在する場合も同じ経路で再生成する。
  local layout_json manifests_root foundation_root ai_data ai_output
  local extract_ai_script="${REPO_SELF}/generation-engine/scripts/extract/extract-ai-assets.sh"
  local matrix_script="${REPO_SELF}/generation-engine/scripts/matrix/build-matrix-pages.sh"
  layout_json="$(resolve_output_layout "${OUTPUT_DIR}")" || layout_json=""
  manifests_root="$(output_layout_get "${layout_json}" manifestsRoot 2>/dev/null)" || manifests_root="manifests"
  foundation_root="$(output_layout_get "${layout_json}" foundationDir 2>/dev/null)" || foundation_root="project-portal/foundation"
  ai_data="${OUTPUT_DIR}/${manifests_root}/ai-assets.json"
  ai_output="${OUTPUT_DIR}/${foundation_root}/AI設定資産.html"
  run_cmd bash "${extract_ai_script}" "${REPO}" "${ai_data}"
  if [ "${LAST_RC}" -eq 0 ]; then
    run_cmd bash "${matrix_script}" ai-assets "${ai_data}" "${ai_output}" \
      --portal-dir "${PORTAL_DIR}"
  fi
  if [ "${LAST_RC}" -eq 0 ]; then
    run_cmd bash "${script}" "${REPO}" "${OUTPUT_DIR}" "${PORTAL_DIR}" --portal-only
  fi
  if [ "${LAST_RC}" -eq 0 ]; then
    record_result portal-build OK "ポータルを生成し、AI設定資産の走査結果を反映した"
  else
    record_result portal-build FAIL "AI設定資産の反映=終了コード ${LAST_RC}"
  fi
}

stage_aggregate() {
  record_result aggregate OK "各段の結果を集計した"
}

run_stage() {
  local key="$1"
  case "${key}" in
    prepare-output) stage_prepare_output ;;
    prepare-input) stage_prepare_input ;;
    build-manifests) stage_build_manifests ;;
    type-extraction) stage_type_extraction ;;
    unit-lists) stage_unit_lists ;;
    matrix) stage_matrix ;;
    design-pages) stage_design_pages ;;
    rules-scaffold) stage_rules_scaffold ;;
    portal-build) stage_portal_build ;;
    aggregate) stage_aggregate ;;
  esac
}

print_summary() {
  local i total=0 okc=0 failc=0 skipc=0
  for i in "${!RESULT_KEYS[@]}"; do
    printf '[%s] %s — %s\n' "${RESULT_STATUS[$i]}" "$(stage_name "${RESULT_KEYS[$i]}")" "${RESULT_DETAIL[$i]}"
    total=$((total + 1))
    case "${RESULT_STATUS[$i]}" in
      OK) okc=$((okc + 1)) ;;
      FAIL) failc=$((failc + 1)) ;;
      SKIP) skipc=$((skipc + 1)) ;;
    esac
  done
  local file_count
  file_count="$(find "${OUTPUT_DIR}" -type f 2>/dev/null | wc -l | tr -d ' ')"
  printf '段 %s / 成功 %s / 失敗 %s / スキップ %s\n' "${total}" "${okc}" "${failc}" "${skipc}"
  printf '生成ファイル数 %s\n' "${file_count}"
}

# ---- 出力先の版管理下チェック --------------------------------------------

_nearest_existing_ancestor() {
  local p="$1"
  case "${p}" in
    /*) : ;;
    *) p="$(pwd)/${p}" ;;
  esac
  while [ ! -d "${p}" ] && [ "${p}" != "/" ]; do
    p="$(dirname "${p}")"
  done
  printf '%s\n' "${p}"
}

is_output_inside_git() {
  local target="$1" anchor
  anchor="$(_nearest_existing_ancestor "${target}")"
  git -C "${anchor}" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# --output のパスを実体のパスへ解決する。macOS の ${TMPDIR:-/tmp} は
# /private/tmp へのシンボリックリンクであり、build-portal.sh は祖先を辿って
# シンボリックリンクを含むパスを拒否するため、以降の段へ渡す前に一度だけ解決する。
# realpath コマンドはこの環境に無い可能性があるため使わない。
resolve_output_dir_realpath() {
  local path="$1"
  mkdir -p "${path}" 2>/dev/null || return 1
  ( cd "${path}" 2>/dev/null && pwd -P )
}

# ---- self-test -----------------------------------------------------------

self_test() {
  local run=0 ok=0 ng=0
  _case_pass() { run=$((run + 1)); ok=$((ok + 1)); echo "[PASS] $1 — $2"; }
  _case_fail() { run=$((run + 1)); ng=$((ng + 1)); echo "[FAIL] $1 — $2" >&2; }

  local repo_root
  repo_root="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

  local tmp inside_parent
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/run-layer-full-pipeline-self-test.XXXXXX")" || {
    echo "self-test: 一時ディレクトリを作成できない" >&2
    return 1
  }
  tmp="$(cd "${tmp}" && pwd)"
  # 拒否-版管理下 の下ごしらえ。配布物のルート配下ではなく、この検査のために
  # 作った版管理のリポジトリを使う。配布物のルート配下を使うと、判定が
  # is_output_inside_git の祖先探索に頼るため、周囲にリポジトリがあるかどうかで
  # 結果が変わる（改善課題 1-54: 置き場所によって結果が変わる）。
  inside_parent="$(cd "${tmp}" && pwd -P)/inside-repo"
  mkdir -p "${inside_parent}"
  git -C "${inside_parent}" init -q
  trap 'rm -rf "${tmp}" "${inside_parent}" 2>/dev/null' EXIT

  # 引数-出力先必須
  local rc
  bash "${SELF_PATH}" >/dev/null 2>&1
  rc=$?
  if [ "${rc}" -eq 1 ]; then
    _case_pass "引数-出力先必須" "--output 無指定で exit 1"
  else
    _case_fail "引数-出力先必須" "exit ${rc} (期待値 1)"
  fi

  # 拒否-版管理下
  local inside_path="${inside_parent}/subdir"
  bash "${SELF_PATH}" --output "${inside_path}" >/dev/null 2>&1
  rc=$?
  if [ "${rc}" -eq 1 ] && [ ! -d "${inside_path}" ]; then
    _case_pass "拒否-版管理下" "git リポジトリ内のパスを exit 1 で拒否し作成しなかった"
  else
    _case_fail "拒否-版管理下" "拒否できなかった(rc=${rc})"
  fi

  # 段-定義数
  local n
  n="$(stage_keys | grep -c .)"
  if [ "${n}" -eq 10 ]; then
    _case_pass "段-定義数" "10段(実測 ${n})"
  else
    _case_fail "段-定義数" "10段ではない(実測 ${n})"
  fi

  # 段-規約適用フラグ
  local block
  block="$(sed -n '/^stage_rules_scaffold()/,/^}/p' "${SELF_PATH}")"
  if printf '%s' "${block}" | grep -q 'scaffold-rule-definitions.sh' \
    && printf '%s' "${block}" | grep -q -- '--apply'; then
    _case_pass "段-規約適用フラグ" "規約段の呼び出しに --apply を含む"
  else
    _case_fail "段-規約適用フラグ" "--apply が見つからない"
  fi

  # 版-記録
  # 配布物のルートではなく、この検査のために作った版管理のリポジトリで確かめる。
  # 配布物のルートを使うと、配布物が版管理の下に置かれているかどうかで結果が
  # 変わる（改善課題 1-54: 置き場所によって結果が変わる）。配布物が版管理の下に
  # 無い場合に unknown を返すことは verification-env.sh の自己テストが受け持つ。
  local ver ver_repo
  ver_repo="$(cd "${tmp}" && pwd -P)/ver-repo"
  mkdir -p "${ver_repo}"
  git -C "${ver_repo}" init -q
  printf 'x\n' > "${ver_repo}/seed.txt"
  git -C "${ver_repo}" add seed.txt
  git -C "${ver_repo}" -c user.name=t -c user.email=t@example.com commit -q -m seed
  ver="$(verification_env_record_version "${ver_repo}")"
  if [[ "${ver}" =~ ^[0-9a-f]{40}$ ]]; then
    _case_pass "版-記録" "40文字のコミットハッシュを取得(${ver})"
  else
    _case_fail "版-記録" "40文字のハッシュではない(${ver})"
  fi

  # 依存-スクリプト実在
  local missing=0 s
  while IFS= read -r s; do
    [ -z "${s}" ] && continue
    [ -f "${s}" ] || missing=$((missing + 1))
  done <<DEPS
$(dependency_scripts "${repo_root}")
DEPS
  if [ "${missing}" -eq 0 ]; then
    _case_pass "依存-スクリプト実在" "全依存スクリプトが実在する"
  else
    _case_fail "依存-スクリプト実在" "${missing} 件が不在"
  fi

  # 入力元-共通設計書
  local design_block
  design_block="$(sed -n '/^stage_design_pages()/,/^}/p' "${SELF_PATH}")"
  if printf '%s' "${design_block}" | grep -q 'OUTPUT_DIR' \
    && printf '%s' "${design_block}" | grep -q 'commonRoot' \
    && ! printf '%s' "${design_block}" | grep -Eq '\$\{REPO\}/DESIGN\.md'; then
    _case_pass "入力元-共通設計書" "デザイン系の段が参照するパスが出力先の commonRoot 配下になっている"
  else
    _case_fail "入力元-共通設計書" "\${REPO}/DESIGN.md を直接参照している、または OUTPUT_DIR/commonRoot 経由になっていない"
  fi

  # 解決-実体パス
  local real_target link_dir resolved expected
  real_target="${tmp}/rlfp-real-target"
  link_dir="${tmp}/rlfp-link-to-real"
  mkdir -p "${real_target}"
  ln -s "${real_target}" "${link_dir}"
  resolved="$(resolve_output_dir_realpath "${link_dir}/sub")"
  expected="$(cd "${real_target}" && pwd -P)/sub"
  if [ -n "${resolved}" ] && [ "${resolved}" = "${expected}" ] && [ "${resolved}" != "${link_dir}/sub" ]; then
    _case_pass "解決-実体パス" "シンボリックリンクを含むパスが実体のパスへ解決された(${resolved})"
  else
    _case_fail "解決-実体パス" "実体パスへ解決できない(取得値=${resolved} 期待値=${expected})"
  fi

  # 続行-画面検出失敗
  local scr_test_dir scr_manifest
  scr_test_dir="${tmp}/rlfp-screen-fallback"
  mkdir -p "${scr_test_dir}"
  scr_manifest="${scr_test_dir}/screen-manifest.json"
  REPO="${scr_test_dir}" write_empty_screen_manifest "${scr_manifest}"

  if [ -f "${scr_manifest}" ] \
    && jq -e '(.detectionSummary.unitCount == 0) and (.screens == []) and ((.note // "") | length > 0)' "${scr_manifest}" >/dev/null 2>&1; then
    _case_pass "続行-画面検出失敗" "空の画面マニフェストが妥当なJSONで書き出され後続が進める"
  else
    _case_fail "続行-画面検出失敗" "空の画面マニフェストが妥当な形で書き出されなかった"
  fi

  # 出力先-対応表サブフォルダ
  # matrixDir を output-layout.json から動的解決していること・出力先が
  # <matrixDir>/${pt}/${pt_label}.html の形（ディレクトリ名は英字のkind、
  # ファイル名はJapaneseラベル）であることを検査する（matrixDir に「対応表」の
  # ような旧来の日本語ルートの直書きが復活していないか。ディレクトリ名の方針が
  # 実態と食い違う問題を直す指示書.md でportal-catalog.jsonのdir・discovery.glob
  # を英字へ揃え、stage_matrixの出力先もこれに追従させた）。
  local matrix_block
  matrix_block="$(sed -n '/^stage_matrix()/,/^}/p' "${SELF_PATH}")"
  if printf '%s' "${matrix_block}" | grep -Eq 'output_layout_get "\$\{matrix_layout_json\}" matrixDir' \
    && printf '%s' "${matrix_block}" | grep -Eq '\$\{OUTPUT_DIR\}/\$\{matrix_root\}/\$\{pt\}/\$\{pt_label\}\.html' \
    && ! printf '%s' "${matrix_block}" | grep -Eq 'PORTAL_DIR\}/対応表'; then
    _case_pass "出力先-対応表サブフォルダ" "対応表の出力先が matrixDir から動的解決された <matrixDir>/<kind>/<ラベル>.html の形になっている"
  else
    _case_fail "出力先-対応表サブフォルダ" "対応表の出力先が matrixDir の動的解決を経由していない、または旧来の直書きが残っている"
  fi

  # 変換-権限機能
  if printf '%s' "${matrix_block}" | grep -q 'build-permission-function-data.sh'; then
    _case_pass "変換-権限機能" "権限機能マトリクスの経路に build-permission-function-data の呼び出しが含まれる"
  else
    _case_fail "変換-権限機能" "build-permission-function-data.sh の呼び出しが見つからない"
  fi

  # 収集-確認事項台帳(空白を含む出力先でも辞書順と引数形式を保持する)
  local ledger_test_dir ledger_screen_root ledger_expected_a ledger_expected_b
  ledger_test_dir="${tmp}/ledger collection with spaces"
  ledger_screen_root="custom-screen-units"
  ledger_expected_a="${ledger_test_dir}/${ledger_screen_root}/screen-a/要確認事項台帳.json"
  ledger_expected_b="${ledger_test_dir}/${ledger_screen_root}/screen-z/要確認事項台帳.json"
  mkdir -p "$(dirname "${ledger_expected_a}")" "$(dirname "${ledger_expected_b}")"
  cat > "${ledger_test_dir}/output-layout.json" <<JSON
{"specVersion":1,"layout":{"screenUnitRoot":"${ledger_screen_root}"}}
JSON
  : > "${ledger_expected_a}"
  : > "${ledger_expected_b}"
  if build_confirmation_ledger_args "${ledger_test_dir}" \
    && [ "${#SURVEY_LEDGER_ARGS[@]}" -eq 4 ] \
    && [ "${SURVEY_LEDGER_ARGS[0]}" = "--confirmation-ledger" ] \
    && [ "${SURVEY_LEDGER_ARGS[1]}" = "${ledger_expected_a}" ] \
    && [ "${SURVEY_LEDGER_ARGS[2]}" = "--confirmation-ledger" ] \
    && [ "${SURVEY_LEDGER_ARGS[3]}" = "${ledger_expected_b}" ]; then
    _case_pass "収集-確認事項台帳" "辞書順の2台帳を空白を壊さず4引数へ変換した"
  else
    _case_fail "収集-確認事項台帳" "台帳の順序・空白保持・引数形式が一致しない"
  fi

  # 収集-台帳0件
  local ledger_empty_dir
  ledger_empty_dir="${tmp}/ledger empty with spaces"
  mkdir -p "${ledger_empty_dir}/${ledger_screen_root}"
  cat > "${ledger_empty_dir}/output-layout.json" <<JSON
{"specVersion":1,"layout":{"screenUnitRoot":"${ledger_screen_root}"}}
JSON
  if build_confirmation_ledger_args "${ledger_empty_dir}" \
    && [ "${#SURVEY_LEDGER_ARGS[@]}" -eq 0 ]; then
    _case_pass "収集-台帳0件" "台帳0件を成功・空配列として扱った"
  else
    _case_fail "収集-台帳0件" "台帳0件が失敗した、または引数が残った"
  fi

  # 収集-不正出力レイアウト
  local ledger_invalid_dir
  ledger_invalid_dir="${tmp}/ledger-invalid-layout"
  mkdir -p "${ledger_invalid_dir}"
  cat > "${ledger_invalid_dir}/output-layout.json" <<'JSON'
{"specVersion":1,"layout":{"screenUnitRoot":"invalid root"}}
JSON
  build_confirmation_ledger_args "${ledger_invalid_dir}" >/dev/null 2>&1
  rc=$?
  if [ "${rc}" -ne 0 ]; then
    _case_pass "収集-不正出力レイアウト" "レイアウト解決失敗を非0で返した"
  else
    _case_fail "収集-不正出力レイアウト" "不正なレイアウトを成功扱いした"
  fi

  # 収集-find失敗伝播
  find() { return 7; }
  build_confirmation_ledger_args "${ledger_test_dir}" >/dev/null 2>&1
  rc=$?
  unset -f find
  if [ "${rc}" -ne 0 ]; then
    _case_pass "収集-find失敗伝播" "findの失敗を非0で返した"
  else
    _case_fail "収集-find失敗伝播" "findの失敗を台帳0件として扱った"
  fi

  # ハッシュ-決定的
  # stage_matrix() の実コード(matrix_block)自体が del(.generatedAt, ...) を
  # 経由してハッシュを取っていることを検査する。ここで独自に del() を計算すると
  # jq の挙動を確かめるだけになり、stage_matrix() の実装を検査できない。
  local hash_del_count
  hash_del_count="$(printf '%s' "${matrix_block}" | grep -Fc 'del(.generatedAt')"
  if printf '%s' "${matrix_block}" | grep -Fq 'del(.generatedAt, .manifestContentHash)' \
    && [ "${hash_del_count}" -eq 2 ] \
    && ! printf '%s' "${matrix_block}" | grep -Fq 'jq -cjS . "${pf_data}"'; then
    _case_pass "ハッシュ-決定的" "pf_hash の算出が shasum/sha256sum 両分岐とも del(.generatedAt, .manifestContentHash) 経由になっている"
  else
    _case_fail "ハッシュ-決定的" "pf_hash の算出が generatedAt を除かずに permission-matrix.json をそのままハッシュしている(del 出現数=${hash_del_count})"
  fi

  # 出力先-基盤配下
  # foundationDir を output-layout.json から動的解決していることと、旧来の
  # 「基盤」という日本語ルートの直書きが残っていないことを検査する。
  if printf '%s' "${design_block}" | grep -Eq 'output_layout_get "\$\{design_layout_json\}" foundationDir' \
    && printf '%s' "${design_block}" | grep -q 'foundation_dir="\${OUTPUT_DIR}/\${foundation_root}"' \
    && ! printf '%s' "${design_block}" | grep -Eq 'PORTAL_DIR\}/基盤' \
    && printf '%s' "${design_block}" | grep -q -- '"\${foundation_dir}" --page design-system' \
    && printf '%s' "${design_block}" | grep -q -- '"\${foundation_dir}" --page component-inventory' \
    && printf '%s' "${design_block}" | grep -q -- '"\${foundation_dir}" --page icon-catalog'; then
    _case_pass "出力先-基盤配下" "デザイン系ページの出力先が foundationDir から動的解決されている"
  else
    _case_fail "出力先-基盤配下" "デザイン系ページの出力先が foundationDir の動的解決を経由していない、または旧来の直書きが残っている"
  fi

  # 引数-ポータル位置
  if printf '%s' "${design_block}" | grep -q -- '--page design-system --portal-dir "\${PORTAL_DIR}"' \
    && printf '%s' "${design_block}" | grep -q -- '--page component-inventory --portal-dir "\${PORTAL_DIR}"' \
    && printf '%s' "${design_block}" | grep -q -- '--page icon-catalog --portal-dir "\${PORTAL_DIR}"'; then
    _case_pass "引数-ポータル位置" "デザイン系の3呼び出しに --portal-dir が含まれる"
  else
    _case_fail "引数-ポータル位置" "デザイン系の呼び出しに --portal-dir が見つからない"
  fi

  # 配線-追加6件
  local type_block unit_block wired_all needle combined
  type_block="$(sed -n '/^stage_type_extraction()/,/^}/p' "${SELF_PATH}")"
  unit_block="$(sed -n '/^stage_unit_lists()/,/^}/p' "${SELF_PATH}")"
  combined="${type_block}${unit_block}${matrix_block}"
  wired_all=1
  for needle in extract-screen-metadata convert-message-doc-to-manifest aggregate-test-viewpoints aggregate-test-cases build-confirmation-survey-data; do
    printf '%s' "${combined}" | grep -q "${needle}" || wired_all=0
  done
  printf '%s' "${unit_block}" | grep -Eq '^[[:space:]]+run_cmd bash "\$\{integration_spec_script\}" "\$\{OUTPUT_DIR\}" "検証用プロジェクト"$' || wired_all=0
  if [ "${wired_all}" -eq 1 ]; then
    _case_pass "配線-追加6件" "6本の呼び出しがすべてスクリプト本文に存在する"
  else
    _case_fail "配線-追加6件" "追加6本のうち一部の呼び出しが見つからない"
  fi

  # 原本root-全生成連鎖: 疑似入力がある場合は合成rootまたは種別別rootを使い、
  # 画面だけはREPOを基準にする。
  local manifest_block
  manifest_block="$(sed -n '/^stage_build_manifests()/,/^}/p' "${SELF_PATH}")"
  if printf '%s' "${manifest_block}" | grep -Fq -- 'verification-source/project' \
    && printf '%s' "${manifest_block}" | grep -Fq -- '--source-file-root "${source_file_root}"' \
    && printf '%s' "${unit_block}" | grep -Fq -- '--source-file-root "${REPO}"' \
    && [ "$(printf '%s' "${unit_block}" | grep -Fc -- 'resolve_extraction_source_dir')" -eq 2 ]; then
    _case_pass "原本root-全生成連鎖" "manifest組立へ合成root、feature・汎用5種別へ種別別root、screenへREPOを透過"
  else
    _case_fail "原本root-全生成連鎖" "生成経路ごとの--source-file-root配線が欠けている"
  fi

  # 依存-追加分実在
  local added_missing=0 added
  for added in \
    "${repo_root}/generation-engine/scripts/extract/extract-screen-metadata.sh" \
    "${repo_root}/generation-engine/scripts/extract/convert-message-doc-to-manifest.sh" \
    "${repo_root}/generation-engine/scripts/extract/aggregate-test-viewpoints.sh" \
    "${repo_root}/generation-engine/scripts/extract/aggregate-test-cases.sh" \
    "${repo_root}/generation-engine/scripts/extract/build-confirmation-survey-data.sh"; do
    [ -f "${added}" ] || added_missing=$((added_missing + 1))
  done
  if [ "${added_missing}" -eq 0 ]; then
    _case_pass "依存-追加分実在" "追加した5本の依存スクリプトが実在する"
  else
    _case_fail "依存-追加分実在" "${added_missing} 件が不在"
  fi

  # 配線-関連図3件
  local diagram_wired_all=1 diagram_needle
  for diagram_needle in extract-entity-state-page-data extract-er-page-data extract-transition-page-data; do
    printf '%s' "${design_block}" | grep -q "${diagram_needle}" || diagram_wired_all=0
  done
  if [ "${diagram_wired_all}" -eq 1 ]; then
    _case_pass "配線-関連図3件" "状態遷移図・ER図・画面遷移図の抽出呼び出しがすべてスクリプト本文に存在する"
  else
    _case_fail "配線-関連図3件" "関連図3本のうち一部の呼び出しが見つからない"
  fi

  # 出力先-図配下
  # diagramDir を output-layout.json から動的解決していることと、旧来の
  # 「図」という日本語ルートの直書きが残っていないことを検査する。
  if printf '%s' "${design_block}" | grep -Eq 'output_layout_get "\$\{design_layout_json\}" diagramDir' \
    && printf '%s' "${design_block}" | grep -q 'diagrams_dir="\${OUTPUT_DIR}/\${diagram_root}"' \
    && ! printf '%s' "${design_block}" | grep -Eq 'PORTAL_DIR\}/図' \
    && printf '%s' "${design_block}" | grep -q -- '"\${diagrams_dir}" --page entity-state --portal-dir "\${PORTAL_DIR}"' \
    && printf '%s' "${design_block}" | grep -q -- '"\${diagrams_dir}" --page er --portal-dir "\${PORTAL_DIR}"' \
    && printf '%s' "${design_block}" | grep -q -- '"\${diagrams_dir}" --page transition --portal-dir "\${PORTAL_DIR}"'; then
    _case_pass "出力先-図配下" "関連図3種の出力先が diagramDir から動的解決されている"
  else
    _case_fail "出力先-図配下" "関連図3種の出力先が diagramDir の動的解決を経由していない、または旧来の直書きが残っている"
  fi

  # 依存-関連図3件実在
  local diagram_missing=0 diagram_added
  for diagram_added in \
    "${repo_root}/generation-engine/scripts/portal-input/extract-entity-state-page-data.sh" \
    "${repo_root}/generation-engine/scripts/portal-input/extract-er-page-data.sh" \
    "${repo_root}/generation-engine/scripts/portal-input/extract-transition-page-data.sh"; do
    [ -f "${diagram_added}" ] || diagram_missing=$((diagram_missing + 1))
  done
  if [ "${diagram_missing}" -eq 0 ]; then
    _case_pass "依存-関連図3件実在" "関連図3種の抽出スクリプトが実在する"
  else
    _case_fail "依存-関連図3件実在" "${diagram_missing} 件が不在"
  fi

  rm -rf "${tmp}" "${inside_parent}" 2>/dev/null
  trap - EXIT
  echo "実行 ${run} 件 / 成功 ${ok} 件 / 失敗 ${ng} 件"
  [ "${ng}" -eq 0 ]
}

# ---- main ------------------------------------------------------------

usage() {
  cat <<'EOS'
使い方: run-layer-full-pipeline.sh --output <出力先> [--repo <リポジトリのパス>] [--input <疑似入力の位置>] [--keep] [--self-test]
EOS
}

main() {
  local output="" repo="" input="" keep=0 self_test_mode=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --output) output="${2:-}"; shift 2 ;;
      --repo) repo="${2:-}"; shift 2 ;;
      --input) input="${2:-}"; shift 2 ;;
      --keep) keep=1; shift ;;
      --self-test) self_test_mode=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "不明な引数: $1" >&2; usage >&2; exit 2 ;;
    esac
  done

  if [ "${self_test_mode}" -eq 1 ]; then
    self_test
    exit $?
  fi

  if [ -z "${output}" ]; then
    echo "ERROR: --output は必須です" >&2
    usage >&2
    exit 1
  fi

  case "${output}" in
    /*) OUTPUT_DIR="${output}" ;;
    *) OUTPUT_DIR="$(pwd)/${output}" ;;
  esac

  if is_output_inside_git "${OUTPUT_DIR}"; then
    echo "ERROR: --output は版管理下のパスを指定できません: ${OUTPUT_DIR}" >&2
    exit 1
  fi

  local resolved_output_dir
  resolved_output_dir="$(resolve_output_dir_realpath "${OUTPUT_DIR}")"
  if [ -z "${resolved_output_dir}" ]; then
    echo "ERROR: --output の実体パスを解決できません: ${OUTPUT_DIR}" >&2
    exit 1
  fi
  OUTPUT_DIR="${resolved_output_dir}"

  REPO_SELF="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
  REPO="${repo}"
  REPO_EXPLICIT=0
  [ -n "${repo}" ] && REPO_EXPLICIT=1
  [ -z "${REPO}" ] && REPO="${REPO_SELF}"
  INPUT_LOCATION="${input}"
  KEEP="${keep}"

  MANIFESTS_DIR="${OUTPUT_DIR}/docs/manifests"
  PORTAL_DIR="${OUTPUT_DIR}/project-portal"
  mkdir -p "${MANIFESTS_DIR}" "${PORTAL_DIR}"

  echo "検証対象コミット: $(verification_env_record_version "${REPO}")"
  echo

  local key
  for key in $(stage_keys); do
    echo "[実行中] $(stage_name "${key}")"
    run_stage "${key}"
  done
  echo

  print_summary

  local i rc=0
  for i in "${!RESULT_STATUS[@]}"; do
    [ "${RESULT_STATUS[$i]}" = "FAIL" ] && rc=1
  done

  if [ "${KEEP}" -ne 1 ] && [ -n "${SCRATCH_BASE}" ]; then
    verification_env_teardown "${SCRATCH_BASE}" >/dev/null 2>&1
  fi

  exit "${rc}"
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
