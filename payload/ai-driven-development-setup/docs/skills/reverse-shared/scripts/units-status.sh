#!/usr/bin/env bash
set -u

# units-status.sh — 実行フォルダの単位ごとの工程の状態を読み書きする
# （reverse単位の共有部品）
#
# 目的:
#   一覧を作る・事実を取り出す・基本設計書を書く 等、reverse単位の各機能は
#   単位ごとの工程（事実・基本設計・完了判定・詳細設計）の状態を個別の
#   ファイルにバラバラに記録せず、本スクリプトを介して
#   <実行フォルダ>/logs/units-status.json へ集約する。
#
# 状態を持つファイルの形:
#   {"<種別>":{"<識別子>":{"事実":"済|未|保留","基本設計":"…",
#     "完了判定":"合格|不合格|保留|未","詳細設計":"…"}}}
#   工程は 事実・基本設計・完了判定・詳細設計 の4つに限る。
#   無いキーは「未」とみなす。
#
# 使い方:
#   units-status.sh <実行フォルダ> set <種別> <識別子> <工程> <状態>
#   units-status.sh <実行フォルダ> get <種別> <識別子> <工程>
#   units-status.sh <実行フォルダ> list <工程> <状態>
#   units-status.sh --self-test
#
# 出力（list）: タブ区切り1行1件（種別・識別子）
#
# 終了コード:
#   0 = set・list を実行した、または get が値（既定「未」を含む）を1行出した
#   2 = 使い方の誤り・工程が4つのいずれでもない・jq不在・保存先を作れない
#       （判定不能）
#
# 保守責任者: 人手（ユーザー）。工程の4つの値を増減するときは、本スクリプトと
#   自己テストと、この状態を読み書きする各機能を同時に直す。
#
# 廃棄条件: 単位ごとの進捗管理を別の仕組みに変えた時。
#
# macOS bash 3.2 互換。

VALID_PHASES="事実 基本設計 完了判定 詳細設計"

usage_error() {
  echo "使い方: units-status.sh <実行フォルダ> set <種別> <識別子> <工程> <状態>" >&2
  echo "        units-status.sh <実行フォルダ> get <種別> <識別子> <工程>" >&2
  echo "        units-status.sh <実行フォルダ> list <工程> <状態>" >&2
  echo "        units-status.sh --self-test" >&2
  exit 2
}

is_valid_phase() {
  local p="$1" v
  for v in $VALID_PHASES; do
    [ "$p" = "$v" ] && return 0
  done
  return 1
}

status_file_for() {
  printf '%s/logs/units-status.json' "${1%/}"
}

ensure_store() {
  local run_dir="$1" file
  file="$(status_file_for "$run_dir")"
  mkdir -p "$(dirname "$file")" 2>/dev/null
  if [ ! -d "$(dirname "$file")" ]; then
    return 2
  fi
  if [ ! -f "$file" ]; then
    echo '{}' > "$file"
  fi
  printf '%s' "$file"
}

cmd_set() {
  local run_dir="$1" kind="$2" id="$3" phase="$4" state="$5"
  is_valid_phase "$phase" || { echo "[FAIL] 工程-不正: ${phase}" >&2; return 2; }
  if ! command -v jq > /dev/null 2>&1; then
    echo "[FAIL] jq-不在" >&2
    return 2
  fi
  local file tmp
  file="$(ensure_store "$run_dir")" || { echo "[FAIL] 保存先-作成不能: ${run_dir}" >&2; return 2; }
  tmp="${file}.tmp.$$"
  if jq --arg k "$kind" --arg i "$id" --arg p "$phase" --arg s "$state" \
      '.[$k] = (.[$k] // {}) | .[$k][$i] = (.[$k][$i] // {}) | .[$k][$i][$p] = $s' \
      "$file" > "$tmp"; then
    mv "$tmp" "$file"
    return 0
  fi
  rm -f "$tmp" 2>/dev/null
  echo "[FAIL] 書き込み不能: ${file}" >&2
  return 2
}

cmd_get() {
  local run_dir="$1" kind="$2" id="$3" phase="$4"
  is_valid_phase "$phase" || { echo "[FAIL] 工程-不正: ${phase}" >&2; return 2; }
  if ! command -v jq > /dev/null 2>&1; then
    echo "[FAIL] jq-不在" >&2
    return 2
  fi
  local file
  file="$(status_file_for "$run_dir")"
  if [ ! -f "$file" ]; then
    echo "未"
    return 0
  fi
  jq -r --arg k "$kind" --arg i "$id" --arg p "$phase" \
    '(.[$k][$i][$p]) // "未"' "$file"
  return 0
}

cmd_list() {
  local run_dir="$1" phase="$2" state="$3"
  is_valid_phase "$phase" || { echo "[FAIL] 工程-不正: ${phase}" >&2; return 2; }
  if ! command -v jq > /dev/null 2>&1; then
    echo "[FAIL] jq-不在" >&2
    return 2
  fi
  local file
  file="$(status_file_for "$run_dir")"
  if [ ! -f "$file" ]; then
    return 0
  fi
  jq -r --arg p "$phase" --arg s "$state" '
    to_entries[] as $ke
    | $ke.value
    | to_entries[] as $ue
    | (($ue.value[$p]) // "未") as $st
    | select($st == $s)
    | [$ke.key, $ue.key]
    | @tsv
  ' "$file"
  return 0
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/units-status-self-test.XXXXXX")" || { echo "一時領域を作成できません" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local total=0 fail=0
  local run_dir="${tmp}/run"
  mkdir -p "$run_dir"

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

  assert_rc() {
    local desc="$1" expected="$2"; shift 2
    total=$((total + 1))
    "$@" > /dev/null 2>"${tmp}/err.log"
    local actual=$?
    if [ "$actual" = "$expected" ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（期待終了コード ${expected} / 実際 ${actual}）"
      fail=$((fail + 1))
    fi
  }

  local got0
  got0="$(bash "$0" "$run_dir" get screen "/orders/{id}" 事実)"
  assert_eq "未設定は未" "未" "$got0"

  bash "$0" "$run_dir" set screen "/orders" 事実 済 > /dev/null
  local got1
  got1="$(bash "$0" "$run_dir" get screen "/orders" 事実)"
  assert_eq "set後にgetで同じ値" "済" "$got1"

  local got2
  got2="$(bash "$0" "$run_dir" get screen "/orders" 基本設計)"
  assert_eq "別工程は未のまま" "未" "$got2"

  bash "$0" "$run_dir" set screen "/orders/{id}" 事実 未 > /dev/null
  bash "$0" "$run_dir" set api "/orders" 事実 済 > /dev/null

  local list_out expected_list
  list_out="$(bash "$0" "$run_dir" list 事実 済 | sort)"
  expected_list="$(printf 'api\t/orders\nscreen\t/orders' | sort)"
  assert_eq "listで事実=済の2件" "$expected_list" "$list_out"

  assert_rc "不正な工程はset時終了コード2" 2 bash "$0" "$run_dir" set screen x 不明工程 済
  assert_rc "不正な工程はget時終了コード2" 2 bash "$0" "$run_dir" get screen x 不明工程
  assert_rc "不正な工程はlist時終了コード2" 2 bash "$0" "$run_dir" list 不明工程 済
  assert_rc "引数不足は終了コード2" 2 bash "$0" "$run_dir"

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

run_dir="$1"; shift
sub="$1"; shift

case "$sub" in
  set)
    [ $# -eq 4 ] || usage_error
    cmd_set "$run_dir" "$1" "$2" "$3" "$4"
    exit $?
    ;;
  get)
    [ $# -eq 3 ] || usage_error
    cmd_get "$run_dir" "$1" "$2" "$3"
    exit $?
    ;;
  list)
    [ $# -eq 2 ] || usage_error
    cmd_list "$run_dir" "$1" "$2"
    exit $?
    ;;
  *)
    usage_error
    ;;
esac
