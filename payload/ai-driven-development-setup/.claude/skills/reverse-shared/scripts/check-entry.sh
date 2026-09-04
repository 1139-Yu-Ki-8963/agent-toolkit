#!/usr/bin/env bash
set -u

# check-entry.sh — 範囲の承認を確かめる（reverse単位の共有部品）
#
# 目的:
#   一覧を作る機能などreverse単位の第二フェーズ以降の各機能は、調査と検出条件の定義書を描く
#   機能の範囲の承認（confirmations/対象範囲の承認.md）が可であり、承認時の
#   調査と検出条件の定義書と現在の調査と検出条件の定義書が同一であることを確かめてから走査を始める。この確認を
#   個別の機能が再実装せず、本スクリプトへ委ねる。
#
# 前提とする対象範囲の承認.mdの行形式（reverse-writing-survey-definition 手順6が書く）:
#   可否: 可                 （または 否）
#   調査と検出条件の定義書: <調査と検出条件の定義書.mdの shasum -a 256 の値>
#
# 使い方:
#   check-entry.sh <実行フォルダ> <対象リポジトリのルート>
#   check-entry.sh --self-test
#
# 終了コード:
#   0 = 可否が可、かつ調査と検出条件の定義書の同一性の値が一致
#   1 = 可否が可でない、または同一性の値が不一致・不在
#   2 = 使い方の誤り・承認ファイル不在・調査と検出条件の定義書ファイル不在（判定不能）
#
# 保守責任者: 人手（ユーザー）。対象範囲の承認.mdの行形式を変えるときは、
#   reverse-writing-survey-definition SKILL.mdの手順6と本スクリプトと自己テストを同時に直す。
#
# 廃棄条件: 範囲の承認の確認方法を別の仕組みに変えた時。
#
# macOS bash 3.2 互換。

usage_error() {
  echo "使い方: check-entry.sh <実行フォルダ> <対象リポジトリのルート> [--design-root <設計書の置き場>]" >&2
  echo "        check-entry.sh --self-test" >&2
  exit 2
}

check_entry() {
  local run_dir="$1" target="$2" design_root="$3"
  [ -n "$design_root" ] || design_root="$target"
  local approval="${run_dir%/}/confirmations/対象範囲の承認.md"
  local map="${design_root%/}/docs/design/common/調査と検出条件の定義書.md"

  if [ ! -f "$approval" ]; then
    echo "[FAIL] 承認-不在: ${approval} が存在しません" >&2
    return 2
  fi
  if [ ! -f "$map" ]; then
    echo "[FAIL] 調査と検出条件の定義書-不在: ${map} が存在しません" >&2
    return 2
  fi

  local kahi
  kahi="$(grep -E '^可否:[[:space:]]*' "$approval" | head -n1 | sed -E 's/^可否:[[:space:]]*//')"
  if [ "$kahi" != "可" ]; then
    echo "[FAIL] 可否-不可: 可否が「可」ではありません（実際: ${kahi:-空}）" >&2
    return 1
  fi

  local recorded_hash
  recorded_hash="$(grep -E '^調査と検出条件の定義書:[[:space:]]*' "$approval" | head -n1 | sed -E 's/^調査と検出条件の定義書:[[:space:]]*//')"
  if [ -z "$recorded_hash" ]; then
    echo "[FAIL] 同一性-不在: 承認の記録に調査と検出条件の定義書の同一性の値がありません" >&2
    return 1
  fi

  local current_hash
  current_hash="$(shasum -a 256 "$map" | awk '{print $1}')"
  if [ "$recorded_hash" != "$current_hash" ]; then
    echo "[FAIL] 同一性-不一致: 承認時の調査と検出条件の定義書と現在の調査と検出条件の定義書が一致しません" >&2
    return 1
  fi

  echo "合格: 承認済み・調査と検出条件の定義書は同一"
  return 0
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-entry-self-test.XXXXXX")" || { echo "一時領域を作成できません" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local total=0 fail=0

  local target="${tmp}/target"
  mkdir -p "${target}/docs/design/common"
  echo "# 調査と検出条件の定義書" > "${target}/docs/design/common/調査と検出条件の定義書.md"
  local hash
  hash="$(shasum -a 256 "${target}/docs/design/common/調査と検出条件の定義書.md" | awk '{print $1}')"
  local wrong_hash
  wrong_hash="$(printf '0%.0s' $(seq 1 64))"

  assert_exit() {
    local desc="$1" expected="$2"; shift 2
    total=$((total + 1))
    "$@" > "${tmp}/out.log" 2>"${tmp}/err.log"
    local actual=$?
    if [ "$actual" = "$expected" ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（期待終了コード ${expected} / 実際 ${actual}）"
      sed -n '1,10p' "${tmp}/err.log"
      fail=$((fail + 1))
    fi
  }

  # 合格
  local run_ok="${tmp}/run-ok"
  mkdir -p "${run_ok}/confirmations"
  cat > "${run_ok}/confirmations/対象範囲の承認.md" << EOF2
可否: 可
否の理由: なし
日時: 2026-09-03T10:00:00+09:00
対象のコミット: abc1234
調査と検出条件の定義書: ${hash}
EOF2
  assert_exit "合格" 0 bash "$0" "$run_ok" "$target"

  # 不合格-否
  local run_no="${tmp}/run-no"
  mkdir -p "${run_no}/confirmations"
  cat > "${run_no}/confirmations/対象範囲の承認.md" << EOF2
可否: 否
否の理由: 範囲を見直すため
調査と検出条件の定義書: ${hash}
EOF2
  assert_exit "不合格-否" 1 bash "$0" "$run_no" "$target"

  # 不合格-同一性不一致
  local run_mismatch="${tmp}/run-mismatch"
  mkdir -p "${run_mismatch}/confirmations"
  cat > "${run_mismatch}/confirmations/対象範囲の承認.md" << EOF2
可否: 可
調査と検出条件の定義書: ${wrong_hash}
EOF2
  assert_exit "不合格-同一性不一致" 1 bash "$0" "$run_mismatch" "$target"

  # 判定不能-承認ファイル不在
  local run_missing="${tmp}/run-missing"
  mkdir -p "${run_missing}"
  assert_exit "判定不能-承認ファイル不在" 2 bash "$0" "$run_missing" "$target"

  # 判定不能-調査と検出条件の定義書ファイル不在
  local target_missing="${tmp}/target-missing"
  mkdir -p "${target_missing}"
  assert_exit "判定不能-調査と検出条件の定義書ファイル不在" 2 bash "$0" "$run_ok" "$target_missing"

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

run_dir_arg="$1"; target_arg="$2"; shift 2
design_root_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --design-root) design_root_arg="$2"; shift 2 ;;
    *) usage_error ;;
  esac
done

check_entry "$run_dir_arg" "$target_arg" "$design_root_arg"
exit $?
