#!/usr/bin/env bash
# check-portal-timeout-margin.sh — build-portal に与えた上限が十分かを見る
#
# 第1層の集約は timeout コマンドを持たない環境向けに、0.2 秒ごとの生存確認で
# 上限を測る。この見張りには誤差があり、名目の上限より実時間のほうが長い
# （実測 2026-08-24: 名目 10 秒 → 実時間 11 秒、名目 30 秒 → 実時間 31 秒）。
#
# build-portal.sh --self-test は 122 秒かかる（実測 2026-08-24・パイプ無し）。
# 既定の上限 120 秒では、実時間の打ち切り点（約 124 秒）まで 2 秒しか余裕が
# 無い。負荷が少し上がれば打ち切られ、検査の内容に問題が無いのに第1層の
# 合否が実行環境の混み具合で変わる。
#
# 集約の上限の宣言（declared_long_running_timeout）へ build-portal が登録され、
# その値が下限（既定 200 秒）以上であることを見る。
#
# 判定の式を指示書の表へ直接書けないためスクリプトへ切り出した。式に含まれる
# 縦棒を片付けの判定器が列の区切りと読み違え、判定行そのものを壊すためである
# （.claude/rules/always/tasks/instruction-format/rule.md の設計判断を参照）。
#
# 使い方:
#   check-portal-timeout-margin.sh            上限が下限以上かを見る
#   check-portal-timeout-margin.sh --min <秒>  下限を変える（既定 200）
#   check-portal-timeout-margin.sh --self-test このスクリプト自身の判定を確かめる
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGGREGATOR="${REPO_ROOT}/generation-engine/scripts/verification/run-layer-machine-checks.sh"
TARGET='generation-engine/scripts/build-portal.sh'

unknown() {
  echo "[UNKNOWN] $1" >&2
  exit 2
}

# 集約の上限の宣言から、対象へ与えた秒数を読む。
# 見つからなければ何も出さずに 1 を返す。
read_declared_timeout() {
  local aggregator="$1" line
  line="$(LC_ALL=C grep -F "${TARGET}) echo " "$aggregator" 2>/dev/null | head -1)" || :
  [ -n "$line" ] || return 1
  printf '%s' "$line" | LC_ALL=C sed -n 's/.*echo[[:space:]]*\([0-9][0-9]*\).*/\1/p'
}

run_check() {
  local min="${1:-200}" aggregator="${2:-$AGGREGATOR}" sec

  [ -f "$aggregator" ] || unknown "集約が見つからないため判定できません 参照したパス: ${aggregator}"

  if ! sec="$(read_declared_timeout "$aggregator")" || [ -z "$sec" ]; then
    echo "[FAIL] ${TARGET} が上限の宣言へ登録されていません（既定の上限が使われ、打ち切りまでの余裕が 2 秒しかありません）"
    return 1
  fi

  if [ "$sec" -lt "$min" ]; then
    echo "[FAIL] 上限が ${sec} 秒で、下限の ${min} 秒に届きません"
    return 1
  fi

  echo "[PASS] ${TARGET} の上限は ${sec} 秒（下限 ${min} 秒以上）"
  return 0
}

run_self_test() {
  local tmp n_pass=0 n_fail=0

  if ! tmp="$(mktemp -d 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため自己テストを判定できません（mktemp -d が一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' EXIT

  assert() {
    local name="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then
      echo "[PASS] ${name}"
      n_pass=$((n_pass + 1))
    else
      echo "[FAIL] ${name}（期待 ${want} / 実際 ${got}）"
      n_fail=$((n_fail + 1))
    fi
  }

  printf '%s\n' "    ${TARGET}) echo 200 ;;" > "$tmp/ok.sh"
  ( run_check 200 "$tmp/ok.sh" >/dev/null 2>&1 )
  assert "下限ちょうどなら合格" 0 $?

  printf '%s\n' "    ${TARGET}) echo 300 ;;" > "$tmp/over.sh"
  ( run_check 200 "$tmp/over.sh" >/dev/null 2>&1 )
  assert "下限を超えれば合格" 0 $?

  printf '%s\n' "    ${TARGET}) echo 150 ;;" > "$tmp/short.sh"
  ( run_check 200 "$tmp/short.sh" >/dev/null 2>&1 )
  assert "下限に届かなければ不合格" 1 $?

  printf '%s\n' "    generation-engine/scripts/other.sh) echo 200 ;;" > "$tmp/absent.sh"
  ( run_check 200 "$tmp/absent.sh" >/dev/null 2>&1 )
  assert "登録が無ければ不合格" 1 $?

  ( run_check 200 "$tmp/no-such-file.sh" >/dev/null 2>&1 )
  assert "集約が無ければ判定不能" 2 $?

  echo "---"
  echo "SELF-TEST SUMMARY: 実行 $((n_pass + n_fail)) 件 合格 ${n_pass} 件 不合格 ${n_fail} 件"
  [ "$n_fail" -eq 0 ] || exit 1
  exit 0
}

MIN=200
while [ $# -gt 0 ]; do
  case "$1" in
    --self-test) run_self_test ;;
    --min) MIN="${2:-200}"; shift 2 ;;
    *) shift ;;
  esac
done
run_check "$MIN"
