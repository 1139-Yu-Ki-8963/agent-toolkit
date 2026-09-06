#!/usr/bin/env bash
set -u

# unit-dir-name.sh — 表示名から単位のフォルダ名を作る（reverse単位の共有部品）
#
# 目的:
#   一覧化（工程2-1）の完了時の処理「業務名の確定」が組んだ表示名は、
#   フォルダ名に使えない文字を含みうる。本スクリプトはその置換規則を
#   単位のフォルダ名の唯一の定義として持つ。呼び出し元は工程2-1の
#   業務名の確定だけであり、確定した値は一覧の元データjsonの「フォルダ名」
#   フィールドへ書く。後続の各機能（一覧を作る・読み取り結果を取り出す・
#   基本設計書を書く 等）は本スクリプトを再度呼ばず、list-units-of.shの
#   出力（5列目）からフォルダ名を得る。
#
# 置換規則:
#   表示名に含まれる / （スラッシュ）・空白・{ ・} ・: ・\ ・? ・* ・"
#   （二重引用符）・< ・> ・| （パイプ）をすべて _ （アンダースコア）へ
#   置換し、先頭の _ を除いたものをフォルダ名とする。全角括弧（（）等）は
#   置換対象に含まない。
#
# 使い方:
#   unit-dir-name.sh <表示名>
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
  echo "使い方: unit-dir-name.sh <表示名>" >&2
  echo "        unit-dir-name.sh --self-test" >&2
  exit 2
}

unit_dir_name() {
  local name="$1" out
  out="$name"
  out="${out//\//_}"
  out="${out//\{/_}"
  out="${out//\}/_}"
  out="${out//:/_}"
  out="${out//\\/_}"
  out="${out//\?/_}"
  out="${out//\*/_}"
  out="${out//\"/_}"
  out="${out//</_}"
  out="${out//>/_}"
  out="${out//|/_}"
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

  check "フォルダ名-表示名変換" "注文詳細取得API" "注文詳細取得API"
  check "フォルダ名-空白置換" "注文 一覧" "注文_一覧"
  check "フォルダ名-先頭記号除去" "/注文" "注文"
  check "フォルダ名-波括弧置換" "注文（/orders/{id}）" "注文（_orders__id_）"
  check "記号12種のうち二重引用符・山括弧・パイプを置換" 'a:b?c*d"e<f>g|h' "a_b_c_d_e_f_g_h"
  check "バックスラッシュを置換" 'a\b' "a_b"

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
