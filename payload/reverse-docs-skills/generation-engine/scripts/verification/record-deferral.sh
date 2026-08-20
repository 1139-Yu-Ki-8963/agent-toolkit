#!/usr/bin/env bash
# record-deferral.sh — 退避を退避の記録の台帳へ追記する
#
# 目的:
#   このリポジトリ自身の退避記録（配布対象外。または同形式の台帳）へ、実行を伴う検証を退避した
#   1件分の記録を追記する。「実行が要る」という理由だけでの退避を許さないため、
#   何をどう試して何がどう失敗したかの記入（--tried・--failed）と、何が変われば
#   再実行できるかの記入（--condition）をすべて必須にする。1つでも欠けたら
#   記録できない。
#
# Usage:
#   record-deferral.sh --ledger <退避記録のパス> --item <退避した項目> \
#     --version <コミットハッシュ> --tried <実行したコマンド> --failed <失敗の内容> \
#     --condition <再実行の条件>
#   record-deferral.sh --self-test
#
# オプション（--self-test 以外はすべて必須。1つでも欠ければ終了コード1）:
#   --ledger <path>     追記先の退避記録ファイル
#   --item <text>       退避した項目の名称
#   --version <hash>    対象のコミットハッシュ。40文字の16進でなければ終了コード1
#   --tried <text>      実際に実行したコマンド
#   --failed <text>     出力の要点
#   --condition <text>  何が変われば試せるようになるか
#   --self-test         自己テストを実行して終了する
#
# 追記する節の形式:
#   ### <退避した項目>
#
#   | 項目 | 内容 |
#   |---|---|
#   | 退避した日時 | <ISO 8601> |
#   | 版 | `<コミットハッシュ全長>` |
#   | 試したこと | <実行したコマンド> |
#   | 失敗の内容 | <出力の要点> |
#   | 再実行の条件 | <何が変われば試せるか> |
#
# 追記の位置: `## 記録` の見出し直後（新しい記録が上に来る）。
#
# 終了コード: 必須引数の欠落は1。版の形式不正は1。--ledger 不在は2。追記成功は0。
#
# 保守責任者: 人手（ユーザー）。台帳の節の形式を変える場合は本ファイルと
#   このリポジトリ自身の退避記録（配布対象外）の「記録の形式」節と self-test を同時に更新する。
# macOS bash 3.2 互換（連想配列は使わない）。
set -uo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"

# ---------------------------------------------------------------------------
# 版の形式検査
# ---------------------------------------------------------------------------

_deferral_version_valid() {
  local v="$1"
  [[ "$v" =~ ^[0-9A-Fa-f]{40}$ ]]
}

# ---------------------------------------------------------------------------
# 節の組み立て
# ---------------------------------------------------------------------------

_deferral_build_block() {
  local item="$1" ts="$2" version="$3" tried="$4" failed="$5" condition="$6"

  printf '### %s\n\n| 項目 | 内容 |\n|---|---|\n| 退避した日時 | %s |\n| 版 | `%s` |\n| 試したこと | %s |\n| 失敗の内容 | %s |\n| 再実行の条件 | %s |\n' \
    "$item" "$ts" "$version" "$tried" "$failed" "$condition"
}

# ---------------------------------------------------------------------------
# `## 記録` の見出し直後へ節を差し込む
# ---------------------------------------------------------------------------

_deferral_insert() {
  local ledger="$1" block="$2"

  if ! grep -q '^## 記録$' "$ledger"; then
    echo "ERROR: 台帳に \`## 記録\` の見出しが見つかりません: ${ledger}" >&2
    return 1
  fi

  local tmp blockfile
  tmp="$(mktemp "${TMPDIR:-/tmp}/record-deferral.XXXXXX")" || return 1
  blockfile="$(mktemp "${TMPDIR:-/tmp}/record-deferral-block.XXXXXX")" || { rm -f "$tmp"; return 1; }
  printf '%s\n' "$block" > "$blockfile"

  # awk -v は値内の改行を扱えない（BSD/macOS awk で "newline in string" エラー）ため、
  # 差し込む節は別ファイルに書き出し、getline で読み込んで挿入する。
  awk -v blockfile="$blockfile" '
    { print }
    /^## 記録$/ && !done {
      print ""
      while ((getline line < blockfile) > 0) print line
      close(blockfile)
      done=1
    }
  ' "$ledger" > "$tmp" || { rm -f "$tmp" "$blockfile"; return 1; }

  rm -f "$blockfile"
  mv "$tmp" "$ledger"
}

# ---------------------------------------------------------------------------
# 退避1件分の記録（CLI・self-test 共通の入口）
# ---------------------------------------------------------------------------

deferral_append() {
  local ledger="$1" item="$2" version="$3" tried="$4" failed="$5" condition="$6"

  if [ -z "$item" ] || [ -z "$version" ] || [ -z "$tried" ] || [ -z "$failed" ] || [ -z "$condition" ]; then
    echo "ERROR: --item・--version・--tried・--failed・--condition はすべて必須です" >&2
    return 1
  fi

  if [ ! -f "$ledger" ]; then
    echo "ERROR: 台帳が見つかりません: ${ledger}" >&2
    return 2
  fi

  if ! _deferral_version_valid "$version"; then
    echo "ERROR: --version は40文字の16進でなければなりません: ${version}" >&2
    return 1
  fi

  local ts block
  ts="$(date +"%Y-%m-%dT%H:%M:%S%z")"
  block="$(_deferral_build_block "$item" "$ts" "$version" "$tried" "$failed" "$condition")"

  _deferral_insert "$ledger" "$block"
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

_deferral_self_test() {
  local run=0 ok=0 ng=0

  _case_pass() { run=$((run+1)); ok=$((ok+1)); echo "[PASS] $1 — $2"; }
  _case_fail() { run=$((run+1)); ng=$((ng+1)); echo "[FAIL] $1 — $2" >&2; }

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/record-deferral-selftest.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT

  local fixture="${tmp}/ledger.md"
  local v1="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  local v2="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  _reset_fixture() {
    cat > "$fixture" <<'EOF'
# リバース検証の退避記録（テスト用）

## 記録

この見出しの下へ、退避が発生するたびに新しい項目を追記する。
EOF
  }

  # --- 必須-試した内容 ---
  _reset_fixture
  local rc
  deferral_append "$fixture" "項目A" "$v1" "" "終了コード1" "修正後" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 1 ]; then
    _case_pass "必須-試した内容" "--tried を省くと終了コード1"
  else
    _case_fail "必須-試した内容" "終了コードが1でない（rc=${rc}）"
  fi

  # --- 必須-失敗の内容 ---
  deferral_append "$fixture" "項目A" "$v1" "bash test.sh" "" "修正後" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 1 ]; then
    _case_pass "必須-失敗の内容" "--failed を省くと終了コード1"
  else
    _case_fail "必須-失敗の内容" "終了コードが1でない（rc=${rc}）"
  fi

  # --- 必須-再実行の条件 ---
  deferral_append "$fixture" "項目A" "$v1" "bash test.sh" "終了コード1" "" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 1 ]; then
    _case_pass "必須-再実行の条件" "--condition を省くと終了コード1"
  else
    _case_fail "必須-再実行の条件" "終了コードが1でない（rc=${rc}）"
  fi

  # --- 版-形式検査 ---
  deferral_append "$fixture" "項目A" "not-a-hash" "bash test.sh" "終了コード1" "修正後" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 1 ]; then
    _case_pass "版-形式検査" "40文字の16進でない版は終了コード1"
  else
    _case_fail "版-形式検査" "終了コードが1でない（rc=${rc}）"
  fi

  # --- 追記-新しい順 ---
  deferral_append "$fixture" "項目1回目" "$v1" "bash test.sh --once" "終了コード1" "test.sh の修正後" >/dev/null
  sleep 1
  deferral_append "$fixture" "項目2回目" "$v2" "bash test.sh --twice" "終了コード2" "test.sh の再修正後" >/dev/null
  local line_v1 line_v2
  line_v1="$(grep -n "\`${v1}\`" "$fixture" | head -1 | cut -d: -f1)"
  line_v2="$(grep -n "\`${v2}\`" "$fixture" | head -1 | cut -d: -f1)"
  if [ -n "$line_v1" ] && [ -n "$line_v2" ] && [ "$line_v2" -lt "$line_v1" ]; then
    _case_pass "追記-新しい順" "2回目に追記した節が1回目より上に来る"
  else
    _case_fail "追記-新しい順" "追記の順序が新しい順でない（v1行=${line_v1} v2行=${line_v2}）"
  fi

  rm -rf "$tmp"
  trap - EXIT

  echo "実行 ${run} 件 / 成功 ${ok} 件 / 失敗 ${ng} 件"
  [ "$ng" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 引数解析・ディスパッチ
# ---------------------------------------------------------------------------

LEDGER=""
ITEM=""
VERSION=""
TRIED=""
FAILED=""
CONDITION=""
SELF_TEST=0

usage() {
  cat <<EOS
Usage: ${SCRIPT_NAME} --ledger <path> --item <text> --version <hash> --tried <text> --failed <text> --condition <text> [--self-test]
EOS
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ledger)
      LEDGER="${2:-}"; shift 2 ;;
    --item)
      ITEM="${2:-}"; shift 2 ;;
    --version)
      VERSION="${2:-}"; shift 2 ;;
    --tried)
      TRIED="${2:-}"; shift 2 ;;
    --failed)
      FAILED="${2:-}"; shift 2 ;;
    --condition)
      CONDITION="${2:-}"; shift 2 ;;
    --self-test)
      SELF_TEST=1; shift ;;
    *)
      echo "ERROR: 未知の引数です: $1" >&2
      exit 2
      ;;
  esac
done

if [ "$SELF_TEST" -eq 1 ]; then
  _deferral_self_test
  exit $?
fi

if [ -z "$LEDGER" ] || [ -z "$ITEM" ] || [ -z "$VERSION" ] || [ -z "$TRIED" ] || [ -z "$FAILED" ] || [ -z "$CONDITION" ]; then
  echo "ERROR: --ledger・--item・--version・--tried・--failed・--condition はすべて必須です" >&2
  usage >&2
  exit 1
fi

deferral_append "$LEDGER" "$ITEM" "$VERSION" "$TRIED" "$FAILED" "$CONDITION"
exit $?
