#!/usr/bin/env bash
set -euo pipefail

# test-plan-on-self.sh — このリポジトリ自身 (docs/skills) を対象に計画を組み立て、
# 規約の配置（docs/rules を出力する機能）が規約の派生（docs/rules を入力する機能）
# より前に並ぶことを、機能名を直書きせず宣言（outputs/inputs の値）から求めて確かめる。
#
# 終了コード: 0=合格 1=不合格 2=前提不足（判定不能）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN_SCRIPT="${SCRIPT_DIR}/../scripts/plan-setup.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
SKILLS_ROOT="${REPO_ROOT}/docs/skills"

if [ ! -d "$SKILLS_ROOT" ]; then
  echo "[UNKNOWN] docs/skills が見当たらない: ${SKILLS_ROOT}" >&2
  exit 2
fi

fm_extract() {
  local file="$1" first_line
  first_line="$(head -n1 "$file" 2>/dev/null || true)"
  [ "$first_line" = "---" ] || return 1
  awk 'NR==1{next} /^---$/{exit} {print}' "$file"
}

fm_get_array_raw() {
  local body="$1" key="$2" line
  line="$(printf '%s\n' "$body" | grep -E "^${key}:" | head -n1 || true)"
  [ -n "$line" ] || return 1
  printf '%s\n' "${line#"${key}: "}"
}

fm_get_scalar() {
  local body="$1" key="$2" line
  line="$(printf '%s\n' "$body" | grep -E "^${key}:" | head -n1 || true)"
  [ -n "$line" ] || { printf ''; return 1; }
  printf '%s' "${line#"${key}: "}"
}

# docs/rules/ を出力する機能名・入力する機能名を、それぞれ宣言から1件ずつ探す。
# plan-setup.sh は --units setup の計画で検証するため、探索も unit: setup の
# 機能に絞る（他単位の機能が同じ入出力パターンを持っていても対象にしない）。
producer=""
consumer=""
f_list="$(find "$SKILLS_ROOT" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' | sort)"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  dir="$(dirname "$f")"
  name="$(basename "$dir")"
  body="$(fm_extract "$f")" || continue
  declared_unit="$(fm_get_scalar "$body" unit || true)"
  [ "$declared_unit" = "setup" ] || continue
  outputs_raw="$(fm_get_array_raw "$body" outputs || echo '[]')"
  inputs_raw="$(fm_get_array_raw "$body" inputs || echo '[]')"
  if [ -z "$producer" ] && printf '%s' "$outputs_raw" | grep -q 'docs/rules/'; then
    producer="$name"
  fi
  if [ -z "$consumer" ] && printf '%s' "$inputs_raw" | grep -q 'docs/rules/'; then
    consumer="$name"
  fi
done <<LIST
$f_list
LIST

if [ -z "$producer" ] || [ -z "$consumer" ]; then
  echo "[UNKNOWN] docs/rules/ を出力・入力する機能の宣言が見つからない（producer=${producer:-なし} consumer=${consumer:-なし}）" >&2
  exit 2
fi

out="$("$PLAN_SCRIPT" "$REPO_ROOT" --units setup --format steps 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "[FAIL] plan-setup.sh が終了コード0で返らない (exit ${rc})" >&2
  printf '%s\n' "$out" | sed 's/^/  /' >&2
  exit 1
fi

producer_line="$(printf '%s\n' "$out" | grep -n -m1 -F "$producer" | cut -d: -f1)"
consumer_line="$(printf '%s\n' "$out" | grep -n -m1 -F "$consumer" | cut -d: -f1)"

if [ -z "$producer_line" ] || [ -z "$consumer_line" ]; then
  echo "[FAIL] 計画の出力に ${producer} または ${consumer} が現れない" >&2
  printf '%s\n' "$out" | sed 's/^/  /' >&2
  exit 1
fi

if [ "$producer_line" -lt "$consumer_line" ]; then
  echo "[PASS] ${producer}（docs/rules/ を出力）が ${consumer}（docs/rules/ を入力）より前に並ぶ"
  exit 0
fi

echo "[FAIL] ${producer} が ${consumer} より前に並ばない" >&2
printf '%s\n' "$out" | sed 's/^/  /' >&2
exit 1
