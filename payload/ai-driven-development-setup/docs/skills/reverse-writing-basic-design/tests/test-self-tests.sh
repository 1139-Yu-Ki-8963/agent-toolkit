#!/usr/bin/env bash
set -u

# test-self-tests.sh — check-basic-design.sh --self-test を実行し、合否を報告する。
# set -e は使わない。失敗しても最後まで実行し、失敗本数を数えるためである。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/../scripts"

FAIL=0
TOTAL=0

run_one() {
  local name="$1" path="$2"
  TOTAL=$((TOTAL + 1))
  local out="${TMPDIR:-/tmp}/test-self-tests-out.$$"
  if bash "$path" --self-test > "$out" 2>&1; then
    echo "PASS: ${name} --self-test"
  else
    local code=$?
    echo "FAIL: ${name} --self-test (終了コード ${code})"
    sed -n '1,60p' "$out"
    FAIL=$((FAIL + 1))
  fi
  rm -f "$out"
}

run_one "check-basic-design.sh" "${SCRIPTS_DIR}/check-basic-design.sh"

# basic-phase-viewpoints.md が挙げる scripts/...sh・../reverse-shared/scripts/...sh の
# パスが、機能のフォルダ（reverse-writing-basic-design/）を起点に実在するかを検査する
# （第1回改善指示書1-21）。パスの起点はこの参照自身の置き場（references/）ではない。
check_reference_paths() {
  local ref="$1" func_dir="$2"
  local rel path fail=0 total=0
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    total=$((total + 1))
    path="${func_dir}/${rel}"
    [ -f "$path" ] || fail=$((fail + 1))
  done < <(grep -oE '(\.\./reverse-shared/scripts/[a-zA-Z_-]+\.sh( --[a-z]+)?|scripts/[a-zA-Z_-]+\.sh)' "$ref" \
    | awk '{print $1}' | sort -u)
  echo "${fail} ${total}"
}

run_reference_path_checks() {
  local ref="${SCRIPT_DIR}/../references/basic-phase-viewpoints.md"
  local func_dir
  func_dir="$(cd "${SCRIPT_DIR}/.." && pwd)"

  local result fail total
  result="$(check_reference_paths "$ref" "$func_dir")"
  fail="$(echo "$result" | awk '{print $1}')"
  total="$(echo "$result" | awk '{print $2}')"
  TOTAL=$((TOTAL + 1))
  if [ "$fail" -eq 0 ] && [ "$total" -gt 0 ]; then
    echo "PASS: basic-phase-viewpoints.mdの参照パスが機能のフォルダから全て実在する"
    echo "  (対象 ${total}件)"
  else
    echo "FAIL: basic-phase-viewpoints.mdの参照パスに不在がある（不在${fail}/${total}件）"
    FAIL=$((FAIL + 1))
  fi

  # 負例: 存在しないパスへ書き換えた一時複製で、検査が実際に不在を検出することを確かめる
  local tmp_ref
  tmp_ref="$(mktemp "${TMPDIR:-/tmp}/basic-phase-viewpoints-XXXXXX.md")"
  sed 's/check-basic-design\.sh/check-basic-design-nonexistent.sh/' "$ref" > "$tmp_ref"
  result="$(check_reference_paths "$tmp_ref" "$func_dir")"
  fail="$(echo "$result" | awk '{print $1}')"
  rm -f "$tmp_ref"
  TOTAL=$((TOTAL + 1))
  if [ "$fail" -gt 0 ]; then
    echo "PASS: 存在しないパスへ書き換えると検査が不在を検出する（負例）"
  else
    echo "FAIL: 存在しないパスへ書き換えても検査が不在を検出しない（負例）"
    FAIL=$((FAIL + 1))
  fi
}

run_reference_path_checks

check_extract_body_h1_parity() {
  local basic_script="${SCRIPTS_DIR}/check-basic-design.sh"
  local detail_script="${SCRIPT_DIR}/../../reverse-writing-detail-design/scripts/check-detail-design.sh"
  TOTAL=$((TOTAL + 1))
  local basic_out="${TMPDIR:-/tmp}/test-self-tests-basic-body.$$"
  local detail_out="${TMPDIR:-/tmp}/test-self-tests-detail-body.$$"
  sed -n '/^extract_body_h1()/,/^}$/p' "$basic_script" > "$basic_out"
  sed -n '/^extract_body_h1()/,/^}$/p' "$detail_script" > "$detail_out"
  if [ "$(tail -n 1 "$basic_out")" != "}" ] || [ "$(tail -n 1 "$detail_out")" != "}" ]; then
    echo "FAIL: extract_body_h1-同一性（関数の終端（\`}\`だけの行）が見つかりません）"
    FAIL=$((FAIL + 1))
  elif [ "$(wc -l < "$basic_out")" -lt 3 ] || [ "$(wc -l < "$detail_out")" -lt 3 ]; then
    echo "FAIL: extract_body_h1-同一性（片方または両方の関数定義が見つかりません）"
    FAIL=$((FAIL + 1))
  elif diff "$basic_out" "$detail_out" > /dev/null 2>&1; then
    echo "PASS: extract_body_h1-同一性"
  else
    echo "FAIL: extract_body_h1-同一性（check-basic-design.shとcheck-detail-design.shの関数本体が一致しません）"
    FAIL=$((FAIL + 1))
  fi
  rm -f "$basic_out" "$detail_out"
}

check_extract_body_h1_parity

echo "実行 ${TOTAL} 件 / 失敗 ${FAIL} 件"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
