#!/usr/bin/env bash
# check-coverage-zero.sh — 網羅の判定で欠落が 0 件かを見る
#
# 判定の式を指示書の表へ直接書けないためスクリプトへ切り出した。式に含まれる
# 縦棒を片付けの判定器が列の区切りと読み違え、判定行そのものを壊すためである
# （.claude/rules/always/tasks/instruction-format/rule.md の設計判断を参照）。
#
# 網羅の判定は生成物のディレクトリを要する。第3層を1回走らせてから判定する。
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
V="${REPO_ROOT}/generation-engine/scripts/verification"

if ! out_base="$(bash -c "source '${V}/verification-env.sh'; id=\"\$(verification_env_new_id)\"; verification_env_setup \"\$id\"" 2>/dev/null)" || [ -z "$out_base" ]; then
  echo "[UNKNOWN] 使い捨ての作業領域を作れないため判定できません（verification_env_setup が一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi
trap 'rm -rf "$out_base" 2>/dev/null || :' EXIT

bash "${V}/run-layer-full-pipeline.sh" --output "${out_base}/output" >/dev/null 2>&1 || :
res="$(bash "${V}/check-coverage.sh" --output "${out_base}/output" 2>&1)" || :
n="$(printf '%s\n' "$res" | LC_ALL=C sed -n 's/.*欠落 \([0-9][0-9]*\) 件.*/\1/p' | head -1)"

if [ -z "$n" ]; then
  echo "[UNKNOWN] 網羅の出力から欠落の件数を読めないため判定できません（sed による集計行の読み取りに失敗しました。出力の書式が変わった可能性があります）" >&2
  exit 2
fi
if [ "$n" -eq 0 ]; then
  echo "[PASS] 網羅の欠落=0件"
  exit 0
fi
echo "[FAIL] 網羅の欠落=${n}件"
exit 1
