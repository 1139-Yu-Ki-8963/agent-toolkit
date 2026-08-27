#!/bin/bash
# 第1層の集約（run-layer-machine-checks.sh）についての2つの判定を行う。
#
#   --declared-zero  宣言済み長時間として登録された検査が0本であることを見る
#   --success-min    集約の成功本数が下限（既定144本）を下回らないことを見る
#
# どちらも終了コード0なら満たす、0以外なら満たさない。
#
# 実装判断: この2つの判定はどちらもコマンドの中に縦棒を含む。判定を指示書の
#   表へ直接書くと、その縦棒を片付けの判定器（docs/scripts/judge-task-done.sh）が
#   列の区切りと読み違え、コマンドの切り出しに失敗する。2026-08-24、同種の判定が
#   手で実行すると終了コード0なのに「実測で満たさない」と記録される事象を確認した。
#   式をこのファイルへ移し、表からはファイル名だけを呼ぶ形にして縦棒を取り除く。
#   先例: docs/scripts/check-broken-verdict-rows.sh
#
# 実装判断: --success-min は集約を実際に走らせる。1回に10分規模かかるため、
#   呼び出し側は時間の上限を長めに取る必要がある。集約の終了コードは使わず、
#   出力の集計行から成功本数を読む。集約は失敗が1本でもあれば1を返すため、
#   終了コードで「成功本数が下限以上か」を判定できない。
#
# 実装判断: grep の実行へ LC_ALL=C を明示する。ここで見るのは半角の
#   パターン（generation-engine/scripts/... と 成功 <数> 本）であり、
#   多バイト文字の正規表現を使わない。完全一致に近い走査のため C ロケールが正しい
#   （実装判断記録規約の「ロケールの使い分け」節の既定1）。

set -u

AGGREGATOR="generation-engine/scripts/verification/run-layer-machine-checks.sh"

check_declared_zero() {
  local n
  n="$(LC_ALL=C awk '/^declared_long_running_known\(\)/,/^}/' "$AGGREGATOR" 2>/dev/null \
    | LC_ALL=C grep -cE '^[[:space:]]+generation-engine/scripts/.*\.sh\)' || true)"
  n="$(printf '%s' "$n" | head -1 | tr -d '[:space:]')"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -eq 0 ]; then
    echo "[PASS] 宣言済み長時間=0本"
    return 0
  fi
  echo "[FAIL] 宣言済み長時間=${n}本" >&2
  return 1
}

check_success_min() {
  local min="${1:-144}" output n
  output="$(bash "$AGGREGATOR" 2>&1 || :)"
  n="$(printf '%s\n' "$output" | LC_ALL=C sed -n 's/.*成功 \([0-9][0-9]*\) 本.*/\1/p' | head -1)"
  if [ -z "$n" ]; then
    echo "[UNKNOWN] 集約の出力から成功本数を読めないため判定できません 操作: sed / 想定原因: 集計行の書式が変わった、または集約が集計行を出す前に終了した" >&2
    return 2
  fi
  if [ "$n" -ge "$min" ]; then
    printf '[PASS] 成功=%s本（下限%s本）\n' "$n" "$min"
    return 0
  fi
  printf '[FAIL] 成功=%s本（下限%s本）\n' "$n" "$min" >&2
  return 1
}

run_self_test() {
  local rc=0 pass=0 fail=0
  if check_declared_zero >/dev/null 2>&1; then
    echo "  [PASS] 宣言済み長時間の判定が動く"; pass=$((pass + 1))
  else
    echo "  [FAIL] 宣言済み長時間の判定が動く" >&2; fail=$((fail + 1)); rc=1
  fi

  # 集約を走らせずに、成功本数の読み取りだけを試す
  local sample n
  sample='対象 182 本 / 成功 177 本 / 失敗 2 本 / 判定不能 2 本'
  n="$(printf '%s\n' "$sample" | LC_ALL=C sed -n 's/.*成功 \([0-9][0-9]*\) 本.*/\1/p' | head -1)"
  if [ "$n" = "177" ]; then
    echo "  [PASS] 集計行から成功本数を読める"; pass=$((pass + 1))
  else
    echo "  [FAIL] 集計行から成功本数を読める（読めた値=${n}）" >&2; fail=$((fail + 1)); rc=1
  fi

  sample='集計行がない出力'
  n="$(printf '%s\n' "$sample" | LC_ALL=C sed -n 's/.*成功 \([0-9][0-9]*\) 本.*/\1/p' | head -1)"
  if [ -z "$n" ]; then
    echo "  [PASS] 集計行が無ければ空を返す"; pass=$((pass + 1))
  else
    echo "  [FAIL] 集計行が無ければ空を返す" >&2; fail=$((fail + 1)); rc=1
  fi

  printf '実行 %d 件 / 成功 %d 件 / 失敗 %d 件\n' "$((pass + fail))" "$pass" "$fail"
  return "$rc"
}

case "${1:-}" in
  --declared-zero) check_declared_zero ;;
  --success-min) shift; check_success_min "${1:-144}" ;;
  --self-test) run_self_test ;;
  *)
    echo "usage: check-layer1-declarations.sh --declared-zero | --success-min [下限] | --self-test" >&2
    exit 2
    ;;
esac
