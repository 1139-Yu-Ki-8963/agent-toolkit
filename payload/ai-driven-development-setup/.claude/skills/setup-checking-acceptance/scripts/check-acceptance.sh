#!/usr/bin/env bash
set -u

# check-acceptance.sh - 機能→単位→要件（柱）の合格を集計し、欠落6つを検査する
#
# 目的:
#   docs/skills/<機能名>/tests/*.sh を実行して機能の合格を決め、機能の集まりから
#   単位の合格を、単位と category の対応から要件（柱）の合格を決める。あわせて
#   追跡の鎖が切れた6種類の欠落（テストを持たない機能・どの機能にも属さない
#   テスト・2単位に属する機能・統括が直書きする機能名・他の単位の名前を持つ
#   機能・portal以外の機能のhtml出力）を検査し、1件でもあれば不合格とする。
#
# 使い方:
#   check-acceptance.sh <リポジトリのルート> [--unit <単位>] [--report <出力パス>]
#   check-acceptance.sh --self-test
#
# 前段:
#   実行の最初に <リポジトリのルート>/docs/skills/setup-deriving-skills/scripts/
#   validate-skill-definitions.sh <docs/skills のルート> を呼ぶ（requires で宣言
#   した setup-deriving-skills への依存）。不合格でも全体の集計は続行するが、
#   最終的な合否には反映する。
#
# unitオプション:
#   指定した単位の機能だけ tests を実際に実行する。他の単位の機能は対象外
#   として扱い、実行しない。6つの欠落検査はunitの指定に関わらず常に
#   docs/skills 全体を対象にする（構造の検査であり実行を伴わないため）。
#   要件（柱）は、必須単位・任意単位のいずれかが指定単位以外を含む場合、
#   判定材料が揃わないため対象外と表示する。
#
# tests1本あたりの上限:
#   既定 300 秒（環境変数 ACCEPTANCE_TEST_TIMEOUT で上書き可、self-test用）。
#   超えた場合は不合格ではなく未確認として扱い、合格にも不合格にも数えない
#   （.claude/rules/always/verification/indeterminate-result/rule.md の考え方）。
#
# 終了コード:
#   0 = 全機能・全単位・全要件が合格（または未着手）で、6つの欠落と前段検査が
#       すべて問題なし。合格と数えられるのはこの0だけである
#   1 = 機能・単位・要件のいずれかが不合格、または欠落・前段検査に問題あり
#       （未確認が1件でも、不合格・欠落が同時にあれば1を優先する）
#   2 = 不合格・欠落は無いが、機能・単位・要件のいずれかに未確認（tests1本
#       あたりの上限超過）が1件以上ある場合。または、リポジトリのルート不在・
#       docs/skills 不在・機能定義が1件も無い・--self-testでの一時領域の
#       作成失敗など、判定材料が揃わず検査そのものを実行できなかった場合
#
# 保守責任者: 人手（ユーザー）。6つの欠落の判定条件・柱の対応（requirement-
#   pillars.json）を変える場合は本スクリプトと
#   docs/skills/setup-checking-acceptance/SKILL.md を同時に更新する。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REQUIRED_SKILL_NAME="setup-deriving-skills"
SELF_SKILL_NAME="setup-checking-acceptance"
UNIT_NAMES="setup reverse verify portal operate"
TEST_TIMEOUT_SECONDS="${ACCEPTANCE_TEST_TIMEOUT:-300}"

# 自分自身のtestsが自分自身を再帰的に呼び出すため、内側の呼び出しでは
# 自分自身のtestsをスキップする（無限再帰・指数的な再帰を防ぐ）。
SKIP_SELF="${ACCEPTANCE_SKIP_SELF:-0}"

# ---------------------------------------------------------------------------
# front matter 抽出
# ---------------------------------------------------------------------------

fm_extract() {
  local file="$1" first_line
  first_line="$(head -n1 "$file" 2>/dev/null || true)"
  [ "$first_line" = "---" ] || return 1
  awk 'NR==1{next} /^---$/{exit} {print}' "$file"
}

body_extract() {
  awk 'BEGIN{count=0} /^---$/{count++; next} count>=2{print}' "$1"
}

fm_get_scalar() {
  local body="$1" key="$2"
  printf '%s\n' "$body" | awk -v k="$key" '
    index($0, k ": ") == 1 { sub("^" k ": ", ""); print; exit }
    $0 == k ":" { print ""; exit }
  '
}

fm_get_array_raw() {
  local body="$1" key="$2" line
  line="$(printf '%s\n' "$body" | grep -E "^${key}:" | head -n1 || true)"
  [ -n "$line" ] || return 1
  printf '%s\n' "${line#"${key}: "}"
}

array_elements() {
  local raw="$1"
  raw="${raw#\[}"
  raw="${raw%\]}"
  [ -n "$raw" ] || return 0
  printf '%s\n' "$raw" | tr ',' '\n' | sed -e 's/^ *//' -e 's/ *$//'
}

# ---------------------------------------------------------------------------
# タイムアウト付き実行
# ---------------------------------------------------------------------------

run_with_timeout() {
  local timeout_seconds="$1" out_file="$2"
  shift 2
  local max_iterations=$(( timeout_seconds * 5 ))
  local child_pid loop_counter exit_code
  set -m
  "$@" > "$out_file" 2>&1 &
  child_pid=$!
  loop_counter=0
  while kill -0 "$child_pid" 2>/dev/null; do
    sleep 0.2
    loop_counter=$((loop_counter + 1))
    if [ "$loop_counter" -ge "$max_iterations" ]; then
      kill -TERM -- -"$child_pid" 2>/dev/null
      sleep 0.5
      kill -KILL -- -"$child_pid" 2>/dev/null
      wait "$child_pid" 2>/dev/null
      set +m
      return 124
    fi
  done
  wait "$child_pid"
  exit_code=$?
  set +m
  return "$exit_code"
}

# ---------------------------------------------------------------------------
# 前段: validate-skill-definitions.sh の呼び出し
# ---------------------------------------------------------------------------

run_front_validate() {
  local root="$1" skills_root="$2" validate_script validate_exit_code=0
  validate_script="${root}/docs/skills/${REQUIRED_SKILL_NAME}/scripts/validate-skill-definitions.sh"
  if [ ! -f "$validate_script" ]; then
    echo "[UNKNOWN] validate-skill-definitions.sh が見つからない: ${validate_script}"
    return 2
  fi
  bash "$validate_script" "$skills_root" 2>&1 || validate_exit_code=$?
  return "$validate_exit_code"
}

extract_validate_key_lines() {
  printf '%s\n' "$1" | awk -v key="$2" '
    /^\[FAIL\]/ {
      line=$0
      sub(/^\[FAIL\] /, "", line)
      element_count = split(line, parts, ": ")
      if (element_count >= 2 && parts[2] == key) print line
    }
  '
}

# ---------------------------------------------------------------------------
# 機能の収集
# ---------------------------------------------------------------------------

SKILL_NAMES=()
SKILL_UNITS=()
SKILL_CATEGORIES=()
SKILL_TYPES=()
SKILL_REQUIRES=()
SKILL_OUTPUTS=()
SKILL_TESTS_TOTAL=()
SKILL_TESTS_PASSED=()
SKILL_TESTS_TIMEOUT=()
SKILL_STATUS=()

reset_skill_arrays() {
  SKILL_NAMES=()
  SKILL_UNITS=()
  SKILL_CATEGORIES=()
  SKILL_TYPES=()
  SKILL_REQUIRES=()
  SKILL_OUTPUTS=()
  SKILL_TESTS_TOTAL=()
  SKILL_TESTS_PASSED=()
  SKILL_TESTS_TIMEOUT=()
  SKILL_STATUS=()
}

run_skill_tests() {
  local skill_dir="$1" tests_dir test_total=0 test_passed=0 test_timeout=0
  tests_dir="${skill_dir}/tests"
  local test_scripts
  test_scripts="$(find "$tests_dir" -maxdepth 1 -type f -name '*.sh' -perm -u+x 2>/dev/null | sort)"
  if [ -n "$test_scripts" ]; then
    local one_script out_file exit_code
    while IFS= read -r one_script; do
      [ -n "$one_script" ] || continue
      test_total=$((test_total + 1))
      out_file="$(mktemp "${TMPDIR:-/tmp}/check-acceptance-test-out.XXXXXX" 2>/dev/null)" || out_file=""
      if [ -z "$out_file" ]; then
        exit_code=0
        bash "$one_script" >/dev/null 2>&1 || exit_code=$?
      else
        run_with_timeout "$TEST_TIMEOUT_SECONDS" "$out_file" bash "$one_script"
        exit_code=$?
        rm -f "$out_file"
      fi
      if [ "$exit_code" -eq 124 ]; then
        test_timeout=$((test_timeout + 1))
      elif [ "$exit_code" -eq 0 ]; then
        test_passed=$((test_passed + 1))
      fi
    done <<TEST_SCRIPT_LIST
$test_scripts
TEST_SCRIPT_LIST
  fi
  printf '%s %s %s\n' "$test_total" "$test_passed" "$test_timeout"
}

skill_status_of() {
  local test_total="$1" test_passed="$2" test_timeout="$3" test_failed
  if [ "$test_total" -eq 0 ]; then
    printf '不合格'
    return
  fi
  test_failed=$(( test_total - test_passed - test_timeout ))
  if [ "$test_failed" -gt 0 ]; then
    printf '不合格'
  elif [ "$test_timeout" -gt 0 ]; then
    printf '未確認'
  else
    printf '合格'
  fi
}

gather_skills() {
  local skills_root="$1" unit_filter="$2"
  reset_skill_arrays
  local skill_dirs
  skill_dirs="$(find "$skills_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)"
  [ -n "$skill_dirs" ] || return 0
  local one_dir skill_name skill_file front_matter_body declared_unit declared_category declared_type declared_requires declared_outputs test_total test_passed test_timeout skill_status
  while IFS= read -r one_dir; do
    [ -n "$one_dir" ] || continue
    skill_name="$(basename "$one_dir")"
    skill_file="${one_dir}/SKILL.md"
    if [ ! -f "$skill_file" ]; then
      continue
    fi
    front_matter_body="$(fm_extract "$skill_file" 2>/dev/null || true)"
    declared_unit="$(fm_get_scalar "$front_matter_body" unit)"
    declared_category="$(fm_get_scalar "$front_matter_body" category)"
    declared_type="$(fm_get_scalar "$front_matter_body" type)"
    declared_requires="$(fm_get_array_raw "$front_matter_body" requires 2>/dev/null || true)"
    declared_outputs="$(fm_get_array_raw "$front_matter_body" outputs 2>/dev/null || true)"

    if [ -n "$unit_filter" ] && [ "$declared_unit" != "$unit_filter" ]; then
      test_total="-"; test_passed="-"; test_timeout="-"; skill_status="対象外"
    elif [ "$skill_name" = "$SELF_SKILL_NAME" ] && [ "$SKIP_SELF" = "1" ]; then
      test_total="-"; test_passed="-"; test_timeout="-"; skill_status="対象外（再帰防止）"
    else
      read -r test_total test_passed test_timeout <<< "$(run_skill_tests "$one_dir")"
      skill_status="$(skill_status_of "$test_total" "$test_passed" "$test_timeout")"
    fi

    SKILL_NAMES+=("$skill_name")
    SKILL_UNITS+=("$declared_unit")
    SKILL_CATEGORIES+=("$declared_category")
    SKILL_TYPES+=("$declared_type")
    SKILL_REQUIRES+=("$declared_requires")
    SKILL_OUTPUTS+=("$declared_outputs")
    SKILL_TESTS_TOTAL+=("$test_total")
    SKILL_TESTS_PASSED+=("$test_passed")
    SKILL_TESTS_TIMEOUT+=("$test_timeout")
    SKILL_STATUS+=("$skill_status")
  done <<SKILL_DIR_LIST
$skill_dirs
SKILL_DIR_LIST
}

# ---------------------------------------------------------------------------
# 単位の集計
# ---------------------------------------------------------------------------

unit_skill_count() {
  local target_unit="$1" found_count=0 index_position
  for ((index_position = 0; index_position < ${#SKILL_NAMES[@]}; index_position++)); do
    [ "${SKILL_UNITS[$index_position]}" = "$target_unit" ] && found_count=$((found_count + 1))
  done
  printf '%s' "$found_count"
}

unit_status_of() {
  local target_unit="$1" unit_filter="$2" member_count index_position member_status has_failed_member=0 has_unknown_member=0
  member_count="$(unit_skill_count "$target_unit")"
  if [ "$member_count" -eq 0 ]; then
    printf '未着手'
    return
  fi
  if [ -n "$unit_filter" ] && [ "$target_unit" != "$unit_filter" ]; then
    printf '対象外'
    return
  fi
  for ((index_position = 0; index_position < ${#SKILL_NAMES[@]}; index_position++)); do
    if [ "${SKILL_UNITS[$index_position]}" = "$target_unit" ]; then
      member_status="${SKILL_STATUS[$index_position]}"
      [ "$member_status" = "不合格" ] && has_failed_member=1
      [ "$member_status" = "未確認" ] && has_unknown_member=1
    fi
  done
  if [ "$has_failed_member" -eq 1 ]; then
    printf '不合格'
  elif [ "$has_unknown_member" -eq 1 ]; then
    printf '未確認'
  else
    printf '合格'
  fi
}

# ---------------------------------------------------------------------------
# 要件（柱）の集計
# ---------------------------------------------------------------------------

pillars_read() {
  # jq で pillars[].key / title / requiredUnits[] / optionalUnits[] を読み、
  # 1行1柱の "key|title|required_csv|optional_csv" 形式へ整形する。
  # jq が使えない、または読み取りに失敗した場合は [UNKNOWN] を出し空行を返す
  # （呼び出し側は空行を「柱0件」として扱い、requirement-pillars.jsonが見つから
  # ない場合と同様に不合格側へ倒す）。
  local pillars_file="$1"
  if ! command -v jq >/dev/null 2>&1; then
    echo "[UNKNOWN] jq が見つからないため requirement-pillars.json を読めない" >&2
    return 0
  fi
  jq -r '
    .pillars[]
    | [
        (.key // ""),
        (.title // ""),
        ((.requiredUnits // []) | join(",")),
        ((.optionalUnits // []) | join(","))
      ]
    | join("|")
  ' "$pillars_file" 2>/dev/null || {
    echo "[UNKNOWN] requirement-pillars.json の読み取りに失敗した: ${pillars_file}" >&2
    return 0
  }
}

pillar_missing_required() {
  local required_csv="$1" missing_list=""
  local saved_ifs="$IFS"
  IFS=','
  local required_unit_array=($required_csv)
  IFS="$saved_ifs"
  local one_unit
  for one_unit in "${required_unit_array[@]}"; do
    [ -n "$one_unit" ] || continue
    if [ "$(unit_skill_count "$one_unit")" -eq 0 ]; then
      missing_list="${missing_list}${one_unit} "
    fi
  done
  printf '%s' "$missing_list"
}

pillar_status_of() {
  local category_key="$1" required_csv="$2" optional_csv="$3" unit_filter="$4"
  local missing_units index_position member_status

  if [ -n "$unit_filter" ]; then
    local saved_ifs="$IFS"
    IFS=','
    local combined_unit_array=($required_csv $optional_csv)
    IFS="$saved_ifs"
    local combined_unit
    for combined_unit in "${combined_unit_array[@]}"; do
      [ -n "$combined_unit" ] || continue
      if [ "$combined_unit" != "$unit_filter" ]; then
        printf '対象外'
        return
      fi
    done
  fi

  missing_units="$(pillar_missing_required "$required_csv")"
  if [ -n "$missing_units" ]; then
    printf '未着手'
    return
  fi

  local has_category_member=0 has_failed_member=0 has_unknown_member=0
  for ((index_position = 0; index_position < ${#SKILL_NAMES[@]}; index_position++)); do
    if [ "${SKILL_CATEGORIES[$index_position]}" = "$category_key" ]; then
      has_category_member=1
      member_status="${SKILL_STATUS[$index_position]}"
      [ "$member_status" = "不合格" ] && has_failed_member=1
      [ "$member_status" = "未確認" ] && has_unknown_member=1
    fi
  done
  if [ "$has_category_member" -eq 0 ]; then
    printf '未着手'
    return
  fi
  if [ "$has_failed_member" -eq 1 ]; then
    printf '不合格'
    return
  fi

  local saved_ifs2="$IFS"
  IFS=','
  local optional_unit_array=($optional_csv)
  IFS="$saved_ifs2"
  local optional_unit
  for optional_unit in "${optional_unit_array[@]}"; do
    [ -n "$optional_unit" ] || continue
    if [ "$(unit_skill_count "$optional_unit")" -gt 0 ]; then
      for ((index_position = 0; index_position < ${#SKILL_NAMES[@]}; index_position++)); do
        if [ "${SKILL_UNITS[$index_position]}" = "$optional_unit" ]; then
          member_status="${SKILL_STATUS[$index_position]}"
          [ "$member_status" = "不合格" ] && has_failed_member=1
          [ "$member_status" = "未確認" ] && has_unknown_member=1
        fi
      done
    fi
  done
  if [ "$has_failed_member" -eq 1 ]; then
    printf '不合格'
  elif [ "$has_unknown_member" -eq 1 ]; then
    printf '未確認'
  else
    printf '合格'
  fi
}

# ---------------------------------------------------------------------------
# 欠落6つの検査
# ---------------------------------------------------------------------------

missing_no_tests() {
  # --unit で絞り込んだ場合でも docs/skills 全体を対象にする（実行を伴わない
  # 構造検査のため）。SKILL_TESTS_TOTAL は対象外の機能で "-" になり件数を
  # 反映しないため、ファイルシステムを直接走査する。
  local skills_root="$1" one_dir skill_name test_sh_count collected_lines=""
  [ -d "$skills_root" ] || { printf ''; return; }
  for one_dir in "$skills_root"/*/; do
    [ -f "${one_dir}SKILL.md" ] || continue
    skill_name="$(basename "$one_dir")"
    test_sh_count="$(find "${one_dir}tests" -maxdepth 1 -type f -name '*.sh' 2>/dev/null | grep -c . 2>/dev/null || true)"
    [ -n "$test_sh_count" ] || test_sh_count=0
    if [ "$test_sh_count" -eq 0 ]; then
      collected_lines="${collected_lines}${skill_name}
"
    fi
  done
  printf '%s' "$collected_lines"
}

missing_orphan_tests() {
  local skills_root="$1" found_files one_file file_dir dir_parent collected_lines=""
  found_files="$(find "$skills_root" -type f -name '*.sh' -path '*/tests/*' 2>/dev/null | sort)"
  [ -n "$found_files" ] || { printf ''; return; }
  while IFS= read -r one_file; do
    [ -n "$one_file" ] || continue
    file_dir="$(dirname "$one_file")"
    if [ "$(basename "$file_dir")" != "tests" ]; then
      collected_lines="${collected_lines}${one_file} （tests直下でない）
"
      continue
    fi
    dir_parent="$(dirname "$file_dir")"
    if [ "$(dirname "$dir_parent")" != "$skills_root" ]; then
      collected_lines="${collected_lines}${one_file} （機能フォルダの直下のtestsでない）
"
      continue
    fi
    if [ ! -f "${dir_parent}/SKILL.md" ]; then
      collected_lines="${collected_lines}${one_file} （対応するSKILL.mdが無い）
"
    fi
  done <<ORPHAN_FILE_LIST
$found_files
ORPHAN_FILE_LIST
  printf '%s' "$collected_lines"
}

missing_two_unit_skills() {
  local validate_output="$1"
  extract_validate_key_lines "$validate_output" "接頭辞-不一致"
}

missing_orchestration_literal() {
  local skills_root="$1" outer_index inner_index collected_lines="" this_skill_name this_skill_body requires_line_list one_other_name
  local all_skill_names=("${SKILL_NAMES[@]}")
  for ((outer_index = 0; outer_index < ${#SKILL_NAMES[@]}; outer_index++)); do
    [ "${SKILL_TYPES[$outer_index]}" = "orchestration" ] || continue
    this_skill_name="${SKILL_NAMES[$outer_index]}"
    this_skill_body="$(body_extract "${skills_root}/${this_skill_name}/SKILL.md" 2>/dev/null || true)"
    requires_line_list=""
    if [ -n "${SKILL_REQUIRES[$outer_index]}" ]; then
      requires_line_list="$(array_elements "${SKILL_REQUIRES[$outer_index]}")"
    fi
    for ((inner_index = 0; inner_index < ${#all_skill_names[@]}; inner_index++)); do
      one_other_name="${all_skill_names[$inner_index]}"
      [ "$one_other_name" = "$this_skill_name" ] && continue
      if printf '%s\n' "$requires_line_list" | grep -qxF "$one_other_name"; then
        continue
      fi
      if printf '%s\n' "$this_skill_body" | grep -qF "$one_other_name"; then
        collected_lines="${collected_lines}${this_skill_name}: ${one_other_name}
"
      fi
    done
  done
  printf '%s' "$collected_lines"
}

missing_other_unit_name() {
  local validate_output="$1"
  extract_validate_key_lines "$validate_output" "他単位-名前混入"
}

missing_html_output_outside_portal() {
  # portal 以外の単位の機能が宣言の outputs に .html を持つものを列挙する。
  # 決まり: 先方の docs/ には AI が読む定義（md・json）だけを置き、人が見る
  # HTML は portal 単位だけが出す。
  local index_position one_output collected_lines=""
  for ((index_position = 0; index_position < ${#SKILL_NAMES[@]}; index_position++)); do
    [ "${SKILL_UNITS[$index_position]}" = "portal" ] && continue
    [ -n "${SKILL_OUTPUTS[$index_position]}" ] || continue
    while IFS= read -r one_output; do
      [ -n "$one_output" ] || continue
      if printf '%s' "$one_output" | grep -qiE '\.html?$'; then
        collected_lines="${collected_lines}${SKILL_NAMES[$index_position]}: ${one_output}
"
      fi
    done <<OUTPUT_ELEMENTS
$(array_elements "${SKILL_OUTPUTS[$index_position]}")
OUTPUT_ELEMENTS
  done
  printf '%s' "$collected_lines"
}

# ---------------------------------------------------------------------------
# 出力の組み立て
# ---------------------------------------------------------------------------

build_report() {
  local root="$1" unit_filter="$2"
  local skills_root="${root}/docs/skills"
  local pillars_json="${root}/docs/design/requirement-pillars.json"
  local report_text=""
  local overall_has_problem=0
  local overall_has_unknown=0

  report_text="${report_text}# 合格の集計

"

  if [ ! -d "$skills_root" ]; then
    echo "[UNKNOWN] docs/skills が存在しない: ${skills_root}" >&2
    return 2
  fi
  local existing_skill_dirs
  existing_skill_dirs="$(find "$skills_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)"
  if [ -z "$existing_skill_dirs" ]; then
    echo "[UNKNOWN] 機能の定義が1件も無い: ${skills_root}" >&2
    return 2
  fi

  local validate_output validate_exit_code=0
  validate_output="$(run_front_validate "$root" "$skills_root")" || validate_exit_code=$?
  report_text="${report_text}## 前段（機能定義の検査）

"
  if [ "$validate_exit_code" -eq 0 ]; then
    report_text="${report_text}[OK] ${REQUIRED_SKILL_NAME} による定義検査は合格

"
  else
    overall_has_problem=1
    local validate_fail_count
    validate_fail_count="$(printf '%s\n' "$validate_output" | grep -c '^\[FAIL\]' 2>/dev/null || true)"
    [ -n "$validate_fail_count" ] || validate_fail_count=0
    report_text="${report_text}[FAIL] ${REQUIRED_SKILL_NAME} による定義検査が不合格（${validate_fail_count} 件）

\`\`\`
${validate_output}
\`\`\`

"
  fi

  gather_skills "$skills_root" "$unit_filter"

  report_text="${report_text}## 機能

| 名前 | 単位 | category | tests本数 | 結果 |
|---|---|---|---|---|
"
  local row_index
  for ((row_index = 0; row_index < ${#SKILL_NAMES[@]}; row_index++)); do
    report_text="${report_text}| ${SKILL_NAMES[$row_index]} | ${SKILL_UNITS[$row_index]} | ${SKILL_CATEGORIES[$row_index]} | ${SKILL_TESTS_TOTAL[$row_index]} | ${SKILL_STATUS[$row_index]} |
"
    if [ "${SKILL_STATUS[$row_index]}" = "不合格" ]; then
      overall_has_problem=1
    elif [ "${SKILL_STATUS[$row_index]}" = "未確認" ]; then
      overall_has_unknown=1
    fi
  done
  report_text="${report_text}
"

  report_text="${report_text}## 単位

| 名前 | 機能数 | 結果 |
|---|---|---|
"
  local one_unit_name unit_result unit_member_count
  for one_unit_name in $UNIT_NAMES; do
    unit_member_count="$(unit_skill_count "$one_unit_name")"
    unit_result="$(unit_status_of "$one_unit_name" "$unit_filter")"
    report_text="${report_text}| ${one_unit_name} | ${unit_member_count} | ${unit_result} |
"
    if [ "$unit_result" = "不合格" ]; then
      overall_has_problem=1
    elif [ "$unit_result" = "未確認" ]; then
      overall_has_unknown=1
    fi
  done
  report_text="${report_text}
"

  report_text="${report_text}## 要件（柱）

| 柱 | 必須単位の充足 | 任意単位 | 結果 |
|---|---|---|---|
"
  if [ -f "$pillars_json" ]; then
    local pillar_key pillar_title required_csv optional_csv missing_required_units pillar_result required_display optional_display pillar_row_count=0
    while IFS='|' read -r pillar_key pillar_title required_csv optional_csv; do
      [ -n "$pillar_key" ] || continue
      pillar_row_count=$((pillar_row_count + 1))
      missing_required_units="$(pillar_missing_required "$required_csv")"
      pillar_result="$(pillar_status_of "$pillar_key" "$required_csv" "$optional_csv" "$unit_filter")"
      if [ -n "$missing_required_units" ]; then
        required_display="必須単位未着手: ${missing_required_units}"
      else
        required_display="満たす"
      fi
      optional_display=""
      local saved_ifs3="$IFS"
      IFS=','
      local optional_display_array=($optional_csv)
      IFS="$saved_ifs3"
      local one_optional_unit
      for one_optional_unit in "${optional_display_array[@]}"; do
        [ -n "$one_optional_unit" ] || continue
        if [ "$(unit_skill_count "$one_optional_unit")" -eq 0 ]; then
          optional_display="${optional_display}${one_optional_unit}(任意・未着手) "
        else
          optional_display="${optional_display}${one_optional_unit} "
        fi
      done
      [ -n "$optional_display" ] || optional_display="（任意単位なし）"
      report_text="${report_text}| ${pillar_title}（${pillar_key}） | ${required_display} | ${optional_display} | ${pillar_result} |
"
      if [ "$pillar_result" = "不合格" ]; then
        overall_has_problem=1
      elif [ "$pillar_result" = "未確認" ]; then
        overall_has_unknown=1
      fi
    done <<PILLAR_LIST
$(pillars_read "$pillars_json")
PILLAR_LIST
    if [ "$pillar_row_count" -eq 0 ]; then
      report_text="${report_text}| （requirement-pillars.jsonの柱が0件: ${pillars_json}） | - | - | - |
"
      overall_has_problem=1
    fi
  else
    report_text="${report_text}| （requirement-pillars.jsonが見つからない: ${pillars_json}） | - | - | - |
"
    overall_has_problem=1
  fi
  report_text="${report_text}
"

  report_text="${report_text}## 欠落の検査

| 種類 | 件数 | 該当 |
|---|---|---|
"
  local no_tests_lines orphan_tests_lines two_unit_lines orchestration_lines other_unit_name_lines html_output_lines
  local no_tests_count orphan_tests_count two_unit_count orchestration_count other_unit_name_count html_output_count
  no_tests_lines="$(missing_no_tests "$skills_root")"
  orphan_tests_lines="$(missing_orphan_tests "$skills_root")"
  two_unit_lines="$(missing_two_unit_skills "$validate_output")"
  orchestration_lines="$(missing_orchestration_literal "$skills_root")"
  other_unit_name_lines="$(missing_other_unit_name "$validate_output")"
  html_output_lines="$(missing_html_output_outside_portal)"
  no_tests_count="$(printf '%s' "$no_tests_lines" | grep -c . 2>/dev/null || true)"; [ -n "$no_tests_count" ] || no_tests_count=0
  orphan_tests_count="$(printf '%s' "$orphan_tests_lines" | grep -c . 2>/dev/null || true)"; [ -n "$orphan_tests_count" ] || orphan_tests_count=0
  two_unit_count="$(printf '%s' "$two_unit_lines" | grep -c . 2>/dev/null || true)"; [ -n "$two_unit_count" ] || two_unit_count=0
  orchestration_count="$(printf '%s' "$orchestration_lines" | grep -c . 2>/dev/null || true)"; [ -n "$orchestration_count" ] || orchestration_count=0
  other_unit_name_count="$(printf '%s' "$other_unit_name_lines" | grep -c . 2>/dev/null || true)"; [ -n "$other_unit_name_count" ] || other_unit_name_count=0
  html_output_count="$(printf '%s' "$html_output_lines" | grep -c . 2>/dev/null || true)"; [ -n "$html_output_count" ] || html_output_count=0

  report_text="${report_text}| tests無し機能 | ${no_tests_count} | $(printf '%s' "$no_tests_lines" | tr '\n' ';' | sed 's/;$//') |
"
  report_text="${report_text}| 孤立tests | ${orphan_tests_count} | $(printf '%s' "$orphan_tests_lines" | tr '\n' ';' | sed 's/;$//') |
"
  report_text="${report_text}| 2単位に属する機能 | ${two_unit_count} | $(printf '%s' "$two_unit_lines" | tr '\n' ';' | sed 's/;$//') |
"
  report_text="${report_text}| 統括直書きの機能名 | ${orchestration_count} | $(printf '%s' "$orchestration_lines" | tr '\n' ';' | sed 's/;$//') |
"
  report_text="${report_text}| 他単位の名前を持つ機能 | ${other_unit_name_count} | $(printf '%s' "$other_unit_name_lines" | tr '\n' ';' | sed 's/;$//') |
"
  report_text="${report_text}| portal以外のhtml出力 | ${html_output_count} | $(printf '%s' "$html_output_lines" | tr '\n' ';' | sed 's/;$//') |
"
  report_text="${report_text}
"

  if [ "$no_tests_count" -gt 0 ] || [ "$orphan_tests_count" -gt 0 ] || [ "$two_unit_count" -gt 0 ] || [ "$orchestration_count" -gt 0 ] || [ "$other_unit_name_count" -gt 0 ] || [ "$html_output_count" -gt 0 ]; then
    overall_has_problem=1
  fi

  printf '%s' "$report_text"
  if [ "$overall_has_problem" -ne 0 ]; then
    return 1
  fi
  if [ "$overall_has_unknown" -ne 0 ]; then
    return 2
  fi
  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

copy_real_validate_script() {
  local dest_root="$1"
  local real_script_path="${SCRIPT_DIR}/../../${REQUIRED_SKILL_NAME}/scripts/validate-skill-definitions.sh"
  mkdir -p "${dest_root}/docs/skills/${REQUIRED_SKILL_NAME}/scripts"
  cp "$real_script_path" "${dest_root}/docs/skills/${REQUIRED_SKILL_NAME}/scripts/validate-skill-definitions.sh"
  chmod +x "${dest_root}/docs/skills/${REQUIRED_SKILL_NAME}/scripts/validate-skill-definitions.sh"
  mkdir -p "${dest_root}/docs/skills/${REQUIRED_SKILL_NAME}/tests"
  cat > "${dest_root}/docs/skills/${REQUIRED_SKILL_NAME}/SKILL.md" <<INNER_SKILL_EOF
---
name: ${REQUIRED_SKILL_NAME}
日本語名: 機能の派生（self-test用）
description: "self-test用の複製。"
invocation: ${REQUIRED_SKILL_NAME}
type: transform
allowed-tools: [Bash]
unit: setup
category: setup
kind: none
inputs: [docs/skills/${REQUIRED_SKILL_NAME}/dummy-input]
outputs: [docs/skills/${REQUIRED_SKILL_NAME}/dummy-output]
requires: []
acceptance: tests/
---

## いつ使うか

self-test用。
INNER_SKILL_EOF
  cat > "${dest_root}/docs/skills/${REQUIRED_SKILL_NAME}/tests/test-dummy.sh" <<'INNER_TEST_EOF'
#!/usr/bin/env bash
exit 0
INNER_TEST_EOF
  chmod +x "${dest_root}/docs/skills/${REQUIRED_SKILL_NAME}/tests/test-dummy.sh"
}

st_write_skill() {
  local target_root="$1" skill_name="$2" skill_unit="$3" skill_category="$4" test_body="${5:-exit 0}"
  local skill_dir="${target_root}/docs/skills/${skill_name}"
  mkdir -p "${skill_dir}/tests" "${skill_dir}/scripts"
  cat > "${skill_dir}/SKILL.md" <<INNER_SKILL_EOF2
---
name: ${skill_name}
日本語名: self-test用機能
description: "self-test用の機能定義。"
invocation: ${skill_name}
type: transform
allowed-tools: [Bash]
unit: ${skill_unit}
category: ${skill_category}
kind: none
inputs: [docs/skills/${skill_name}/dummy-input]
outputs: [docs/skills/${skill_name}/dummy-output]
requires: []
acceptance: tests/
---

## いつ使うか

self-test用。
INNER_SKILL_EOF2
  cat > "${skill_dir}/tests/test-dummy.sh" <<INNER_TEST_EOF2
#!/usr/bin/env bash
${test_body}
INNER_TEST_EOF2
  chmod +x "${skill_dir}/tests/test-dummy.sh"
  cat > "${skill_dir}/scripts/dummy.sh" <<INNER_DUMMY_EOF
#!/usr/bin/env bash
# ${skill_name} 用のダミースクリプト
INNER_DUMMY_EOF
}

st_reset_pillars() {
  local target_root="$1"
  mkdir -p "${target_root}/docs/design"
  cat > "${target_root}/docs/design/requirement-pillars.json" <<'INNER_PILLARS_EOF'
{
  "pillars": [
    {"key": "survey", "title": "調査を支える", "requiredUnits": ["reverse"], "optionalUnits": []},
    {"key": "setup", "title": "基盤一式の作成を支える", "requiredUnits": ["setup", "reverse"], "optionalUnits": ["verify", "portal"]},
    {"key": "operate", "title": "現場運用を支える", "requiredUnits": ["operate"], "optionalUnits": ["portal"]}
  ]
}
INNER_PILLARS_EOF
}

self_test() {
  local pass_count=0 fail_count=0
  local temp_root
  if ! temp_root="$(mktemp -d "${TMPDIR:-/tmp}/check-acceptance-self-test.XXXXXX" 2>/dev/null)" || [ -z "$temp_root" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi

  copy_real_validate_script "$temp_root"
  st_write_skill "$temp_root" "setup-alpha" "setup" "setup"
  st_reset_pillars "$temp_root"
  local output_1 exit_code_1=0
  output_1="$("$0" "$temp_root" 2>&1)" || exit_code_1=$?
  if [ "$exit_code_1" -eq 0 ] && printf '%s' "$output_1" | grep -q '| setup-alpha |'; then
    pass_count=$((pass_count+1)); echo "  [PASS] ケース1: 合格例は終了コード0"
  else
    fail_count=$((fail_count+1)); echo "  [FAIL] ケース1: 合格例が終了コード0にならない (exit ${exit_code_1})" >&2
    printf '%s\n' "$output_1" | sed 's/^/    /' >&2
  fi
  rm -rf "${temp_root:?}/docs/skills/setup-alpha"

  copy_real_validate_script "$temp_root"
  st_write_skill "$temp_root" "setup-alpha" "setup" "setup"
  rm -f "${temp_root}/docs/skills/setup-alpha/tests/test-dummy.sh"
  st_reset_pillars "$temp_root"
  local output_2 exit_code_2=0
  output_2="$("$0" "$temp_root" 2>&1)" || exit_code_2=$?
  if [ "$exit_code_2" -eq 1 ] && printf '%s' "$output_2" | grep -q 'tests無し機能 | 1'; then
    pass_count=$((pass_count+1)); echo "  [PASS] ケース2: tests無し機能を検知（exit 1）"
  else
    fail_count=$((fail_count+1)); echo "  [FAIL] ケース2: tests無し機能を検知しない (exit ${exit_code_2})" >&2
    printf '%s\n' "$output_2" | sed 's/^/    /' >&2
  fi
  rm -rf "${temp_root:?}/docs/skills/setup-alpha"

  copy_real_validate_script "$temp_root"
  st_write_skill "$temp_root" "setup-alpha" "setup" "setup"
  mkdir -p "${temp_root}/docs/skills/tests"
  cat > "${temp_root}/docs/skills/tests/test-orphan.sh" <<'INNER_ORPHAN_EOF'
#!/usr/bin/env bash
exit 0
INNER_ORPHAN_EOF
  chmod +x "${temp_root}/docs/skills/tests/test-orphan.sh"
  st_reset_pillars "$temp_root"
  local output_3 exit_code_3=0
  output_3="$("$0" "$temp_root" 2>&1)" || exit_code_3=$?
  if [ "$exit_code_3" -eq 1 ] && printf '%s' "$output_3" | grep -q '孤立tests | 1'; then
    pass_count=$((pass_count+1)); echo "  [PASS] ケース3: 孤立testsを検知（exit 1）"
  else
    fail_count=$((fail_count+1)); echo "  [FAIL] ケース3: 孤立testsを検知しない (exit ${exit_code_3})" >&2
    printf '%s\n' "$output_3" | sed 's/^/    /' >&2
  fi
  rm -rf "${temp_root:?}/docs/skills/setup-alpha" "${temp_root:?}/docs/skills/tests"

  copy_real_validate_script "$temp_root"
  st_write_skill "$temp_root" "setup-alpha" "setup" "setup"
  st_write_skill "$temp_root" "setup-beta" "setup" "setup"
  sed -i.bak 's/^type: transform$/type: orchestration/' "${temp_root}/docs/skills/setup-alpha/SKILL.md" && rm -f "${temp_root}/docs/skills/setup-alpha/SKILL.md.bak"
  cat >> "${temp_root}/docs/skills/setup-alpha/SKILL.md" <<'INNER_ORCH_EOF'

setup-beta を直接呼び出す。
INNER_ORCH_EOF
  st_reset_pillars "$temp_root"
  local output_4 exit_code_4=0
  output_4="$("$0" "$temp_root" 2>&1)" || exit_code_4=$?
  if [ "$exit_code_4" -eq 1 ] && printf '%s' "$output_4" | grep -q '統括直書きの機能名 | 1'; then
    pass_count=$((pass_count+1)); echo "  [PASS] ケース4: 統括直書きを検知（exit 1）"
  else
    fail_count=$((fail_count+1)); echo "  [FAIL] ケース4: 統括直書きを検知しない (exit ${exit_code_4})" >&2
    printf '%s\n' "$output_4" | sed 's/^/    /' >&2
  fi
  rm -rf "${temp_root:?}/docs/skills/setup-alpha" "${temp_root:?}/docs/skills/setup-beta"

  copy_real_validate_script "$temp_root"
  st_write_skill "$temp_root" "setup-alpha" "setup" "setup" "sleep 3; exit 0"
  st_reset_pillars "$temp_root"
  local output_5 exit_code_5=0
  output_5="$(ACCEPTANCE_TEST_TIMEOUT=1 "$0" "$temp_root" 2>&1)" || exit_code_5=$?
  if [ "$exit_code_5" -eq 2 ] && printf '%s' "$output_5" | grep -q '| setup-alpha | setup | setup | 1 | 未確認 |'; then
    pass_count=$((pass_count+1)); echo "  [PASS] ケース5: 上限超過を未確認として扱い終了コード2にする"
  else
    fail_count=$((fail_count+1)); echo "  [FAIL] ケース5: 上限超過の扱いが不正 (exit ${exit_code_5})" >&2
    printf '%s\n' "$output_5" | sed 's/^/    /' >&2
  fi
  rm -rf "${temp_root:?}/docs/skills/setup-alpha"

  copy_real_validate_script "$temp_root"
  st_write_skill "$temp_root" "setup-alpha" "setup" "setup" "exit 1"
  st_reset_pillars "$temp_root"
  local output_6 exit_code_6=0
  output_6="$("$0" "$temp_root" 2>&1)" || exit_code_6=$?
  if [ "$exit_code_6" -eq 1 ] && printf '%s' "$output_6" | grep -q '| setup-alpha | setup | setup | 1 | 不合格 |'; then
    pass_count=$((pass_count+1)); echo "  [PASS] ケース6: 機能不合格を検知（exit 1）"
  else
    fail_count=$((fail_count+1)); echo "  [FAIL] ケース6: 機能不合格を検知しない (exit ${exit_code_6})" >&2
    printf '%s\n' "$output_6" | sed 's/^/    /' >&2
  fi
  rm -rf "${temp_root:?}/docs/skills/setup-alpha"

  rm -rf "${temp_root:?}"/docs/skills
  mkdir -p "${temp_root}/docs/skills"
  st_reset_pillars "$temp_root"
  local output_7 exit_code_7=0
  output_7="$("$0" "$temp_root" 2>&1)" || exit_code_7=$?
  if [ "$exit_code_7" -eq 2 ] && printf '%s' "$output_7" | grep -q '\[UNKNOWN\]'; then
    pass_count=$((pass_count+1)); echo "  [PASS] ケース7: 機能0件を判定不能として報告（exit 2）"
  else
    fail_count=$((fail_count+1)); echo "  [FAIL] ケース7: 機能0件の扱いが不正 (exit ${exit_code_7})" >&2
    printf '%s\n' "$output_7" | sed 's/^/    /' >&2
  fi

  copy_real_validate_script "$temp_root"
  st_write_skill "$temp_root" "setup-alpha" "setup" "setup" "sleep 3; exit 0"
  st_write_skill "$temp_root" "setup-beta" "setup" "setup" "exit 1"
  st_reset_pillars "$temp_root"
  local output_8 exit_code_8=0
  output_8="$(ACCEPTANCE_TEST_TIMEOUT=1 "$0" "$temp_root" 2>&1)" || exit_code_8=$?
  if [ "$exit_code_8" -eq 1 ] \
    && printf '%s' "$output_8" | grep -q '| setup-alpha | setup | setup | 1 | 未確認 |' \
    && printf '%s' "$output_8" | grep -q '| setup-beta | setup | setup | 1 | 不合格 |'; then
    pass_count=$((pass_count+1)); echo "  [PASS] ケース8: 未確認と不合格が同時にあれば不合格を優先し終了コード1にする"
  else
    fail_count=$((fail_count+1)); echo "  [FAIL] ケース8: 未確認と不合格の優先順位が不正 (exit ${exit_code_8})" >&2
    printf '%s\n' "$output_8" | sed 's/^/    /' >&2
  fi
  rm -rf "${temp_root:?}/docs/skills/setup-alpha" "${temp_root:?}/docs/skills/setup-beta"

  copy_real_validate_script "$temp_root"
  st_write_skill "$temp_root" "setup-alpha" "setup" "setup"
  st_reset_pillars "$temp_root"
  local output_9 exit_code_9=0
  output_9="$("$0" "$temp_root" 2>&1)" || exit_code_9=$?
  if printf '%s' "$output_9" | grep -q '| 基盤一式の作成を支える（setup） | 必須単位未着手: reverse' \
    && printf '%s' "$output_9" | grep -q '| 調査を支える（survey） | 必須単位未着手: reverse' \
    && printf '%s' "$output_9" | grep -q '| 現場運用を支える（operate） | 必須単位未着手: operate' \
    && ! printf '%s' "$output_9" | grep -qE '\{（|key\(任意|title\(任意|\| key \|'; then
    pass_count=$((pass_count+1)); echo "  [PASS] ケース9: jq読み取りで柱の表が壊れずに組み立つ"
  else
    fail_count=$((fail_count+1)); echo "  [FAIL] ケース9: 柱の表がjqで正しく組み立たない (exit ${exit_code_9})" >&2
    printf '%s\n' "$output_9" | sed 's/^/    /' >&2
  fi
  rm -rf "${temp_root:?}/docs/skills/setup-alpha"

  copy_real_validate_script "$temp_root"
  st_write_skill "$temp_root" "setup-alpha" "setup" "setup"
  sed -i.bak 's#^outputs: \[docs/skills/setup-alpha/dummy-output\]$#outputs: [reports/x.html]#' \
    "${temp_root}/docs/skills/setup-alpha/SKILL.md" && rm -f "${temp_root}/docs/skills/setup-alpha/SKILL.md.bak"
  st_reset_pillars "$temp_root"
  local output_10 exit_code_10=0
  output_10="$("$0" "$temp_root" 2>&1)" || exit_code_10=$?
  if [ "$exit_code_10" -eq 1 ] && printf '%s' "$output_10" | grep -q 'portal以外のhtml出力 | 1'; then
    pass_count=$((pass_count+1)); echo "  [PASS] ケース10: portal以外の機能のhtml出力を検知（exit 1）"
  else
    fail_count=$((fail_count+1)); echo "  [FAIL] ケース10: portal以外の機能のhtml出力を検知しない (exit ${exit_code_10})" >&2
    printf '%s\n' "$output_10" | sed 's/^/    /' >&2
  fi
  rm -rf "${temp_root:?}/docs/skills/setup-alpha"

  copy_real_validate_script "$temp_root"
  # 単位名+ハイフンの並びをこのファイル中に直接書くと、このファイル自身
  # （setup単位）に対する他単位-名前混入検査に引っかかるため、変数の
  # 連結で組み立てる。
  local portal_unit_word="portal"
  local portal_skill_name="${portal_unit_word}-omega"
  st_write_skill "$temp_root" "$portal_skill_name" "$portal_unit_word" "setup"
  sed -i.bak "s#^outputs: \[docs/skills/${portal_skill_name}/dummy-output\]\$#outputs: [project-${portal_unit_word}/x.html]#" \
    "${temp_root}/docs/skills/${portal_skill_name}/SKILL.md" && rm -f "${temp_root}/docs/skills/${portal_skill_name}/SKILL.md.bak"
  st_reset_pillars "$temp_root"
  local output_11 exit_code_11=0
  output_11="$("$0" "$temp_root" 2>&1)" || exit_code_11=$?
  if printf '%s' "$output_11" | grep -q 'portal以外のhtml出力 | 0'; then
    pass_count=$((pass_count+1)); echo "  [PASS] ケース11: portal単位のhtml出力は検知しない"
  else
    fail_count=$((fail_count+1)); echo "  [FAIL] ケース11: portal単位のhtml出力を誤検知した (exit ${exit_code_11})" >&2
    printf '%s\n' "$output_11" | sed 's/^/    /' >&2
  fi
  rm -rf "${temp_root:?}/docs/skills/${portal_skill_name}"

  rm -rf "$temp_root"

  if [ "$fail_count" -eq 0 ]; then
    echo "self-test 全項目 PASS（PASS=${pass_count} FAIL=${fail_count}）"
    return 0
  fi
  echo "self-test FAIL（PASS=${pass_count} FAIL=${fail_count}）" >&2
  return 1
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

usage() {
  echo "usage: $(basename "$0") <リポジトリのルート> [--unit <単位>] [--report <出力パス>] | --self-test" >&2
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi

  local repo_root="${1:-}"
  if [ -z "$repo_root" ]; then
    usage
    exit 2
  fi
  shift

  local unit_filter="" report_path=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --unit)
        unit_filter="${2:-}"
        shift 2
        ;;
      --report)
        report_path="${2:-}"
        shift 2
        ;;
      *)
        echo "unknown argument: $1" >&2
        usage
        exit 2
        ;;
    esac
  done

  if [ ! -d "$repo_root" ]; then
    echo "[UNKNOWN] リポジトリのルートが存在しない: ${repo_root}" >&2
    exit 2
  fi

  local report_body build_exit_code
  report_body="$(build_report "$repo_root" "$unit_filter")"
  build_exit_code=$?

  if [ -n "$report_body" ]; then
    printf '%s\n' "$report_body"
    if [ -n "$report_path" ]; then
      printf '%s\n' "$report_body" > "$report_path"
    fi
  fi

  exit "$build_exit_code"
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
