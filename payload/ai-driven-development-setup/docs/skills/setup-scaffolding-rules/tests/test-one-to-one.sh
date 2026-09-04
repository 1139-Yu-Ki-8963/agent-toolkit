#!/usr/bin/env bash
set -u

# test-one-to-one.sh — 規約の定義（templates/rules/tool-defined/）が
#   「規約1件=フォルダ1つ=rule.md + checker + checker.test.sh」の1対1配置を
#   保っているかを確かめる。
#
# 確かめる内容:
#   1. templates/rules/checkers/ という単一集約フォルダが存在しない
#   2. rule-taxonomy.json が checker を宣言する子カテゴリごとに、
#      templates/rules/tool-defined/<親>/<子>/ の直下へ
#      checker本体と <checkerのベース名>.test.sh が実在する
#   3. 各 <親>/<子>/ フォルダに、宣言外の check-*.sh（.test.shを除く）が無い
#   4. 同じ checker を複数の子カテゴリが宣言していない（規約と検査の1対1）
#
# 加えて、上記2・3・4の検査自体が実際に効いているかを、否定側のケース
# （checker欠落・test欠落・宣言外ファイル混入・checker名の重複）で確かめる。
# ${TMPDIR:-/tmp}配下に合成フィクスチャを作り、各ケースで意図的に不合格を
# 作ってから検査を呼び、不合格として検出できるかを見る。mktempの失敗は
# 判定不能規約（.claude/rules/always/verification/indeterminate-result/rule.md
# の考え方）に従い [UNKNOWN]・終了コード2とする。
#
# set -e は使わない。失敗しても最後まで実行し、失敗本数を数えるためである。
#
# 使い方:
#   bash test-one-to-one.sh                                    実データ（既定）を検査する
#   bash test-one-to-one.sh <tool-defined-dir> <taxonomy-json>  対象フォルダを差し替えて検査する

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_TOOLDEFINED_DIR="${S_ROOT}/templates/rules/tool-defined"
CHECKERS_DIR="${S_ROOT}/templates/rules/checkers"
DEFAULT_TAXONOMY_JSON="${S_ROOT}/references/rule-taxonomy.json"

TOOLDEFINED_DIR="${1:-$DEFAULT_TOOLDEFINED_DIR}"
TAXONOMY_JSON="${2:-$DEFAULT_TAXONOMY_JSON}"

FAIL=0

report_pass() { echo "  [PASS] $1"; }
report_fail() {
  echo "  [FAIL] $1" >&2
  FAIL=$((FAIL + 1))
}

if ! command -v jq >/dev/null 2>&1; then
  echo "[UNKNOWN] jqが無いため判定できません" >&2
  exit 2
fi

# 1. 単一集約フォルダが存在しない（常にこのスキル自身の実データを見る。
#    差し替え対象外。単一集約フォルダの復活は対象フォルダの引数と無関係に
#    検出すべき欠陥のため）
if [ -d "$CHECKERS_DIR" ]; then
  report_fail "旧来の単一集約フォルダが残っている: ${CHECKERS_DIR}"
else
  report_pass "単一集約フォルダ（templates/rules/checkers/）が存在しない"
fi

# run_one_to_one_checks: 2・3・4の検査本体。
#   $1: tool-defined ディレクトリ  $2: taxonomy の JSON パス
# [PASS] は標準出力、[FAIL] は標準エラーへ出す。不合格件数を終了コードとして返す
# （呼び出し側が `fn ...; rc=$?` または `out="$(fn ... 2>&1)"; rc=$?` で受け取る）。
run_one_to_one_checks() {
  local tooldefined_dir="$1" taxonomy_json="$2"
  local fail=0 declared_all=0 declared_ok=0 exclusive_all_ok=1 dup_found=0
  local checker_seen="" children_lines pkey ckey cchecker child_dir checker_test other_files

  children_lines="$(jq -r '.parents[] | .key as $p | .children[] | "\($p)\t\(.key)\t\(.checker // empty)"' "$taxonomy_json")"

  while IFS=$'\t' read -r pkey ckey cchecker; do
    [ -n "$ckey" ] || continue
    child_dir="${tooldefined_dir}/${pkey}/${ckey}"

    if [ ! -f "${child_dir}/rule.md" ]; then
      echo "  [FAIL] rule.mdが実在しない: ${child_dir}/rule.md" >&2
      fail=$((fail + 1))
    fi

    if [ -z "$cchecker" ] || [ "$cchecker" = "null" ]; then
      continue
    fi

    declared_all=$((declared_all + 1))
    checker_test="${cchecker%.sh}.test.sh"

    if [ -f "${child_dir}/${cchecker}" ] && [ -f "${child_dir}/${checker_test}" ]; then
      declared_ok=$((declared_ok + 1))
    else
      echo "  [FAIL] checkerまたはtestが実在しない: ${child_dir}/${cchecker}（またはtest）" >&2
      fail=$((fail + 1))
    fi

    # 3. 宣言外のcheck-*.shが無いこと
    other_files="$(find "$child_dir" -maxdepth 1 -type f -name 'check-*.sh' ! -name '*.test.sh' ! -name "$cchecker" 2>/dev/null)"
    if [ -n "$other_files" ]; then
      exclusive_all_ok=0
      echo "  [FAIL] 宣言外のcheck-*.shが同フォルダに存在する: ${other_files}" >&2
      fail=$((fail + 1))
    fi

    # 4. checkerの一意性（子カテゴリ横断）
    if printf '%s\n' "$checker_seen" | grep -qxF "$cchecker"; then
      dup_found=1
      echo "  [FAIL] 同じcheckerを複数の規約が宣言している: ${cchecker}" >&2
      fail=$((fail + 1))
    fi
    checker_seen="${checker_seen}${cchecker}
"
  done <<INNER_EOF
$children_lines
INNER_EOF

  if [ "$declared_all" -gt 0 ] && [ "$declared_ok" -eq "$declared_all" ]; then
    echo "  [PASS] checkerを宣言する${declared_all}件の子カテゴリすべてにcheckerとtestが実在する"
  fi

  if [ "$exclusive_all_ok" -eq 1 ]; then
    echo "  [PASS] 全子カテゴリのフォルダに宣言外のcheck-*.shが無い"
  fi

  if [ "$dup_found" -eq 0 ]; then
    echo "  [PASS] 同じcheckerを複数の規約が宣言していない（規約と検査の1対1）"
  fi

  return "$fail"
}

# 実データ（または引数で差し替えたフォルダ）に対する主検査
run_one_to_one_checks "$TOOLDEFINED_DIR" "$TAXONOMY_JSON"
main_rc=$?
FAIL=$((FAIL + main_rc))

# --- 否定側のケース ---
# 上のrun_one_to_one_checksが実際に効いているかを、合成フィクスチャで確かめる。
NEG_FAIL=0
st_report_pass() { echo "  [PASS] $1"; }
st_report_fail() {
  echo "  [FAIL] $1" >&2
  NEG_FAIL=$((NEG_FAIL + 1))
}

# ベースのフィクスチャを作る: catA/childA（checker: check-a.sh）と
# catA/childB（checker: check-b.sh）の2規約が、rule.md・checker・testを
# 揃えて存在する状態。各ケースはこの状態から1点だけを崩す。
st_build_fixture() {
  local base="$1"
  mkdir -p "${base}/tool-defined/catA/childA" "${base}/tool-defined/catA/childB"
  cat > "${base}/tool-defined/catA/childA/rule.md" <<'EOF'
---
key: childA
---
# childA（テスト用フィクスチャ）
EOF
  cat > "${base}/tool-defined/catA/childB/rule.md" <<'EOF'
---
key: childB
---
# childB（テスト用フィクスチャ）
EOF
  echo '#!/usr/bin/env bash' > "${base}/tool-defined/catA/childA/check-a.sh"
  echo '#!/usr/bin/env bash' > "${base}/tool-defined/catA/childA/check-a.test.sh"
  echo '#!/usr/bin/env bash' > "${base}/tool-defined/catA/childB/check-b.sh"
  echo '#!/usr/bin/env bash' > "${base}/tool-defined/catA/childB/check-b.test.sh"
  cat > "${base}/taxonomy.json" <<'EOF'
{"parents":[{"key":"catA","children":[{"key":"childA","checker":"check-a.sh"},{"key":"childB","checker":"check-b.sh"}]}]}
EOF
}

if ! neg_root="$(mktemp -d "${TMPDIR:-/tmp}/test-one-to-one-neg.XXXXXX" 2>/dev/null)" || [ -z "$neg_root" ]; then
  echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため否定側のケースを判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi

# (a) checkerを消す
case_a="${neg_root}/case-a"
st_build_fixture "$case_a"
rm -f "${case_a}/tool-defined/catA/childA/check-a.sh"
a_out="$(run_one_to_one_checks "${case_a}/tool-defined" "${case_a}/taxonomy.json" 2>&1)"
a_rc=$?
if [ "$a_rc" -ne 0 ] && printf '%s' "$a_out" | grep -q 'checkerまたはtestが実在しない'; then
  st_report_pass "checkerを消すと不合格になる"
else
  st_report_fail "checkerを消しても不合格にならない"
fi

# (b) .test.shを消す
case_b="${neg_root}/case-b"
st_build_fixture "$case_b"
rm -f "${case_b}/tool-defined/catA/childA/check-a.test.sh"
b_out="$(run_one_to_one_checks "${case_b}/tool-defined" "${case_b}/taxonomy.json" 2>&1)"
b_rc=$?
if [ "$b_rc" -ne 0 ] && printf '%s' "$b_out" | grep -q 'checkerまたはtestが実在しない'; then
  st_report_pass ".test.shを消すと不合格になる"
else
  st_report_fail ".test.shを消しても不合格にならない"
fi

# (c) 宣言の無いcheck-*.shを置く
case_c="${neg_root}/case-c"
st_build_fixture "$case_c"
echo '#!/usr/bin/env bash' > "${case_c}/tool-defined/catA/childA/check-extra.sh"
c_out="$(run_one_to_one_checks "${case_c}/tool-defined" "${case_c}/taxonomy.json" 2>&1)"
c_rc=$?
if [ "$c_rc" -ne 0 ] && printf '%s' "$c_out" | grep -q '宣言外のcheck-\*\.shが同フォルダに存在する'; then
  st_report_pass "宣言の無いcheck-*.shを置くと不合格になる"
else
  st_report_fail "宣言の無いcheck-*.shを置いても不合格にならない"
fi

# (d) 2規約に同じcheckerを宣言する
case_d="${neg_root}/case-d"
st_build_fixture "$case_d"
rm -f "${case_d}/tool-defined/catA/childB/check-b.sh" "${case_d}/tool-defined/catA/childB/check-b.test.sh"
cp "${case_d}/tool-defined/catA/childA/check-a.sh" "${case_d}/tool-defined/catA/childB/check-a.sh"
cp "${case_d}/tool-defined/catA/childA/check-a.test.sh" "${case_d}/tool-defined/catA/childB/check-a.test.sh"
cat > "${case_d}/taxonomy.json" <<'EOF'
{"parents":[{"key":"catA","children":[{"key":"childA","checker":"check-a.sh"},{"key":"childB","checker":"check-a.sh"}]}]}
EOF
d_out="$(run_one_to_one_checks "${case_d}/tool-defined" "${case_d}/taxonomy.json" 2>&1)"
d_rc=$?
if [ "$d_rc" -ne 0 ] && printf '%s' "$d_out" | grep -q '同じcheckerを複数の規約が宣言している'; then
  st_report_pass "2規約に同じcheckerを宣言すると不合格になる"
else
  st_report_fail "2規約に同じcheckerを宣言しても不合格にならない"
fi

rm -rf "$neg_root"
FAIL=$((FAIL + NEG_FAIL))

if [ "$FAIL" -eq 0 ]; then
  echo "PASS"
  exit 0
else
  echo "FAIL（${FAIL}件の不合格）" >&2
  exit 1
fi
