#!/usr/bin/env bash
# check-derived-drift-ledger.sh — 生成物のずれ検知台帳(derived-fingerprints.json)を
# 第1層の機械検証から拾えるようにする入口。
#
# 背景: check-derived-drift.sh は台帳とサンプルの突合そのものを担うが、台帳が
# 存在しない・ずれているという状態を第1層の集約(run-layer-machine-checks.sh)へ
# 伝える入口を持たなかった。台帳を作った後も見本を作り直すたびにずれうるため、
# 継続して検知する必要がある。
#
# 判定方法: check-derived-drift.sh status generation-engine/samples を実行し、
# 終了コード0(ずれなし)かどうかだけを見る。判定の中身(何がずれたか)は
# check-derived-drift.sh 自身の出力に譲り、本スクリプトはその合否だけを
# 第1層の集約形式(実行 <N> 件 / 合格 <P> 件 / 不合格 <F> 件)へ変換する。
#
# 使い方:
#   check-derived-drift-ledger.sh --self-test   # 引数なしでも同じ検査を行う
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DRIFT_SCRIPT="$REPO_ROOT/generation-engine/scripts/check-derived-drift.sh"
SAMPLES_ROOT="$REPO_ROOT/generation-engine/samples"

usage() {
  echo "usage: $0 [--self-test]" >&2
  exit 2
}

run_check() {
  local out rc=0
  out="$(bash "$DRIFT_SCRIPT" status "$SAMPLES_ROOT" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "PASS: 台帳(derived-fingerprints.json)と generation-engine/samples が一致"
    echo "実行 1 件 / 合格 1 件 / 不合格 0 件"
    return 0
  fi
  echo "FAIL: 台帳と generation-engine/samples が不一致(終了コード $rc)" >&2
  printf '%s\n' "$out" >&2
  echo "実行 1 件 / 合格 0 件 / 不合格 1 件"
  return 1
}

case "${1:-}" in
  --self-test) run_check; exit $? ;;
  "") run_check; exit $? ;;
  *) usage ;;
esac
