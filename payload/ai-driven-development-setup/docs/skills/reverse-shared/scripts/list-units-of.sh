#!/usr/bin/env bash
set -u

# list-units-of.sh — 一覧の元データから種別の単位を1行1件で列挙する
# （reverse単位の共有部品）
#
# 目的:
#   一覧を作る機能が書く docs/design/lists/<種別>.json（一覧の元データ）を、
#   事実を取り出す・基本設計書を書く 等の後続機能が個別にjqで再パースせず、
#   本スクリプトを介してタブ区切りの1行1件で読む。
#
# 使い方:
#   list-units-of.sh <対象リポジトリのルート> <種別> [--lists <一覧の元データの場所>]
#   list-units-of.sh --self-test
#
# --lists の既定は <対象リポジトリのルート>/docs/design/lists。
#
# 出力（タブ区切り。1行1単位）:
#   識別子 <TAB> 名前 <TAB> 場所 <TAB> 属するファイル（; 区切り）
#
# 終了コード:
#   0 = 一覧を読んで出力した（0件でも0）
#   2 = 使い方の誤り・<種別>.json が存在しない・JSONとして読めない（判定不能）
#
# 保守責任者: 人手（ユーザー）。一覧の元データの形（識別子・名前・場所・
#   属するファイル）を変えるときは、list-units.sh と本スクリプトと
#   自己テストを同時に直す。
#
# 廃棄条件: 一覧の元データの読み方を別の仕組みに変えた時。
#
# macOS bash 3.2 互換。

usage_error() {
  echo "使い方: list-units-of.sh <対象リポジトリのルート> <種別> [--lists <一覧の元データの場所>]" >&2
  echo "        list-units-of.sh --self-test" >&2
  exit 2
}

list_units_of() {
  local target="$1" kind="$2" lists="$3"
  local file="${lists%/}/${kind}.json"

  if [ ! -f "$file" ]; then
    echo "[FAIL] 一覧-不在: ${file} が存在しません" >&2
    return 2
  fi
  if ! command -v jq > /dev/null 2>&1; then
    echo "[FAIL] jq-不在" >&2
    return 2
  fi
  if ! jq -e . "$file" > /dev/null 2>&1; then
    echo "[FAIL] 一覧-形式: ${file} がJSONとして読めません" >&2
    return 2
  fi

  jq -r '.[] | [.["識別子"], .["名前"], .["場所"], ((.["属するファイル"] // []) | join(";"))] | @tsv' "$file"
  return 0
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/list-units-of-self-test.XXXXXX")" || { echo "一時領域を作成できません" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local total=0 fail=0
  local target="${tmp}/target"
  mkdir -p "${target}/docs/design/lists"
  cat > "${target}/docs/design/lists/screen.json" << 'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/OrderList.tsx","名前":"OrderList","場所":"src/pages/OrderList.tsx","根拠":"src/pages/OrderList.tsx:1","単位の定義":"","属するファイル":["src/pages/OrderList.tsx","src/api/orders.ts"],"分類軸":[]},
  {"種別":"screen","識別子":"src/pages/OrderDetail.tsx","名前":"OrderDetail","場所":"src/pages/OrderDetail.tsx","根拠":"src/pages/OrderDetail.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF

  assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    total=$((total + 1))
    if [ "$actual" = "$expected" ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（期待 [${expected}] / 実際 [${actual}]）"
      fail=$((fail + 1))
    fi
  }

  local out expected
  out="$(bash "$0" "$target" screen)"
  expected="$(printf 'src/pages/OrderList.tsx\tOrderList\tsrc/pages/OrderList.tsx\tsrc/pages/OrderList.tsx;src/api/orders.ts\nsrc/pages/OrderDetail.tsx\tOrderDetail\tsrc/pages/OrderDetail.tsx\t')"
  assert_eq "2件をタブ区切りで出す" "$expected" "$out"

  total=$((total + 1))
  bash "$0" "$target" api > /dev/null 2>"${tmp}/err.log"
  local rc_missing=$?
  if [ "$rc_missing" -eq 2 ] && grep -q '一覧-不在' "${tmp}/err.log"; then
    echo "PASS: 一覧が無ければ終了コード2"
  else
    echo "FAIL: 一覧が無ければ終了コード2（実際: ${rc_missing}）"
    fail=$((fail + 1))
  fi

  echo '不正なJSON' > "${target}/docs/design/lists/table.json"
  total=$((total + 1))
  bash "$0" "$target" table > /dev/null 2>"${tmp}/err.log"
  local rc_invalid=$?
  if [ "$rc_invalid" -eq 2 ]; then
    echo "PASS: 不正なJSONは終了コード2"
  else
    echo "FAIL: 不正なJSONは終了コード2（実際: ${rc_invalid}）"
    fail=$((fail + 1))
  fi

  total=$((total + 1))
  bash "$0" "$target" screen --lists "${target}/docs/design/lists" > "${tmp}/out2.log" 2>&1
  local rc_lists_opt=$?
  if [ "$rc_lists_opt" -eq 0 ]; then
    echo "PASS: --listsオプション指定でも動く"
  else
    echo "FAIL: --listsオプション指定でも動く（実際: ${rc_lists_opt}）"
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

target="$1"; shift
kind="$1"; shift
lists="${target%/}/docs/design/lists"

while [ $# -gt 0 ]; do
  case "$1" in
    --lists) lists="$2"; shift 2 ;;
    *) usage_error ;;
  esac
done

list_units_of "$target" "$kind" "$lists"
exit $?
