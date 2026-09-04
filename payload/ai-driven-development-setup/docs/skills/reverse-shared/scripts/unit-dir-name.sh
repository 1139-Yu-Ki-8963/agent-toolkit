#!/usr/bin/env bash
set -u

# unit-dir-name.sh — 識別子から単位のフォルダ名を作る（reverse単位の共有部品）
#
# 目的:
#   一覧の元データが持つ識別子（ファイルパス・経路・テーブル名など）は
#   フォルダ名に使えない文字を含みうる。本スクリプトはその置換規則を
#   単位のフォルダ名の唯一の定義として持ち、reverse単位の各機能（一覧を
#   作る・読み取り結果を取り出す・基本設計書を書く 等）が個別に置換規則を
#   再実装しない。
#
# 置換規則:
#   識別子に含まれる / （スラッシュ）・空白・{ ・} ・: ・\ ・? ・* を
#   すべて _ （アンダースコア）へ置換し、先頭の _ を除いたものをフォルダ名
#   とする。
#
# 使い方:
#   unit-dir-name.sh <識別子>
#   unit-dir-name.sh --self-test
#
# 終了コード:
#   0 = フォルダ名を1行、標準出力へ書いた
#   2 = 使い方の誤り（引数無し）
#
# 保守責任者: 人手（ユーザー）。置換対象の文字を変えるときは、本スクリプトと
#   自己テストと、この規則を使う各機能（一覧を作る・読み取り結果を取り出す 等）を
#   同時に確かめる。
#
# 廃棄条件: 単位のフォルダ名の決め方を別の仕組みに変えた時。
#
# macOS bash 3.2 互換。

usage_error() {
  echo "使い方: unit-dir-name.sh <識別子>" >&2
  echo "        unit-dir-name.sh --self-test" >&2
  exit 2
}

unit_dir_name() {
  local id="$1" out
  out="$id"
  out="${out//\//_}"
  out="${out//\{/_}"
  out="${out//\}/_}"
  out="${out//:/_}"
  out="${out//\\/_}"
  out="${out//\?/_}"
  out="${out//\*/_}"
  out="${out// /_}"
  while [ "${out#_}" != "$out" ]; do
    out="${out#_}"
  done
  printf '%s' "$out"
}

run_self_test() {
  local total=0 fail=0

  check() {
    local desc="$1" input="$2" expected="$3" actual
    total=$((total + 1))
    actual="$(unit_dir_name "$input")"
    if [ "$actual" = "$expected" ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（期待 ${expected} / 実際 ${actual}）"
      fail=$((fail + 1))
    fi
  }

  check "スラッシュと波括弧を含む経路" "/orders/{id}" "orders__id_"
  check "空白を含む識別子" "src/pages/Order List.tsx" "src_pages_Order_List.tsx"
  check "先頭のアンダースコアを除く" "/orders" "orders"
  check "コロン・疑問符・アスタリスクを置換" 'a:b?c*d' "a_b_c_d"
  check "バックスラッシュを置換" 'a\b' "a_b"
  check "置換対象が無い識別子はそのまま" "orders" "orders"

  total=$((total + 1))
  bash "$0" > /dev/null 2>"${TMPDIR:-/tmp}/unit-dir-name-self-test.err"
  local rc_usage=$?
  if [ "$rc_usage" -eq 2 ]; then
    echo "PASS: 引数無しは終了コード2"
  else
    echo "FAIL: 引数無しは終了コード2（実際 ${rc_usage}）"
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

unit_dir_name "$1"
printf '\n'
exit 0
