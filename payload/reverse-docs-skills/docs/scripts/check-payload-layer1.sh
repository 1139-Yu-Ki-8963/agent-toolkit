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
# 自己テストを持たない。この道具は配布先の集約を実行するだけであり、
#   偽の集約を用意して確かめると、その用意そのものが本物と食い違う。
#   実際の配布先で走らせた結果だけを判定に使う。
#
# 使い方:
#   bash docs/scripts/check-payload-layer1.sh
#   PAYLOAD_DIR=<配布先> bash docs/scripts/check-payload-layer1.sh
set -uo pipefail

PAYLOAD_DIR="${PAYLOAD_DIR:-$HOME/github-public/agent-toolkit/payload/reverse-docs-skills}"

if [ ! -d "$PAYLOAD_DIR" ]; then
  echo "[UNKNOWN] 配布先が見つからないため判定できません（$PAYLOAD_DIR が存在しない。同期が未実行の可能性があります）"
  exit 2
fi

AGG="$PAYLOAD_DIR/generation-engine/scripts/verification/run-layer-machine-checks.sh"
if [ ! -f "$AGG" ]; then
  echo "[UNKNOWN] 配布先に集約スクリプトが無いため判定できません（${AGG}）"
  exit 2
fi

if ! LOG="$(mktemp "${TMPDIR:-/tmp}/payload-l1.XXXXXX" 2>/dev/null)" || [ -z "$LOG" ]; then
  echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした）"
  exit 2
fi

# 配布先に依存が無くても測れるよう、正本の依存を参照させる。
# 参照先が無ければ何も渡さず、従来どおり判定不能のまま進む。
#
# Node.js の依存はブラウザを使う検査2本が要る。
# Python の隔離環境は用語管理の検査3本が要る。実測（2026-08-28）で、
# GLOSSARY_PYTHON へ正本の実行系を渡すだけで91件の検査が合格した。
# どちらも配布先へ置くと版管理へ混入するため、置かずに参照だけを渡す。
DEPS="${PAYLOAD_LAYER1_NODE_PATH:-$HOME/Projects/reverse-docs-skills/node_modules}"
PY="${PAYLOAD_LAYER1_GLOSSARY_PYTHON:-$HOME/Projects/reverse-docs-skills/generation-engine/scripts/glossary/.venv/bin/python}"

declare -a ENVS=()
if [ -d "$DEPS" ]; then
  ENVS+=("NODE_PATH=$DEPS")
else
  echo "[INFO] Node.js の依存の参照先が無いため、ブラウザを使う検査は判定不能のまま進みます（${DEPS}）"
fi
if [ -x "$PY" ]; then
  ENVS+=("GLOSSARY_PYTHON=$PY")
else
  echo "[INFO] Python の実行系の参照先が無いため、用語管理の検査は判定不能のまま進みます（${PY}）"
fi

if [ "${#ENVS[@]}" -gt 0 ]; then
  ( cd "$PAYLOAD_DIR" && env "${ENVS[@]}" bash "$AGG" ) > "$LOG" 2>&1
else
  ( cd "$PAYLOAD_DIR" && bash "$AGG" ) > "$LOG" 2>&1
fi

SUMMARY="$(tail -1 "$LOG")"
echo "$SUMMARY"

FAILS="$(printf '%s' "$SUMMARY" | sed -n 's/.*失敗 \([0-9]*\) 本.*/\1/p')"
if [ -z "$FAILS" ]; then
  echo "[UNKNOWN] 集約の集計行を読めないため判定できません"
  rm -f "$LOG"
  exit 2
fi

if [ "$FAILS" -ne 0 ]; then
  echo "[FAIL] 配布先で $FAILS 本が失敗しています。正本では通っても配布先では落ちる形の欠陥です。"
  grep -E '^\[FAIL\]' "$LOG" | head -10
  rm -f "$LOG"
  exit 1
fi

UNKNOWNS="$(printf '%s' "$SUMMARY" | sed -n 's/.*判定不能 \([0-9]*\) 本.*/\1/p')"
if [ -n "$UNKNOWNS" ] && [ "$UNKNOWNS" -ne 0 ]; then
  echo "[INFO] 判定不能が $UNKNOWNS 本あります。不合格ではありませんが、測れていません。"
  grep -E '^\[UNKNOWN\]' "$LOG" | head -10
fi

# 打ち切りは時間の上限を超えて止められたものである。合否が付いていない点は
# 判定不能と同じであり、放置すると測れていないことに気付けない。
ABORTED="$(printf '%s' "$SUMMARY" | sed -n 's/.*打ち切り \([0-9]*\) 本.*/\1/p')"
if [ -n "$ABORTED" ] && [ "$ABORTED" -ne 0 ]; then
  echo "[INFO] 打ち切りが $ABORTED 本あります。時間の上限を超えたため、合否が付いていません。"
  grep -E '打ち切' "$LOG" | grep -vE '^対象 ' | head -10
fi

echo "[PASS] 配布先で失敗0本です。"
rm -f "$LOG"
exit 0
