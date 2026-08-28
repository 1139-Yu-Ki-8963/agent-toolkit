#!/usr/bin/env bash
# 配布先（agent-toolkit/payload/reverse-docs-skills）で第1層の集約を実行し、
# 失敗が0本であることを確かめる。公開のたびに実行する。
#
# なぜ要るか: 正本で242本すべて成功しても、配布先では落ちることがある。
#   実測（2026-08-27）で、正本は242本すべて成功する一方、配布先では6本落ちていた。
#   原因は3つだった。公開対象から外したスクリプトを無条件に呼ぶもの1本、
#   配布物の境界を越えて外側のリポジトリのルートを掴むもの2本、依存の不在3本である。
#   検証する側は配布先を見る。正本だけで確かめて合格と報告すると、指摘が解消しない。
#
# 判定不能（終了コード2）は不合格として数えない。依存の不在は実行環境の制約であり、
#   成果物の欠陥ではない（.claude/rules/always/verification/indeterminate-result/rule.md）。
#
# ただし判定不能を放置しない。配布先に依存が無いために判定不能のまま残る検査が
#   2種類あった。ブラウザを使う検査2本と、用語管理の検査3本である。
#   実測（2026-08-28）で、前者は正本の node_modules を NODE_PATH で、
#   後者は正本の Python の実行系を GLOSSARY_PYTHON で参照させるだけで、
#   どちらも合格することを確かめた。後者は91件の検査が通った。
#   配布先へ依存を置くと版管理へ混入するため、置かずに参照だけを渡す。
#   参照先が無い場合は従来どおり判定不能のまま進む。
#
# 実装判断（判定不能・打ち切りの内訳を、失敗の判定より前に出す理由）:
#   旧実装は失敗があると `exit 1` で抜けていた。判定不能・打ち切りの内訳を出す
#   処理はその後ろにあったため、失敗と判定不能が同時に出た場合に判定不能の内訳が
#   1本も出ないまま終了していた（2026-08-28 実測。失敗2本・判定不能16本のとき、
#   判定不能の内訳が0本出力された。あわせてログも rm -f で消えており、
#   後から中身を確かめる手段が無かった）。判定不能規約
#   （.claude/rules/always/verification/indeterminate-result/rule.md）の
#   「判定不能を放置しない」節は、判定不能・未確認・SKIPのラベルが残っている限り
#   その裏に欠陥があるかどうか分からないと定める。内訳が見えなければこの確認自体が
#   できない。このため emit_report は判定不能→打ち切り→失敗の順に内訳を出し、
#   失敗判定で return する前に他の内訳をすべて出し終える構成にした。
#
# 実装判断（列挙の上限を超えたら告知する理由）:
#   [FAIL]・[UNKNOWN] の列挙は既定で10件までしか出さない。実測（2026-08-28）で
#   判定不能16本のうち6本が head -10 の外側に隠れていた。件数を絞ったまま
#   その旨を出さないのは no silent caps の考え方
#   （.claude/rules/scoped/portal/page-conventions/rule.md）に反するため、
#   上限を超えたら「他に N 本あります」を出す。
#
# 使い方:
#   bash docs/scripts/check-payload-layer1.sh
#   PAYLOAD_DIR=<配布先> bash docs/scripts/check-payload-layer1.sh
#   PAYLOAD_LAYER1_KEEP_LOG=1 bash docs/scripts/check-payload-layer1.sh   # ログを残す
#   bash docs/scripts/check-payload-layer1.sh --self-test
set -uo pipefail

CAP=10

# 内訳を上限付きで出す。上限を超えたら黙って切り捨てず「他に N 本あります」と出す
# （no silent caps。.claude/rules/scoped/portal/page-conventions/rule.md の考え方）。
emit_capped() {
  local label="$1" hits="$2"
  [ -z "$hits" ] && return 0
  local n
  n="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
  if [ "$n" -gt "$CAP" ]; then
    printf '%s\n' "$hits" | head -"$CAP"
    echo "[INFO] 他に $((n - CAP)) 本あります（${label}）。"
  else
    printf '%s\n' "$hits"
  fi
}

# 集計行と本文ログから判定を出す。戻り値は 0=合格 / 1=不合格 / 2=判定不能。
# 判定不能・打ち切りの内訳を、失敗の判定より前に出す（理由は冒頭コメント参照）。
emit_report() {
  local log="$1" summary="$2"
  local fails unknowns aborted

  fails="$(printf '%s' "$summary" | sed -n 's/.*失敗 \([0-9]*\) 本.*/\1/p')"
  if [ -z "$fails" ]; then
    echo "[UNKNOWN] 集約の集計行を読めないため判定できません"
    return 2
  fi

  unknowns="$(printf '%s' "$summary" | sed -n 's/.*判定不能 \([0-9]*\) 本.*/\1/p')"
  if [ -n "$unknowns" ] && [ "$unknowns" -ne 0 ]; then
    echo "[INFO] 判定不能が $unknowns 本あります。不合格ではありませんが、測れていません。"
    emit_capped "判定不能" "$(grep -E '^\[UNKNOWN\]' "$log")"
  fi

  # 打ち切りは時間の上限を超えて止められたものである。合否が付いていない点は
  # 判定不能と同じであり、放置すると測れていないことに気付けない。
  aborted="$(printf '%s' "$summary" | sed -n 's/.*打ち切り \([0-9]*\) 本.*/\1/p')"
  if [ -n "$aborted" ] && [ "$aborted" -ne 0 ]; then
    echo "[INFO] 打ち切りが $aborted 本あります。時間の上限を超えたため、合否が付いていません。"
    emit_capped "打ち切り" "$(grep -E '打ち切' "$log" | grep -vE '^対象 ')"
  fi

  if [ "$fails" -ne 0 ]; then
    echo "[FAIL] 配布先で $fails 本が失敗しています。正本では通っても配布先では落ちる形の欠陥です。"
    emit_capped "失敗" "$(grep -E '^\[FAIL\]' "$log")"
    return 1
  fi

  echo "[PASS] 配布先で失敗0本です。"
  return 0
}

run_check() {
  local payload_dir agg log
  payload_dir="${PAYLOAD_DIR:-$HOME/github-public/agent-toolkit/payload/reverse-docs-skills}"

  if [ ! -d "$payload_dir" ]; then
    echo "[UNKNOWN] 配布先が見つからないため判定できません（$payload_dir が存在しない。同期が未実行の可能性があります）"
    return 2
  fi

  agg="$payload_dir/generation-engine/scripts/verification/run-layer-machine-checks.sh"
  if [ ! -f "$agg" ]; then
    echo "[UNKNOWN] 配布先に集約スクリプトが無いため判定できません（${agg}）"
    return 2
  fi

  if ! log="$(mktemp "${TMPDIR:-/tmp}/payload-l1.XXXXXX" 2>/dev/null)" || [ -z "$log" ]; then
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした）"
    return 2
  fi

  # 配布先に依存が無くても測れるよう、正本の依存を参照させる。
  # 参照先が無ければ何も渡さず、従来どおり判定不能のまま進む。
  #
  # Node.js の依存はブラウザを使う検査2本が要る。
  # Python の隔離環境は用語管理の検査3本が要る。実測（2026-08-28）で、
  # GLOSSARY_PYTHON へ正本の実行系を渡すだけで91件の検査が合格した。
  # どちらも配布先へ置くと版管理へ混入するため、置かずに参照だけを渡す。
  local deps py
  deps="${PAYLOAD_LAYER1_NODE_PATH:-$HOME/Projects/reverse-docs-skills/node_modules}"
  py="${PAYLOAD_LAYER1_GLOSSARY_PYTHON:-$HOME/Projects/reverse-docs-skills/generation-engine/scripts/glossary/.venv/bin/python}"

  local -a envs=()
  if [ -d "$deps" ]; then
    envs+=("NODE_PATH=$deps")
  else
    echo "[INFO] Node.js の依存の参照先が無いため、ブラウザを使う検査は判定不能のまま進みます（${deps}）"
  fi
  if [ -x "$py" ]; then
    envs+=("GLOSSARY_PYTHON=$py")
  else
    echo "[INFO] Python の実行系の参照先が無いため、用語管理の検査は判定不能のまま進みます（${py}）"
  fi

  if [ "${#envs[@]}" -gt 0 ]; then
    ( cd "$payload_dir" && env "${envs[@]}" bash "$agg" ) > "$log" 2>&1
  else
    ( cd "$payload_dir" && bash "$agg" ) > "$log" 2>&1
  fi

  local summary
  summary="$(tail -1 "$log")"
  echo "$summary"

  emit_report "$log" "$summary"
  local rc=$?

  # ログを残す口。既定では消すが、内訳を後から確かめたいときは残す。
  if [ -n "${PAYLOAD_LAYER1_KEEP_LOG:-}" ]; then
    echo "[INFO] ログを残します（${log}）"
  else
    rm -f "$log"
  fi

  return "$rc"
}

self_test() {
  local pass=0 fail=0 tmp

  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/payload-l1-selftest.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時領域を作れないため判定できません（mktempが書き込めませんでした）"
    exit 2
  fi

  # ケース1: 失敗あり・判定不能あり（2026-08-28 実測の再現）。
  # 実データと同じ並び（本文が先、集計行が最後）にする。
  local log1="$tmp/case1.log"
  {
    echo "[FAIL] generation-engine/scripts/build-portal.sh — 実行 62 件 / 終了コード 1"
    echo "[FAIL] generation-engine/scripts/tests/check-photo-findings-29.test.sh — 実行 30 件 / 終了コード 1"
    for i in $(seq 1 16); do
      echo "[UNKNOWN] generation-engine/scripts/tests/dummy-${i}.sh — 判定不能（依存不在）"
    done
    echo "対象 262 本 / 成功 244 本 / 失敗 2 本 / 判定不能 16 本 / 途中停止の疑い 0 本 / 打ち切り 0 本 / 宣言済み長時間 0 本 / 総ケース数 6076 件"
  } > "$log1"

  local summary1 out1 rc1
  summary1="$(tail -1 "$log1")"
  out1="$(emit_report "$log1" "$summary1")"
  rc1=$?

  if [ "$rc1" -eq 1 ]; then
    echo "  [PASS] ケース1: 失敗ありは戻り値1"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース1: 戻り値が1でない（${rc1}）"; fail=$((fail + 1))
  fi

  if printf '%s\n' "$out1" | grep -q '^\[INFO\] 判定不能が 16 本あります'; then
    echo "  [PASS] ケース1: 失敗ありでも判定不能の内訳が出る（旧不具合の再発防止）"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース1: 判定不能の内訳が出ない（旧不具合の再発）"; fail=$((fail + 1))
  fi

  if printf '%s\n' "$out1" | grep -q '^\[FAIL\] 配布先で 2 本が失敗しています'; then
    echo "  [PASS] ケース1: 失敗の内訳も出る"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース1: 失敗の内訳が出ない"; fail=$((fail + 1))
  fi

  # 上限（10件）超過の告知が出ることを確かめる（16件のUNKNOWNのうち6件超過）。
  if printf '%s\n' "$out1" | grep -q '他に 6 本あります（判定不能）'; then
    echo "  [PASS] ケース1: 上限超過が黙って切り捨てられず告知される"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース1: 上限超過の告知が出ない"; fail=$((fail + 1))
  fi

  # ケース2: 失敗0本・判定不能あり。判定不能の内訳が出て、合格（戻り値0）になる。
  local log2="$tmp/case2.log"
  {
    for i in $(seq 1 3); do
      echo "[UNKNOWN] generation-engine/scripts/tests/dummy-${i}.sh — 判定不能（依存不在）"
    done
    echo "対象 262 本 / 成功 259 本 / 失敗 0 本 / 判定不能 3 本 / 途中停止の疑い 0 本 / 打ち切り 0 本 / 宣言済み長時間 0 本 / 総ケース数 6076 件"
  } > "$log2"
  local summary2 out2 rc2
  summary2="$(tail -1 "$log2")"
  out2="$(emit_report "$log2" "$summary2")"
  rc2=$?

  if [ "$rc2" -eq 0 ]; then
    echo "  [PASS] ケース2: 失敗0本は戻り値0"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース2: 戻り値が0でない（${rc2}）"; fail=$((fail + 1))
  fi

  if printf '%s\n' "$out2" | grep -q '^\[INFO\] 判定不能が 3 本あります'; then
    echo "  [PASS] ケース2: 判定不能の内訳が出る"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース2: 判定不能の内訳が出ない"; fail=$((fail + 1))
  fi

  if printf '%s\n' "$out2" | grep -q '^\[PASS\] 配布先で失敗0本です'; then
    echo "  [PASS] ケース2: 合格の表示が出る"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース2: 合格の表示が出ない"; fail=$((fail + 1))
  fi

  # ケース3: 失敗0本・判定不能0本。内訳を出さずに合格する。
  local log3="$tmp/case3.log"
  echo "対象 262 本 / 成功 262 本 / 失敗 0 本 / 判定不能 0 本 / 途中停止の疑い 0 本 / 打ち切り 0 本 / 宣言済み長時間 0 本 / 総ケース数 6076 件" > "$log3"
  local summary3 out3 rc3
  summary3="$(tail -1 "$log3")"
  out3="$(emit_report "$log3" "$summary3")"
  rc3=$?
  if [ "$rc3" -eq 0 ] && ! printf '%s\n' "$out3" | grep -q '判定不能が'; then
    echo "  [PASS] ケース3: 判定不能0本のときは内訳を出さない"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース3: 判定不能0本なのに内訳が出る、または戻り値が0でない"; fail=$((fail + 1))
  fi

  # ケース4: 集計行を読めない。判定不能（戻り値2）として扱う。
  local log4="$tmp/case4.log"
  echo "壊れた出力" > "$log4"
  local summary4 rc4
  summary4="$(tail -1 "$log4")"
  emit_report "$log4" "$summary4" >/dev/null 2>&1
  rc4=$?
  if [ "$rc4" -eq 2 ]; then
    echo "  [PASS] ケース4: 集計行を読めないとき判定不能（戻り値2）"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース4: 戻り値が2でない（${rc4}）"; fail=$((fail + 1))
  fi

  rm -rf "$tmp"
  echo "self-test: ${pass} PASS, ${fail} FAIL"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  *) run_check ;;
esac
