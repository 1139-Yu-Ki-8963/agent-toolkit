#!/usr/bin/env bash
set -euo pipefail

# plan-setup.sh — 機能の宣言（unit・inputs・outputs・requires）から実行順の計画を組み立てる
#
# 目的:
#   docs/skills/<機能名>/SKILL.md の front matter を読み、機能名を直書きせずに
#   実行順を導く。判定方法の詳細（重なりの近似・既知の限界）は
#   docs/skills/setup-orchestrating-units/references/plan-setup.md を参照する。
#
# 使い方:
#   plan-setup.sh <リポジトリのルート> [--units a,b,c] [--target <対象リポジトリのルート>] [--format table|steps|both] [--until <機能名>]
#   plan-setup.sh --self-test
#
# 機能の定義の置き場:
#   既定は <リポジトリのルート>/docs/skills を読む。存在しない場合は
#   <リポジトリのルート>/.claude/skills を読む（納品先では docs/skills が無く
#   派生済みの .claude/skills だけがあるため）。どちらも無ければ終了コード2。
#
# 辺（実行順の根拠）:
#   (a) requires: X が requires に Y を挙げれば、Y → X（Yが先）
#   (b) 入出力: 機能 Y の outputs のいずれかと機能 X の inputs のいずれかが
#       「重なる」なら、Y → X（Yが先）
#
# 出力形式:
#   steps = "STEP <番号> <機能名>" を1行ずつ
#   table = Markdown の表（順・機能・単位・category・入力・出力・先行する機能とその理由）
#           と、外部入力（対象の出力のどれとも重ならない入力）の表
#   both  = 既定。steps の後に table
#
# --until <機能名>:
#   計画の中にその機能名のSTEPがあれば、そのSTEPまでで計画を打ち切る（以降の
#   STEPを出力しない）。無ければ終了コード2。table形式にも打ち切り後のSTEP集合
#   だけを反映する。
#
# 終了コード:
#   0 = 計画を返した
#   1 = 循環がある
#   2 = 対象となる機能が1件も無い、docs/skills が存在しない、--until に挙げた
#       機能名が計画のSTEPに無い、または一時領域の作成に失敗（--self-test のみ）
#
# 保守責任者: 人手（ユーザー）。辺の判定方法・出力形式を変える場合は
#   本スクリプトと docs/skills/setup-orchestrating-units/SKILL.md と
#   docs/skills/setup-orchestrating-units/references/plan-setup.md を同時に更新する。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

# ---------------------------------------------------------------------------
# front matter 読み取り（setup-deriving-skills の validate-skill-definitions.sh と同じ実装）
# ---------------------------------------------------------------------------

fm_extract() {
  local file="$1"
  local first_line
  first_line="$(head -n1 "$file" 2>/dev/null || true)"
  if [ "$first_line" != "---" ]; then
    return 1
  fi
  awk 'NR==1{next} /^---$/{exit} {print}' "$file"
  return 0
}

fm_get_scalar() {
  local body="$1" key="$2"
  printf '%s\n' "$body" | awk -v k="$key" '
    index($0, k ": ") == 1 { sub("^" k ": ", ""); print; exit }
    $0 == k ":" { print ""; exit }
  '
}

fm_get_array_raw() {
  local body="$1" key="$2"
  local line
  line="$(printf '%s\n' "$body" | grep -E "^${key}:" | head -n1 || true)"
  if [ -z "$line" ]; then
    return 1
  fi
  printf '%s\n' "${line#"${key}: "}"
  return 0
}

is_empty_array() {
  case "$1" in
    "[]") return 0 ;;
    *) return 1 ;;
  esac
}

array_elements() {
  local raw="$1"
  raw="${raw#\[}"
  raw="${raw%\]}"
  [ -n "$raw" ] || return 0
  printf '%s\n' "$raw" | tr ',' '\n' | sed -e 's/^ *//' -e 's/ *$//'
}

# ---------------------------------------------------------------------------
# 重なりの判定（近似）
# ---------------------------------------------------------------------------

prefix_of_pattern() {
  local p="$1"
  case "$p" in
    *'*'*) printf '%s' "${p%%\**}" ;;
    *) printf '%s' "$p" ;;
  esac
}

patterns_overlap() {
  local a b
  a="$(prefix_of_pattern "$1")"
  b="$(prefix_of_pattern "$2")"
  case "$b" in "$a"*) return 0 ;; esac
  case "$a" in "$b"*) return 0 ;; esac
  return 1
}

# ---------------------------------------------------------------------------
# 機能の読み込み
# ---------------------------------------------------------------------------

NAMES=(); UNITS=(); CATEGORIES=(); INPUTS_RAW=(); OUTPUTS_RAW=(); REQUIRES_RAW=()

load_skills() {
  local skills_root="$1" units_filter="$2"
  NAMES=(); UNITS=(); CATEGORIES=(); INPUTS_RAW=(); OUTPUTS_RAW=(); REQUIRES_RAW=()
  local files
  files="$(find "$skills_root" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' 2>/dev/null | sort)"
  [ -n "$files" ] || return 0
  local f dir name body v_unit ir orw rr
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    dir="$(dirname "$f")"
    name="$(basename "$dir")"
    body="$(fm_extract "$f")" || continue
    v_unit="$(fm_get_scalar "$body" unit)"
    if [ -n "$units_filter" ]; then
      case ",${units_filter}," in
        *",${v_unit},"*) : ;;
        *) continue ;;
      esac
    fi
    ir="$(fm_get_array_raw "$body" inputs || true)"
    [ -n "$ir" ] || ir="[]"
    orw="$(fm_get_array_raw "$body" outputs || true)"
    [ -n "$orw" ] || orw="[]"
    rr="$(fm_get_array_raw "$body" requires || true)"
    [ -n "$rr" ] || rr="[]"
    NAMES+=("$name")
    UNITS+=("$v_unit")
    CATEGORIES+=("$(fm_get_scalar "$body" category)")
    INPUTS_RAW+=("$ir")
    OUTPUTS_RAW+=("$orw")
    REQUIRES_RAW+=("$rr")
  done <<LIST
$files
LIST
}

# ---------------------------------------------------------------------------
# 辺の算出
# ---------------------------------------------------------------------------

EDGE_FROM=(); EDGE_TO=(); EDGE_REASON=()

add_edge() {
  local from="$1" to="$2" reason="$3"
  local k
  for ((k = 0; k < ${#EDGE_FROM[@]}; k++)); do
    if [ "${EDGE_FROM[$k]}" = "$from" ] && [ "${EDGE_TO[$k]}" = "$to" ]; then
      EDGE_REASON[$k]="${EDGE_REASON[$k]}; ${reason}"
      return 0
    fi
  done
  EDGE_FROM+=("$from")
  EDGE_TO+=("$to")
  EDGE_REASON+=("$reason")
}

index_of_name() {
  local target="$1" n=${#NAMES[@]} j
  for ((j = 0; j < n; j++)); do
    if [ "${NAMES[$j]}" = "$target" ]; then
      printf '%s' "$j"
      return 0
    fi
  done
  return 1
}

compute_edges() {
  EDGE_FROM=(); EDGE_TO=(); EDGE_REASON=()
  local n=${#NAMES[@]}
  local i j req ridx

  # (a) requires
  for ((i = 0; i < n; i++)); do
    is_empty_array "${REQUIRES_RAW[$i]}" && continue
    while IFS= read -r req; do
      [ -n "$req" ] || continue
      if ridx="$(index_of_name "$req")"; then
        add_edge "$ridx" "$i" "requires"
      fi
    done <<REQLIST
$(array_elements "${REQUIRES_RAW[$i]}")
REQLIST
  done

  # (b) 入出力の重なり
  local outp inp
  for ((i = 0; i < n; i++)); do
    is_empty_array "${OUTPUTS_RAW[$i]}" && continue
    while IFS= read -r outp; do
      [ -n "$outp" ] || continue
      for ((j = 0; j < n; j++)); do
        [ "$j" -ne "$i" ] || continue
        is_empty_array "${INPUTS_RAW[$j]}" && continue
        while IFS= read -r inp; do
          [ -n "$inp" ] || continue
          if patterns_overlap "$outp" "$inp"; then
            add_edge "$i" "$j" "入出力: ${outp} と ${inp}"
          fi
        done <<INLIST
$(array_elements "${INPUTS_RAW[$j]}")
INLIST
      done
    done <<OUTLIST
$(array_elements "${OUTPUTS_RAW[$i]}")
OUTLIST
  done
}

# ---------------------------------------------------------------------------
# トポロジカル順（同順位は名前の辞書順）
# ---------------------------------------------------------------------------

ORDER=()
PLACED=()

topo_sort() {
  local n=${#NAMES[@]}
  local -a indeg
  local i k t best
  for ((i = 0; i < n; i++)); do indeg[$i]=0; PLACED[$i]=0; done
  for ((k = 0; k < ${#EDGE_FROM[@]}; k++)); do
    t="${EDGE_TO[$k]}"
    indeg[$t]=$((indeg[$t] + 1))
  done

  ORDER=()
  local placed_count=0
  while [ "$placed_count" -lt "$n" ]; do
    best=-1
    for ((i = 0; i < n; i++)); do
      if [ "${PLACED[$i]}" -eq 0 ] && [ "${indeg[$i]}" -eq 0 ]; then
        if [ "$best" -eq -1 ] || [[ "${NAMES[$i]}" < "${NAMES[$best]}" ]]; then
          best=$i
        fi
      fi
    done
    if [ "$best" -eq -1 ]; then
      return 1
    fi
    ORDER+=("$best")
    PLACED[$best]=1
    placed_count=$((placed_count + 1))
    for ((k = 0; k < ${#EDGE_FROM[@]}; k++)); do
      if [ "${EDGE_FROM[$k]}" -eq "$best" ]; then
        t="${EDGE_TO[$k]}"
        if [ "${PLACED[$t]}" -eq 0 ]; then
          indeg[$t]=$((indeg[$t] - 1))
        fi
      fi
    done
  done
  return 0
}

# 循環の一例を「A → B → A」の形で返す（PLACED=0 の残存ノードから探す）
find_cycle_message() {
  local n=${#NAMES[@]}
  local start=-1 ci
  for ((ci = 0; ci < n; ci++)); do
    if [ "${PLACED[$ci]}" -eq 0 ]; then
      if [ "$start" -eq -1 ] || [[ "${NAMES[$ci]}" < "${NAMES[$start]}" ]]; then
        start=$ci
      fi
    fi
  done
  if [ "$start" -eq -1 ]; then
    printf '%s' "(循環の特定に失敗)"
    return
  fi

  local -a path
  local -a visited
  for ((ci = 0; ci < n; ci++)); do visited[$ci]=0; done
  local cur="$start" found k
  while [ "${visited[$cur]}" -eq 0 ]; do
    visited[$cur]=1
    path+=("$cur")
    found=-1
    for ((k = 0; k < ${#EDGE_FROM[@]}; k++)); do
      if [ "${EDGE_TO[$k]}" -eq "$cur" ] && [ "${PLACED[${EDGE_FROM[$k]}]}" -eq 0 ]; then
        found="${EDGE_FROM[$k]}"
        break
      fi
    done
    if [ "$found" -eq -1 ]; then
      printf '%s' "(循環の特定に失敗)"
      return
    fi
    cur="$found"
  done

  local idx=-1
  local plen=${#path[@]}
  for ((ci = 0; ci < plen; ci++)); do
    if [ "${path[$ci]}" -eq "$cur" ]; then
      idx=$ci
      break
    fi
  done

  local -a cyc
  cyc+=("${NAMES[${path[$idx]}]}")
  for ((ci = plen - 1; ci > idx; ci--)); do
    cyc+=("${NAMES[${path[$ci]}]}")
  done
  cyc+=("${NAMES[${path[$idx]}]}")

  local msg="" first=1 nm
  for nm in "${cyc[@]}"; do
    if [ "$first" -eq 1 ]; then
      msg="$nm"
      first=0
    else
      msg="${msg} → ${nm}"
    fi
  done
  printf '%s' "$msg"
}

# ---------------------------------------------------------------------------
# 出力
# ---------------------------------------------------------------------------

print_steps() {
  local i n=${#ORDER[@]}
  for ((i = 0; i < n; i++)); do
    echo "STEP $((i + 1)) ${NAMES[${ORDER[$i]}]}"
  done
}

predecessors_of() {
  local idx="$1" k out=""
  for ((k = 0; k < ${#EDGE_FROM[@]}; k++)); do
    if [ "${EDGE_TO[$k]}" -eq "$idx" ]; then
      if [ -n "$out" ]; then out="${out}; "; fi
      out="${out}${NAMES[${EDGE_FROM[$k]}]}（${EDGE_REASON[$k]}）"
    fi
  done
  [ -n "$out" ] || out="-"
  printf '%s' "$out"
}

joined_elements() {
  local raw="$1"
  array_elements "$raw" | tr '\n' ',' | sed -e 's/,$//' -e 's/,/, /g'
}

input_is_external() {
  local self_idx="$1" pattern="$2" total=${#NAMES[@]} j outp
  for ((j = 0; j < total; j++)); do
    [ "$j" -ne "$self_idx" ] || continue
    is_empty_array "${OUTPUTS_RAW[$j]}" && continue
    while IFS= read -r outp; do
      [ -n "$outp" ] || continue
      if patterns_overlap "$pattern" "$outp"; then
        return 1
      fi
    done <<OUTLIST2
$(array_elements "${OUTPUTS_RAW[$j]}")
OUTLIST2
  done
  return 0
}

# 対象リポジトリの下に、パターンに一致するファイルが1件でもあるかを確かめる。
# 戻り値: 0=実在 1=無い 2=対象未指定または対象パス不在
target_has_match() {
  local target="$1" pattern="$2"
  [ -n "$target" ] || return 2
  [ -d "$target" ] || return 2
  local full="${target%/}/${pattern}"
  local found
  found="$(find "$target" -path "$full" 2>/dev/null | head -n1 || true)"
  [ -n "$found" ]
}

print_table() {
  local target="$1"
  local n=${#ORDER[@]}
  local pos idx
  echo "| 順 | 機能 | 単位 | category | 入力 | 出力 | 先行する機能とその理由 |"
  echo "|---|---|---|---|---|---|---|"
  for ((pos = 0; pos < n; pos++)); do
    idx="${ORDER[$pos]}"
    echo "| $((pos + 1)) | ${NAMES[$idx]} | ${UNITS[$idx]} | ${CATEGORIES[$idx]} | $(joined_elements "${INPUTS_RAW[$idx]}") | $(joined_elements "${OUTPUTS_RAW[$idx]}") | $(predecessors_of "$idx") |"
  done
  echo
  echo "外部入力（対象の出力のどれとも重ならない入力）:"
  echo
  echo "| 機能 | 入力 | 対象での状態 |"
  echo "|---|---|---|"
  local total=${#NAMES[@]} idx2 inp any_ext=0 status
  for ((idx2 = 0; idx2 < total; idx2++)); do
    is_empty_array "${INPUTS_RAW[$idx2]}" && continue
    while IFS= read -r inp; do
      [ -n "$inp" ] || continue
      if input_is_external "$idx2" "$inp"; then
        any_ext=1
        if [ -z "$target" ]; then
          status="(対象未指定)"
        elif [ ! -d "$target" ]; then
          status="(対象パス不在)"
        elif target_has_match "$target" "$inp"; then
          status="対象に実在"
        else
          status="対象に無い"
        fi
        echo "| ${NAMES[$idx2]} | ${inp} | ${status} |"
      fi
    done <<INLIST2
$(array_elements "${INPUTS_RAW[$idx2]}")
INLIST2
  done
  if [ "$any_ext" -eq 0 ]; then
    echo "| （該当なし） | - | - |"
  fi
}

# --untilで指定した機能名までにORDERを切り詰める（見つからなければ1を返す）
truncate_until() {
  local until_name="$1"
  [ -n "$until_name" ] || return 0
  local n=${#ORDER[@]} i idx=-1
  for ((i = 0; i < n; i++)); do
    if [ "${NAMES[${ORDER[$i]}]}" = "$until_name" ]; then
      idx=$i
      break
    fi
  done
  if [ "$idx" -eq -1 ]; then
    echo "[UNKNOWN] --untilに挙げた機能が計画のSTEPに無い: ${until_name}" >&2
    return 1
  fi
  local new_order=() j
  for ((j = 0; j <= idx; j++)); do
    new_order+=("${ORDER[$j]}")
  done
  ORDER=("${new_order[@]}")
  return 0
}

run_plan() {
  local skills_root="$1" units="$2" target="$3" format="$4" until_name="${5:-}"
  load_skills "$skills_root" "$units"
  local n=${#NAMES[@]}
  if [ "$n" -eq 0 ]; then
    echo "[UNKNOWN] 対象となる機能が1件も無い" >&2
    return 2
  fi
  compute_edges
  if ! topo_sort; then
    echo "[FAIL] 循環: $(find_cycle_message)" >&2
    return 1
  fi
  if ! truncate_until "$until_name"; then
    return 2
  fi
  case "$format" in
    steps) print_steps ;;
    table) print_table "$target" ;;
    *)
      print_steps
      echo
      print_table "$target"
      ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

bst_write_skill() {
  # $1: skills_root  $2: name  $3: unit  $4: category  $5: inputs  $6: outputs  $7: requires
  local sroot="$1" name="$2" unit="$3" category="$4" inputs="$5" outputs="$6" requires="$7"
  local dir="${sroot}/${name}"
  mkdir -p "${dir}/tests"
  cat > "${dir}/SKILL.md" <<EOF
---
name: ${name}
日本語名: テスト用機能
description: "self-test用の機能定義。"
invocation: ${name}
type: transform
allowed-tools: [Bash]
unit: ${unit}
category: ${category}
kind: none
inputs: ${inputs}
outputs: ${outputs}
requires: ${requires}
acceptance: tests/
---

## いつ使うか

self-test用。
EOF
  cat > "${dir}/tests/test-dummy.sh" <<'TESTEOF'
#!/usr/bin/env bash
exit 0
TESTEOF
  chmod +x "${dir}/tests/test-dummy.sh"
}

line_of() {
  printf '%s\n' "$1" | grep -n -m1 -F "$2" | cut -d: -f1
}

self_test() {
  local pass=0 fail=0
  local root
  if ! root="$(mktemp -d "${TMPDIR:-/tmp}/plan-setup-self-test.XXXXXX" 2>/dev/null)" || [ -z "$root" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  local repo="${root}/repo"
  local skills_root="${repo}/docs/skills"
  mkdir -p "$skills_root"

  # ケース1: 入出力の重なりで順序が決まる
  bst_write_skill "$skills_root" "setup-produce" "setup" "setup" \
    "[docs/skills/setup-produce/dummy]" "[docs/mid/*/out.md]" "[]"
  bst_write_skill "$skills_root" "setup-consume" "setup" "setup" \
    "[docs/mid/*/out.md]" "[docs/skills/setup-consume/dummy]" "[]"
  local out1 rc1=0
  out1="$("$0" "$repo" --units setup --format steps 2>&1)" || rc1=$?
  if [ "$rc1" -eq 0 ] && [ -n "$(line_of "$out1" setup-produce)" ] && [ -n "$(line_of "$out1" setup-consume)" ] \
    && [ "$(line_of "$out1" setup-produce)" -lt "$(line_of "$out1" setup-consume)" ]; then
    pass=$((pass + 1)); echo "  [PASS] ケース1: 入出力の重なりで順序が決まる"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース1: 入出力の重なりで順序が決まらない (exit ${rc1})" >&2
    printf '%s\n' "$out1" | sed 's/^/    /' >&2
  fi
  rm -rf "${skills_root:?}"/*

  # ケース2: requires で順序が決まる（入出力は無関係にする）
  bst_write_skill "$skills_root" "setup-dep-a" "setup" "setup" \
    "[docs/skills/setup-dep-a/x]" "[docs/skills/setup-dep-a/y]" "[]"
  bst_write_skill "$skills_root" "setup-dep-b" "setup" "setup" \
    "[docs/skills/setup-dep-b/x]" "[docs/skills/setup-dep-b/y]" "[setup-dep-a]"
  local out2 rc2=0
  out2="$("$0" "$repo" --units setup --format steps 2>&1)" || rc2=$?
  if [ "$rc2" -eq 0 ] && [ -n "$(line_of "$out2" setup-dep-a)" ] && [ -n "$(line_of "$out2" setup-dep-b)" ] \
    && [ "$(line_of "$out2" setup-dep-a)" -lt "$(line_of "$out2" setup-dep-b)" ]; then
    pass=$((pass + 1)); echo "  [PASS] ケース2: requires で順序が決まる"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース2: requires で順序が決まらない (exit ${rc2})" >&2
    printf '%s\n' "$out2" | sed 's/^/    /' >&2
  fi
  rm -rf "${skills_root:?}"/*

  # ケース3: 循環があれば終了コード1
  bst_write_skill "$skills_root" "setup-cycle-a" "setup" "setup" \
    "[docs/cycle/b-out/*]" "[docs/cycle/a-out/*]" "[]"
  bst_write_skill "$skills_root" "setup-cycle-b" "setup" "setup" \
    "[docs/cycle/a-out/*]" "[docs/cycle/b-out/*]" "[]"
  local out3 rc3=0
  out3="$("$0" "$repo" --units setup --format steps 2>&1)" || rc3=$?
  if [ "$rc3" -eq 1 ] && printf '%s' "$out3" | grep -q '\[FAIL\] 循環:' \
    && printf '%s' "$out3" | grep -q 'setup-cycle-a' && printf '%s' "$out3" | grep -q 'setup-cycle-b'; then
    pass=$((pass + 1)); echo "  [PASS] ケース3: 循環を検知（exit 1）"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース3: 循環を検知しない (exit ${rc3})" >&2
    printf '%s\n' "$out3" | sed 's/^/    /' >&2
  fi
  rm -rf "${skills_root:?}"/*

  # ケース4: --units による絞り込み
  local h4='-'
  local other_unit_name="reverse${h4}other"
  bst_write_skill "$skills_root" "setup-plain" "setup" "setup" \
    "[docs/skills/setup-plain/x]" "[docs/skills/setup-plain/y]" "[]"
  bst_write_skill "$skills_root" "$other_unit_name" "reverse" "setup" \
    "[docs/skills/${other_unit_name}/x]" "[docs/skills/${other_unit_name}/y]" "[]"
  local out4 rc4=0
  out4="$("$0" "$repo" --units setup --format steps 2>&1)" || rc4=$?
  if [ "$rc4" -eq 0 ] && printf '%s' "$out4" | grep -q 'setup-plain' \
    && ! printf '%s' "$out4" | grep -q "$other_unit_name"; then
    pass=$((pass + 1)); echo "  [PASS] ケース4: --units で単位を絞り込む"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース4: --units の絞り込みが不正 (exit ${rc4})" >&2
    printf '%s\n' "$out4" | sed 's/^/    /' >&2
  fi
  rm -rf "${skills_root:?}"/*

  # ケース5: 外部入力の表示（--target あり・実在／無い の両方）
  bst_write_skill "$skills_root" "setup-ext" "setup" "setup" \
    "[docs/external/thing.md]" "[docs/skills/setup-ext/out]" "[]"
  local target_with="${root}/target-with" target_without="${root}/target-without"
  mkdir -p "${target_with}/docs/external" "${target_without}"
  : > "${target_with}/docs/external/thing.md"
  local out5a rc5a=0 out5b rc5b=0
  out5a="$("$0" "$repo" --units setup --format table --target "$target_with" 2>&1)" || rc5a=$?
  out5b="$("$0" "$repo" --units setup --format table --target "$target_without" 2>&1)" || rc5b=$?
  if [ "$rc5a" -eq 0 ] && printf '%s' "$out5a" | grep -q '対象に実在' \
    && [ "$rc5b" -eq 0 ] && printf '%s' "$out5b" | grep -q '対象に無い'; then
    pass=$((pass + 1)); echo "  [PASS] ケース5: 外部入力の対象での状態を表示する"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース5: 外部入力の表示が不正 (exit ${rc5a}/${rc5b})" >&2
    printf '%s\n' "$out5a" | sed 's/^/    /' >&2
    printf '%s\n' "$out5b" | sed 's/^/    /' >&2
  fi
  rm -rf "${skills_root:?}"/*

  # ケース6: 依存の無い機能どうしは名前の辞書順で決定的
  bst_write_skill "$skills_root" "setup-zulu" "setup" "setup" \
    "[docs/skills/setup-zulu/x]" "[docs/skills/setup-zulu/y]" "[]"
  bst_write_skill "$skills_root" "setup-alpha" "setup" "setup" \
    "[docs/skills/setup-alpha/x]" "[docs/skills/setup-alpha/y]" "[]"
  local out6 rc6=0
  out6="$("$0" "$repo" --units setup --format steps 2>&1)" || rc6=$?
  if [ "$rc6" -eq 0 ] && [ -n "$(line_of "$out6" setup-alpha)" ] && [ -n "$(line_of "$out6" setup-zulu)" ] \
    && [ "$(line_of "$out6" setup-alpha)" -lt "$(line_of "$out6" setup-zulu)" ]; then
    pass=$((pass + 1)); echo "  [PASS] ケース6: 無関係な機能は名前の辞書順で決定的"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース6: 辞書順での決定性が崩れている (exit ${rc6})" >&2
    printf '%s\n' "$out6" | sed 's/^/    /' >&2
  fi
  rm -rf "${skills_root:?}"/*

  # ケース7: docs/skills が無く .claude/skills だけがある場合にfallbackで計画が返る
  local root7 repo7 claude_skills_root
  if ! root7="$(mktemp -d "${TMPDIR:-/tmp}/plan-setup-self-test-fallback.XXXXXX" 2>/dev/null)" || [ -z "$root7" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  repo7="${root7}/repo"
  claude_skills_root="${repo7}/.claude/skills"
  mkdir -p "$claude_skills_root"
  bst_write_skill "$claude_skills_root" "setup-fallback" "setup" "setup" \
    "[docs/skills/setup-fallback/x]" "[docs/skills/setup-fallback/y]" "[]"
  local out7 rc7=0
  out7="$("$0" "$repo7" --units setup --format steps 2>&1)" || rc7=$?
  if [ "$rc7" -eq 0 ] && printf '%s' "$out7" | grep -q 'setup-fallback'; then
    pass=$((pass + 1)); echo "  [PASS] ケース7: docs/skills が無く .claude/skills だけがある一時領域で計画が返る"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース7: .claude/skills へのfallbackが機能しない (exit ${rc7})" >&2
    printf '%s\n' "$out7" | sed 's/^/    /' >&2
  fi
  rm -rf "$root7"


  # ケース8: --untilで指定した機能までで打ち切る
  bst_write_skill "$skills_root" "setup-until-a" "setup" "setup" \
    "[docs/skills/setup-until-a/x]" "[docs/mid2/*/out.md]" "[]"
  bst_write_skill "$skills_root" "setup-until-b" "setup" "setup" \
    "[docs/mid2/*/out.md]" "[docs/skills/setup-until-b/y]" "[]"
  bst_write_skill "$skills_root" "setup-until-c" "setup" "setup" \
    "[docs/skills/setup-until-c/x]" "[docs/skills/setup-until-c/y]" "[setup-until-b]"
  local out8 rc8=0
  out8="$("$0" "$repo" --units setup --format steps --until setup-until-b 2>&1)" || rc8=$?
  if [ "$rc8" -eq 0 ] && printf '%s' "$out8" | grep -q 'setup-until-b' \
    && ! printf '%s' "$out8" | grep -q 'setup-until-c'; then
    pass=$((pass + 1)); echo "  [PASS] ケース8: --untilで指定した機能までで打ち切る"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース8: --untilの打ち切りが不正 (exit ${rc8})" >&2
    printf '%s\n' "$out8" | sed 's/^/    /' >&2
  fi

  # ケース9: --untilに挙げた機能が計画に無ければ終了コード2
  local out9 rc9=0
  out9="$("$0" "$repo" --units setup --format steps --until setup-not-exist 2>&1)" || rc9=$?
  if [ "$rc9" -eq 2 ]; then
    pass=$((pass + 1)); echo "  [PASS] ケース9: --untilの対象不在で終了コード2"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース9: --untilの対象不在を検知しない (exit ${rc9})" >&2
    printf '%s\n' "$out9" | sed 's/^/    /' >&2
  fi
  rm -rf "${skills_root:?}"/*
  rm -rf "$root"

  if [ "$fail" -eq 0 ]; then
    echo "self-test 全項目 PASS（PASS=${pass} FAIL=${fail}）"
    return 0
  fi
  echo "self-test FAIL（PASS=${pass} FAIL=${fail}）" >&2
  return 1
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi

  local root="" units="" target="" format="both" until_name=""
  local args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --units) units="${2:-}"; shift 2 ;;
      --target) target="${2:-}"; shift 2 ;;
      --format) format="${2:-both}"; shift 2 ;;
      --until) until_name="${2:-}"; shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  if [ "${#args[@]}" -ne 1 ]; then
    echo "usage: $(basename "$0") <リポジトリのルート> [--units a,b,c] [--target <対象>] [--format table|steps|both] [--until <機能名>] | --self-test" >&2
    exit 2
  fi
  root="${args[0]}"
  local skills_root="${root%/}/docs/skills"
  if [ ! -d "$skills_root" ]; then
    skills_root="${root%/}/.claude/skills"
  fi
  if [ ! -d "$skills_root" ]; then
    echo "ERROR: docs/skills も .claude/skills も存在しない: ${root%/}" >&2
    exit 2
  fi

  run_plan "$skills_root" "$units" "$target" "$format" "$until_name"
  exit $?
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
