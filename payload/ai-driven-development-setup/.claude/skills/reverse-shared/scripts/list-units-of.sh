#!/usr/bin/env bash
set -u

# list-units-of.sh — 一覧の元データから種別の単位を1行1件で列挙する
# （reverse単位の共有部品）
#
# 目的:
#   一覧を作る機能が書く docs/design/lists/<種別>.json（一覧の元データ）を、
#   読み取り結果を取り出す・基本設計書を書く 等の後続機能が個別にjqで再パースせず、
#   本スクリプトを介してタブ区切りの1行1件で読む。
#
# 使い方:
#   list-units-of.sh <対象リポジトリのルート> <種別> [--design-root <設計書の置き場>] [--lists <一覧の元データの場所>]
#   list-units-of.sh --self-test
#
# --design-root の既定は <対象リポジトリのルート>。--lists の既定は <設計書の置き場>/docs/design/lists。
#
# 出力（タブ区切り。1行1単位。5列）:
#   識別子 <TAB> 表示名 <TAB> 場所 <TAB> 属するファイル（; 区切り） <TAB> フォルダ名
#
#   表示名は元データjsonの「表示名」項目。null、または空白（半角・全角の
#   空白・タブ・改行・ゼロ幅空白U+200B・BOM U+FEFF）だけなら「業務名」項目、
#   それもnullまたは空白だけなら識別子で埋める。表示名・業務名が数値や配列
#   など文字列でない値のときは、空白判定の前に文字列にする（falseも文字列
#   falseとして非空扱い）。フォルダ名は元データjsonの「フォルダ名」項目。
#   無ければ表示名をunit-dir-name.shで変換した値とする。呼び出し元は
#   unit-dir-name.shを再度呼ばず、本スクリプトの5列目からフォルダ名を得る。
#
# 終了コード:
#   0 = 一覧を読んで出力した（0件でも0）
#   2 = 使い方の誤り・<種別>.json が存在しない・JSONとして読めない・
#       読み取りの途中でjqの処理が失敗した（判定不能）
#
# 保守責任者: 人手（ユーザー）。一覧の元データの形（識別子・表示名・場所・
#   属するファイル・フォルダ名）を変えるときは、list-units.sh と本スクリプトと
#   自己テストを同時に直す。
#
# 廃棄条件: 一覧の元データの読み方を別の仕組みに変えた時。
#
# macOS bash 3.2 互換。

usage_error() {
  echo "使い方: list-units-of.sh <対象リポジトリのルート> <種別> [--design-root <設計書の置き場>] [--lists <一覧の元データの場所>]" >&2
  echo "        list-units-of.sh --self-test" >&2
  exit 2
}

list_units_of() {
  local target="$1" kind="$2" lists="$3"
  local file="${lists%/}/${kind}.json"
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"

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

  local id name place belongs folder
  local tmp_out
  tmp_out="$(mktemp "${TMPDIR:-/tmp}/list-units-of.XXXXXX")" || {
    echo "[FAIL] 一時ファイルを作成できません" >&2
    return 2
  }
  # 中断（SIGINTでのkill等）でも一時ファイルが残らないよう、関数の終了時に
  # 必ず後始末する（run_self_testの流儀に揃える。第1回改善指示書1-29・第3版反証）。
  trap 'rm -f "$tmp_out"' RETURN

  # jqの出力はタブ区切りだが、bashのreadはタブをIFSの空白とみなし連続分を
  # まとめて削る。属するファイル（4列目）が空でフォルダ名（5列目）が非空
  # という並びだと空欄が消えてフォルダ名が前の変数へずれ込むため、タブを
  # 一度\037（IFSの空白扱いされない制御文字）へ置換してから読む。
  # 表示名・業務名が文字列でない値（数値・配列等）でもgsubで落ちないよう、
  # 空白判定の前にtostringで文字列化する（第1回改善指示書1-29・再検証）。
  # 一時ファイルへ書き出す途中経路（jq | tr）でjq自身が失敗した場合も
  # 判定不能として拾えるよう、このパイプラインだけpipefailを効かせる。
  if ! (set -o pipefail; jq -r '
      def to_str: if . == null then null elif type == "string" then . else tostring end;
      def is_blank_str($s): ($s | gsub("[\\s　​﻿]"; "")) == "";
      def norm: to_str as $s | if $s == null then null elif is_blank_str($s) then null else $s end;
      .[] | [
      .["識別子"],
      ((.["表示名"] | norm) // (.["業務名"] | norm) // .["識別子"]),
      .["場所"],
      ((.["属するファイル"] // []) | join(";")),
      (.["フォルダ名"] // "")
    ] | @tsv' "$file" | tr '\t' '\037' > "$tmp_out"); then
    echo "[FAIL] 一覧-形式: ${file} の読み取りに失敗しました" >&2
    return 2
  fi

  while IFS=$'\037' read -r id name place belongs folder; do
    if [ -z "$folder" ]; then
      folder="$(bash "${script_dir}/unit-dir-name.sh" "$name")"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "$place" "$belongs" "$folder"
  done < "$tmp_out"

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
  {"種別":"screen","識別子":"src/pages/OrderList.tsx","表示名":"注文一覧","場所":"src/pages/OrderList.tsx","根拠":"src/pages/OrderList.tsx:1","単位の定義":"","属するファイル":["src/pages/OrderList.tsx","src/api/orders.ts"],"分類軸":[],"フォルダ名":"order-list"},
  {"種別":"screen","識別子":"src/pages/OrderDetail.tsx","表示名":"注文 一覧2","場所":"src/pages/OrderDetail.tsx","根拠":"src/pages/OrderDetail.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"src/pages/Empty.tsx","表示名":"空一覧","場所":"src/pages/Empty.tsx","根拠":"src/pages/Empty.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[],"フォルダ名":"custom-folder"}
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
  expected="$(printf 'src/pages/OrderList.tsx\t注文一覧\tsrc/pages/OrderList.tsx\tsrc/pages/OrderList.tsx;src/api/orders.ts\torder-list\nsrc/pages/OrderDetail.tsx\t注文 一覧2\tsrc/pages/OrderDetail.tsx\t\t注文_一覧2\nsrc/pages/Empty.tsx\t空一覧\tsrc/pages/Empty.tsx\t\tcustom-folder')"
  assert_eq "一覧読取-フォルダ名列: 5列をタブ区切りで出す" "$expected" "$out"

  local empty_belongs_line
  empty_belongs_line="$(printf '%s\n' "$out" | grep '^src/pages/Empty.tsx' )"
  assert_eq "一覧読取-空列直後の非空列: 属するファイルが空でもフォルダ名がずれない" "$(printf 'src/pages/Empty.tsx\t空一覧\tsrc/pages/Empty.tsx\t\tcustom-folder')" "$empty_belongs_line"

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

  # 有効なJSONだが要素が期待する形でなく、読み取り中にjqの処理自体が
  # 実行時エラーになる経路（第1回改善指示書1-29・第3版反証）。
  echo '{"属するファイル":123}' > "${target}/docs/design/lists/broken.json"
  total=$((total + 1))
  bash "$0" "$target" broken > "${tmp}/out-broken.log" 2>"${tmp}/err-broken.log"
  local rc_runtime=$?
  if [ "$rc_runtime" -eq 2 ] && grep -q '読み取りに失敗' "${tmp}/err-broken.log" && [ ! -s "${tmp}/out-broken.log" ]; then
    echo "PASS: 一覧読取-実行時エラー: 有効なJSONでもjqの実行時エラーは終了コード2で標準出力が空"
  else
    echo "FAIL: 一覧読取-実行時エラー: 有効なJSONでもjqの実行時エラーは終了コード2で標準出力が空（実際: ${rc_runtime}）"
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

  cat > "${target}/docs/design/lists/message.json" << 'FIXEOF'
[
  {"種別":"message","識別子":"unit-a","表示名":"","業務名":"","場所":"","属するファイル":[]},
  {"種別":"message","識別子":"unit-b","表示名":"","業務名":"経理連携","場所":"","属するファイル":[]},
  {"種別":"message","識別子":"unit-c","場所":"","属するファイル":[]},
  {"種別":"message","識別子":"unit-d","表示名":" ","業務名":"","場所":"","属するファイル":[]},
  {"種別":"message","識別子":"unit-e","表示名":"\t","業務名":"","場所":"","属するファイル":[]},
  {"種別":"message","識別子":"unit-f","表示名":123,"業務名":"","場所":"","属するファイル":[]},
  {"種別":"message","識別子":"unit-g","表示名":"​","業務名":"﻿","場所":"","属するファイル":[]},
  {"種別":"message","識別子":"unit-h","表示名":["a","b"],"業務名":"","場所":"","属するファイル":[]}
]
FIXEOF

  local name_a name_b name_c name_d name_e
  name_a="$(bash "$0" "$target" message | awk -F'\t' '$1=="unit-a"{print $2}')"
  assert_eq "表示名-空文字列の既定: 表示名・業務名とも空文字列なら識別子" "unit-a" "$name_a"

  name_b="$(bash "$0" "$target" message | awk -F'\t' '$1=="unit-b"{print $2}')"
  assert_eq "表示名-空文字列の既定: 表示名が空で業務名があれば業務名" "経理連携" "$name_b"

  name_c="$(bash "$0" "$target" message | awk -F'\t' '$1=="unit-c"{print $2}')"
  assert_eq "表示名-空文字列の既定: 表示名・業務名とも鍵が無ければ識別子" "unit-c" "$name_c"

  name_d="$(bash "$0" "$target" message | awk -F'\t' '$1=="unit-d"{print $2}')"
  assert_eq "表示名-空白のみの既定: 空白だけの表示名は識別子" "unit-d" "$name_d"

  name_e="$(bash "$0" "$target" message | awk -F'\t' '$1=="unit-e"{print $2}')"
  assert_eq "表示名-空白のみの既定: タブだけの表示名は識別子" "unit-e" "$name_e"

  local name_f name_g name_h out_f rc_f out_h rc_h
  # 数値・配列の表示名は終了コード0のまま出力されることも合わせて検査する
  # （第1回改善指示書1-29・第3版反証。値だけでなく終了コードも見る）。
  out_f="$(bash "$0" "$target" message)"; rc_f=$?
  name_f="$(printf '%s\n' "$out_f" | awk -F'\t' '$1=="unit-f"{print $2}')"
  assert_eq "表示名-文字列以外の既定: 数値の表示名はそのまま文字列にする" "123|0" "${name_f}|${rc_f}"

  name_g="$(bash "$0" "$target" message | awk -F'\t' '$1=="unit-g"{print $2}')"
  assert_eq "表示名-不可視文字のみの既定: ゼロ幅空白・BOMだけなら識別子" "unit-g" "$name_g"

  out_h="$(bash "$0" "$target" message)"; rc_h=$?
  name_h="$(printf '%s\n' "$out_h" | awk -F'\t' '$1=="unit-h"{print $2}')"
  assert_eq "表示名-文字列以外の既定: 配列の表示名は文字列化される" '["a","b"]|0' "${name_h}|${rc_h}"

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
design_root="$target"
lists=""

while [ $# -gt 0 ]; do
  case "$1" in
    --lists) lists="$2"; shift 2 ;;
    --design-root) design_root="$2"; shift 2 ;;
    *) usage_error ;;
  esac
done

[ -n "$lists" ] || lists="${design_root%/}/docs/design/lists"

list_units_of "$target" "$kind" "$lists"
exit $?
