#!/usr/bin/env bash
set -u

# design-root.sh — 実行フォルダのrun.jsonから「設計書の置き場」を1行読む
# （reverse単位の共有部品）
#
# 目的:
#   調査と検出条件の定義書を描く・一覧を作る・読み取り結果を取り出す等、reverse単位の各機能が設計書
#   （調査と検出条件の定義書・要件定義書・共通設計文書・一覧・基本設計書など）を書く場所は、
#   先方リポジトリへ展開する使い方（run.jsonの「設計書の置き場」= 先方の
#   ルート）と、作業場所だけに置く使い方（同キー = <実行フォルダ>/design）
#   の2通りがある。各機能はrun.jsonを個別に読まず、本スクリプトを介して
#   設計書の置き場を1行読む。
#
# 使い方:
#   design-root.sh <実行フォルダ>
#   design-root.sh --self-test
#
# 後方互換:
#   run.jsonに「設計書の置き場」キーが無い場合は「対象リポジトリ」の値を
#   出す（旧run.json形式との互換）。
#
# 終了コード:
#   0 = 設計書の置き場を1行、標準出力へ書いた
#   2 = 使い方の誤り・run.json不在・JSONとして読めない・
#       「設計書の置き場」も「対象リポジトリ」も無い（判定不能）
#
# 保守責任者: 人手（ユーザー）。run.jsonのキーを変えるときは、
#   start-run.shと本スクリプトと自己テストを同時に直す。
#
# 廃棄条件: 設計書の置き場を渡す方式を別の仕組みに変えた時。
#
# macOS bash 3.2 互換。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage_error() {
  echo "使い方: design-root.sh <実行フォルダ>" >&2
  echo "        design-root.sh --self-test" >&2
  exit 2
}

design_root() {
  local run_dir="$1"
  local run_json="${run_dir%/}/run.json"

  if [ ! -f "$run_json" ]; then
    echo "[FAIL] run-不在: ${run_json} が存在しません" >&2
    return 2
  fi

  local out
  out="$(bash "${SCRIPT_DIR}/read-run.sh" "$run_dir" "設計書の置き場" 2>/dev/null)"
  if [ -n "$out" ]; then
    echo "$out"
    return 0
  fi

  out="$(bash "${SCRIPT_DIR}/read-run.sh" "$run_dir" "対象リポジトリ" 2>/dev/null)"
  if [ -n "$out" ]; then
    echo "$out"
    return 0
  fi

  echo "[FAIL] キー-不在: 設計書の置き場・対象リポジトリのいずれも ${run_json} にありません" >&2
  return 2
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/design-root-self-test.XXXXXX")" || { echo "一時領域を作成できません" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local total=0 fail=0

  check_value() {
    local desc="$1" run_dir="$2" expected="$3"
    total=$((total + 1))
    local actual rc
    actual="$(bash "$0" "$run_dir" 2>"${tmp}/err.log")"
    rc=$?
    if [ "$rc" -eq 0 ] && [ "$actual" = "$expected" ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（実際: rc=${rc} 値=${actual}）"
      fail=$((fail + 1))
    fi
  }

  local run_deploy="${tmp}/run-deploy"
  mkdir -p "$run_deploy"
  cat > "${run_deploy}/run.json" << 'JSONEOF'
{
  "対象リポジトリ": "/path/to/target",
  "設計書の置き場": "/path/to/target"
}
JSONEOF
  check_value "設計書の置き場キーがあればその値" "$run_deploy" "/path/to/target"

  local run_legacy="${tmp}/run-legacy"
  mkdir -p "$run_legacy"
  cat > "${run_legacy}/run.json" << 'JSONEOF'
{
  "対象リポジトリ": "/path/to/target-legacy"
}
JSONEOF
  check_value "設計書の置き場キーが無ければ対象リポジトリで後方互換" "$run_legacy" "/path/to/target-legacy"

  local run_workspace="${tmp}/run-workspace"
  mkdir -p "$run_workspace"
  cat > "${run_workspace}/run.json" << 'JSONEOF'
{
  "対象リポジトリ": "/path/to/target",
  "設計書の置き場": "/path/to/run-workspace/design"
}
JSONEOF
  check_value "作業場所だけの使い方は実行フォルダ配下のdesignを出す" "$run_workspace" "/path/to/run-workspace/design"

  total=$((total + 1))
  bash "$0" "${tmp}/no-such-dir" > /dev/null 2>"${tmp}/err.log"
  local rc_missing=$?
  if [ "$rc_missing" -eq 2 ] && grep -q 'run-不在' "${tmp}/err.log"; then
    echo "PASS: run.json不在は終了コード2"
  else
    echo "FAIL: run.json不在は終了コード2（実際: ${rc_missing}）"
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

if [ $# -lt 1 ]; then
  usage_error
fi

design_root "$1"
exit $?
