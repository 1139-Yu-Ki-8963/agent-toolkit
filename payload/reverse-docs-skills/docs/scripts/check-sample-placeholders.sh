#!/usr/bin/env bash
# check-sample-placeholders.sh — 見本に未置換の記入欄が残っていないかを見る
#
# 判定の式を指示書の表へ直接書けないためスクリプトへ切り出した。式に含まれる
# 縦棒を片付けの判定器が列の区切りと読み違え、判定行そのものを壊すためである
# （.claude/rules/always/tasks/instruction-format/rule.md の設計判断を参照）。
#
# 見本は様式から作る。様式が持つ記入欄（山括弧で囲んだ語や、すべて大文字の
# 目印）が埋まらないまま残ると、読み手は書き忘れと見分けられない。
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# 見本は2つある。画面を持つものと持たないものである。
# 片方だけを走査すると、もう片方に未置換の記入欄が残っても検知できない
# （2026-08-28実測。同じ構造の取り残しが文体・ずれ台帳・廃止語で起きた）。
ROOTS=()
if [ "$#" -gt 0 ]; then
  ROOTS=("$@")
else
  ROOTS=("${REPO_ROOT}/generation-engine/samples/docs/design")
  [ -d "${REPO_ROOT}/generation-engine/samples-no-screen" ] \
    && ROOTS+=("${REPO_ROOT}/generation-engine/samples-no-screen")
  [ -d "${REPO_ROOT}/generation-engine/samples-api-only/docs/design" ] \
    && ROOTS+=("${REPO_ROOT}/generation-engine/samples-api-only/docs/design")
fi
ROOT="${ROOTS[0]}"

[ -d "$ROOT" ] || { echo "[UNKNOWN] 見本の置き場が見つからないため判定できません（参照したパス: ${ROOT}）" >&2; exit 2; }

# 山括弧で囲んだ記入欄と、様式が使うすべて大文字の目印を探す。
found=""
for _root in "${ROOTS[@]}"; do
  [ -d "$_root" ] || continue
  _hit="$(LC_ALL=en_US.UTF-8 grep -rnoE '<[^<>]{2,40}のパス>|<[^<>]{2,20}名>|\bAPIKEY\b|\bSOURCEREF\b|\bVARIABLENAME\b|\bEVIDENCE\b' \
    "$_root" --include='*.md' 2>/dev/null | head -20)"
  [ -n "$_hit" ] && found="${found}${_hit}
"
done
n="$(printf '%s' "$found" | LC_ALL=C grep -c . || :)"

if [ "${n:-0}" -eq 0 ]; then
  echo "[PASS] 未置換の記入欄=0件"
  exit 0
fi
echo "[FAIL] 未置換の記入欄=${n}件"
printf '%s\n' "$found" | sed "s#${REPO_ROOT}/#  #"
exit 1
