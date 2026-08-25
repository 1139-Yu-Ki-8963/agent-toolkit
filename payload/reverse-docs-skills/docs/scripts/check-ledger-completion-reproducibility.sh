#!/usr/bin/env bash
# 指摘改善一覧の「完了」が、検証側で再現できる証拠を状態行に持つか集計する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_LEDGER="$REPO_ROOT/docs/tasks/指摘改善一覧.md"
SELF_TEST_TMPDIR=""

cleanup_self_test() {
  if [ -n "$SELF_TEST_TMPDIR" ] && [ -d "$SELF_TEST_TMPDIR" ]; then
    rm -rf -- "$SELF_TEST_TMPDIR"
  fi
}

usage() {
  echo "使い方: $0 [--strict] [台帳パス]"
  echo "        $0 --self-test"
}

analyze_ledger() {
  local ledger="$1"
  local strict="$2"

  if [ ! -f "$ledger" ]; then
    echo "ERROR: 台帳が見つかりません: $ledger" >&2
    return 2
  fi

  awk -v strict="$strict" '
    function flush_heading(    has_command, has_reason) {
      if (issue_key == "" || state !~ /^\*\*状態\*\*: 完了/) return

      completed++
      has_command = state ~ /確かめたコマンド[：:][[:space:]]*`[^`[:space:]][^`]*`/ \
        || state ~ /`(bash|node|jq|grep|rg|find|awk|sh|python|python3|npx|npm|ruby|go|make|cmake|LC_ALL=)[[:space:]][^`]+`/ \
        || state ~ /`\.\/[^`[:space:]]+[^`]*`/
      has_reason = state ~ /機械で確かめられない理由[：:][[:space:]]*[^）[:space:]]/

      if (has_command) {
        with_command++
      } else {
        without_command++
      }

      if (has_reason) with_reason++
      if (!has_command && !has_reason) {
        invalid++
        invalid_keys = invalid_keys (invalid_keys == "" ? "" : " ") issue_key
      }
    }

    /^### [^.]+\./ {
      flush_heading()
      issue_key = $0
      sub(/^### /, "", issue_key)
      sub(/\..*/, "", issue_key)
      state = ""
      next
    }

    /^\*\*状態\*\*:/ { state = $0 }

    END {
      flush_heading()
      printf "完了: %d件\n", completed
      printf "コマンドあり: %d件\n", with_command
      printf "コマンドなし: %d件\n", without_command
      printf "機械で確かめられない理由あり: %d件\n", with_reason
      printf "不合格: %d件\n", invalid
      if (strict && invalid > 0) {
        printf "[FAIL] コマンドも理由もない完了: %s\n", invalid_keys
        exit 1
      }
    }
  ' "$ledger"
}

run_self_test() {
  local fixture output rc failures
  failures=0
  SELF_TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/check-ledger-completion-reproducibility.XXXXXX")" || {
    echo "[UNKNOWN] 一時領域を作成できません 操作: mktemp -d / 想定原因: TMPDIRの権限または空き容量不足" >&2
    return 2
  }
  trap cleanup_self_test EXIT HUP INT TERM
  fixture="$SELF_TEST_TMPDIR/ledger.md"

  printf '%s\n' \
    '### 1-1. コマンドを持つ完了' \
    '**検収方法**: 1. 自己テストが合格すること' \
    '**状態**: 完了（検収1: 満たす。確かめたコマンド: `perl -v`）' \
    '### 1-2. コマンドを持たない完了' \
    '**検収方法**: 1. 自己テストが合格すること' \
    '**状態**: 完了（検収1: 満たす）' \
    '### 1-3. 理由を持つ完了' \
    '**検収方法**: 1. 文脈上適切であること' \
    '**状態**: 完了（検収1: 満たす。機械で確かめられない理由: 読み手による文脈判断が必要なため）' \
    > "$fixture"

  output="$(analyze_ledger "$fixture" 0)"
  rc=$?
  if [ "$rc" -eq 0 ] \
    && printf '%s\n' "$output" | grep -qF '完了: 3件' \
    && printf '%s\n' "$output" | grep -qF 'コマンドあり: 1件'; then
    echo "PASS: コマンドを持つ完了を検出する"
  else
    echo "FAIL: コマンドを持つ完了の分類結果が期待値と異なる"
    printf '%s\n' "$output"
    failures=$((failures + 1))
  fi

  if [ "$rc" -eq 0 ] \
    && printf '%s\n' "$output" | grep -qF 'コマンドなし: 2件' \
    && printf '%s\n' "$output" | grep -qF '不合格: 1件'; then
    echo "PASS: コマンドも理由も持たない完了を検出する"
  else
    echo "FAIL: コマンドも理由も持たない完了の分類結果が期待値と異なる"
    printf '%s\n' "$output"
    failures=$((failures + 1))
  fi

  if [ "$rc" -eq 0 ] && printf '%s\n' "$output" | grep -qF '機械で確かめられない理由あり: 1件'; then
    echo "PASS: 機械で確かめられない理由を持つ完了を検出する"
  else
    echo "FAIL: 機械で確かめられない理由を持つ完了の分類結果が期待値と異なる"
    printf '%s\n' "$output"
    failures=$((failures + 1))
  fi

  output="$(analyze_ledger "$fixture" 1)"
  rc=$?
  if [ "$rc" -eq 1 ] && printf '%s\n' "$output" | grep -qF '[FAIL] コマンドも理由もない完了: 1-2'; then
    echo "PASS: --strict はコマンドも理由もない完了を不合格にする"
  else
    echo "FAIL: --strict の終了コードまたは不合格見出しが期待値と異なる"
    printf '%s\n' "$output"
    failures=$((failures + 1))
  fi

  if [ "$failures" -eq 0 ]; then
    echo "SELF-TEST: 4 PASS, 0 FAIL"
    return 0
  fi
  echo "SELF-TEST: $((4 - failures)) PASS, ${failures} FAIL"
  return 1
}

strict=0
ledger="$DEFAULT_LEDGER"

case "${1:-}" in
  --self-test)
    run_self_test
    exit $?
    ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --strict)
      strict=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      echo "ERROR: 未知の引数です: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      ledger="$1"
      ;;
  esac
  shift
done

analyze_ledger "$ledger" "$strict"
