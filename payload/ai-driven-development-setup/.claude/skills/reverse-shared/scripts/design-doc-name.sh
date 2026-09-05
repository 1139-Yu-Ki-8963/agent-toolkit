#!/usr/bin/env bash
set -u

# design-doc-name.sh — 種別ごとの基本設計書・単体テスト設計書のファイル名を返す
#   （reverse単位の共有部品）
#
# 目的:
#   種別ごとの基本設計書・単体テスト設計書のファイル名（旧様式の実名）は、
#   check-basic-design.sh（様式の検査）とrecord-acceptance.sh（合格の記録）の
#   双方が使う。名前の決め方を1箇所へ集め、二重定義によるずれ（合格の記録の
#   文書名が種別ごとの実名と揃わず、記録の同一性の値が空になる不具合）を防ぐ。
#
# 使い方:
#   design-doc-name.sh <種別> <basic|test>
#   design-doc-name.sh --self-test
#
# 種別と区分ごとの値:
#   screen   basic 画面基本設計書.md       test 画面単体テスト設計書.md
#   api      basic API基本設計書.md        test API単体テスト設計書.md
#   table    basic 論理データモデル.md      test テーブル単体テスト設計書.md
#   batch    basic バッチ基本設計書.md      test バッチ単体テスト設計書.md
#   report   basic 帳票基本設計書.md        test 帳票単体テスト設計書.md
#   external basic 外部連携基本設計書.md    test 外部連携単体テスト設計書.md
#   feature  basic 機能設計書.md           test 機能単体テスト設計書.md
#
# 終了コード:
#   0 = 文書名を1行、標準出力へ書いた
#   2 = 使い方の誤り（引数不足・種別が不正・区分がbasic/testでない）
#
# 保守責任者: 人手（ユーザー）。文書名を変えるときは、本スクリプトと自己テストと、
#   本スクリプトを使う各機能（check-basic-design.sh・record-acceptance.sh）を
#   同時に確かめる。
#
# 廃棄条件: 種別ごとの文書名の決め方を構造化データから生成する仕組みに置き換えた時。
#
# macOS bash 3.2 互換。

usage_error() {
  echo "使い方: design-doc-name.sh <種別> <basic|test>" >&2
  echo "        design-doc-name.sh --self-test" >&2
  exit 2
}

design_doc_name() {
  local kind="$1" part="$2"
  case "$part" in
    basic)
      case "$kind" in
        screen) echo "画面基本設計書.md" ;;
        api) echo "API基本設計書.md" ;;
        table) echo "論理データモデル.md" ;;
        batch) echo "バッチ基本設計書.md" ;;
        report) echo "帳票基本設計書.md" ;;
        external) echo "外部連携基本設計書.md" ;;
        feature) echo "機能設計書.md" ;;
        *) echo "" ;;
      esac
      ;;
    test)
      case "$kind" in
        screen) echo "画面単体テスト設計書.md" ;;
        api) echo "API単体テスト設計書.md" ;;
        table) echo "テーブル単体テスト設計書.md" ;;
        batch) echo "バッチ単体テスト設計書.md" ;;
        report) echo "帳票単体テスト設計書.md" ;;
        external) echo "外部連携単体テスト設計書.md" ;;
        feature) echo "機能単体テスト設計書.md" ;;
        *) echo "" ;;
      esac
      ;;
    *) echo "" ;;
  esac
}

run_self_test() {
  local total=0 fail=0

  check() {
    local desc="$1" kind="$2" part="$3" expected="$4" actual
    total=$((total + 1))
    actual="$(design_doc_name "$kind" "$part")"
    if [ "$actual" = "$expected" ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（期待 ${expected} / 実際 ${actual}）"
      fail=$((fail + 1))
    fi
  }

  check "screen-basic" screen basic "画面基本設計書.md"
  check "screen-test" screen test "画面単体テスト設計書.md"
  check "api-basic" api basic "API基本設計書.md"
  check "api-test" api test "API単体テスト設計書.md"
  check "table-basic" table basic "論理データモデル.md"
  check "table-test" table test "テーブル単体テスト設計書.md"
  check "batch-basic" batch basic "バッチ基本設計書.md"
  check "batch-test" batch test "バッチ単体テスト設計書.md"
  check "report-basic" report basic "帳票基本設計書.md"
  check "report-test" report test "帳票単体テスト設計書.md"
  check "external-basic" external basic "外部連携基本設計書.md"
  check "external-test" external test "外部連携単体テスト設計書.md"
  check "feature-basic" feature basic "機能設計書.md"
  check "feature-test" feature test "機能単体テスト設計書.md"

  total=$((total + 1))
  bash "$0" 不正種別 basic > /dev/null 2>"${TMPDIR:-/tmp}/design-doc-name-self-test-1.err"
  local rc_kind=$?
  if [ "$rc_kind" -eq 2 ]; then
    echo "PASS: 不正な種別は終了コード2"
  else
    echo "FAIL: 不正な種別は終了コード2（実際 ${rc_kind}）"
    fail=$((fail + 1))
  fi

  total=$((total + 1))
  bash "$0" screen 不正区分 > /dev/null 2>"${TMPDIR:-/tmp}/design-doc-name-self-test-2.err"
  local rc_part=$?
  if [ "$rc_part" -eq 2 ]; then
    echo "PASS: 不正な区分は終了コード2"
  else
    echo "FAIL: 不正な区分は終了コード2（実際 ${rc_part}）"
    fail=$((fail + 1))
  fi

  total=$((total + 1))
  bash "$0" screen > /dev/null 2>"${TMPDIR:-/tmp}/design-doc-name-self-test-3.err"
  local rc_argc=$?
  if [ "$rc_argc" -eq 2 ]; then
    echo "PASS: 引数不足は終了コード2"
  else
    echo "FAIL: 引数不足は終了コード2（実際 ${rc_argc}）"
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

name="$(design_doc_name "$1" "$2")"
if [ -z "$name" ]; then
  usage_error
fi
printf '%s\n' "$name"
exit 0
