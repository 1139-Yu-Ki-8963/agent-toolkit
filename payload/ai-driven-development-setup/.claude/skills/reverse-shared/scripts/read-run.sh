#!/usr/bin/env bash
set -u

# read-run.sh — 実行フォルダの run.json から値を1つ読む（reverse単位の共有部品）
#
# 目的:
#   統括の実行の開始スクリプトが作る実行フォルダの run.json は、対象リポジトリ・
#   対象プロジェクト名・出力の置き場・実行の識別子・対象のコミットの値を持つ。reverse
#   単位の各機能（調査と検出条件の定義書を描く・一覧を作る等）はこの値を個別に再パースせず、
#   本スクリプトを介して読む。
#
# 使い方:
#   read-run.sh <実行フォルダ> <キー>
#   read-run.sh --self-test
#
# キーの例: 対象リポジトリ / 対象プロジェクト名 / 出力の置き場 / 実行の識別子 / 対象のコミット
# （run.json に実在するキーであれば上記に限らず読める）
#
# 終了コード:
#   0 = 値を1行、標準出力へ書いた
#   2 = 使い方の誤り・run.json不在・JSONとして読めない・キー不在（判定不能）
#
# 保守責任者: 人手（ユーザー）。run.jsonのキーを変えるときは、統括の実行の
#   開始スクリプトと本スクリプトと自己テストを同時に直す。
#
# 廃棄条件: 実行フォルダの前提値を渡す方式を別の仕組みに変えた時。
#
# macOS bash 3.2 互換。

usage_error() {
  echo "使い方: read-run.sh <実行フォルダ> <キー>" >&2
  echo "        read-run.sh --self-test" >&2
  exit 2
}

read_run() {
  local run_dir="$1" key="$2"
  local run_json="${run_dir%/}/run.json"

  if [ ! -f "$run_json" ]; then
    echo "[FAIL] run-不在: ${run_json} が存在しません" >&2
    return 2
  fi
  if ! command -v jq > /dev/null 2>&1; then
    echo "[FAIL] jq-不在: jq が使えません" >&2
    return 2
  fi
  if ! jq -e . "$run_json" > /dev/null 2>&1; then
    echo "[FAIL] run-形式: ${run_json} がJSONとして読めません" >&2
    return 2
  fi

  local has
  has="$(jq --arg k "$key" 'has($k)' "$run_json")"
  if [ "$has" != "true" ]; then
    echo "[FAIL] キー-不在: ${key} が ${run_json} にありません" >&2
    return 2
  fi

  jq -r --arg k "$key" '.[$k]' "$run_json"
  return 0
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/read-run-self-test.XXXXXX")" || { echo "一時領域を作成できません" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local total=0 fail=0
  local run_dir="${tmp}/run"
  mkdir -p "$run_dir"
  cat > "${run_dir}/run.json" << 'RUNEOF'
{
  "対象リポジトリ": "/path/to/target",
  "対象プロジェクト名": "サンプル対象プロジェクト",
  "出力の置き場": "/path/to/ai-output",
  "実行の識別子": "2026-09-03-abc1234",
  "対象のコミット": "abc1234def"
}
RUNEOF

  check_value() {
    local desc="$1" key="$2" expected="$3"
    total=$((total + 1))
    local actual rc
    actual="$(bash "$0" "$run_dir" "$key" 2>"${tmp}/err.log")"
    rc=$?
    if [ "$rc" -eq 0 ] && [ "$actual" = "$expected" ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（実際: rc=${rc} 値=${actual}）"
      fail=$((fail + 1))
    fi
  }

  check_value "対象リポジトリ" "対象リポジトリ" "/path/to/target"
  check_value "対象プロジェクト名" "対象プロジェクト名" "サンプル対象プロジェクト"
  check_value "出力の置き場" "出力の置き場" "/path/to/ai-output"
  check_value "実行の識別子" "実行の識別子" "2026-09-03-abc1234"
  check_value "対象のコミット" "対象のコミット" "abc1234def"

  total=$((total + 1))
  bash "$0" "$run_dir" "存在しないキー" > /dev/null 2>"${tmp}/err.log"
  local rc_missing=$?
  if [ "$rc_missing" -eq 2 ] && grep -q 'キー-不在' "${tmp}/err.log"; then
    echo "PASS: キー不在は終了コード2"
  else
    echo "FAIL: キー不在は終了コード2（実際: ${rc_missing}）"
    fail=$((fail + 1))
  fi

  total=$((total + 1))
  bash "$0" "${tmp}/no-such-dir" "対象リポジトリ" > /dev/null 2>"${tmp}/err.log"
  local rc_nofile=$?
  if [ "$rc_nofile" -eq 2 ] && grep -q 'run-不在' "${tmp}/err.log"; then
    echo "PASS: run.json不在は終了コード2"
  else
    echo "FAIL: run.json不在は終了コード2（実際: ${rc_nofile}）"
    fail=$((fail + 1))
  fi

  total=$((total + 1))
  bash "$0" "$run_dir" > /dev/null 2>"${tmp}/err.log"
  local rc_usage=$?
  if [ "$rc_usage" -eq 2 ]; then
    echo "PASS: 引数不足は終了コード2"
  else
    echo "FAIL: 引数不足は終了コード2（実際: ${rc_usage}）"
    fail=$((fail + 1))
  fi

  echo "実行 ${total} 件 / 失敗 ${fail} 件"
  if [ "$fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

if [ $# -lt 2 ]; then
  usage_error
fi

read_run "$1" "$2"
exit $?
