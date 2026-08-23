#!/usr/bin/env bash
# check-sample-sections.sh — 様式と見本の節構成が一致するかを見る
#
# 判定の式を指示書の表へ直接書けないためスクリプトへ切り出した。
#
# 様式を直しても、見本が古い構成のまま残れば、読み手が見るのは古いほうである。
# 同じ名前のファイルどうしで、大見出しの名前と並びを突き合わせる。
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T_ROOT="${REPO_ROOT}/delivery-payload/templates/リバース検証"
S_ROOT="${REPO_ROOT}/generation-engine/samples/docs/design"

[ -d "$T_ROOT" ] || { echo "[UNKNOWN] 様式の置き場が見つからないため判定できません（参照したパス: ${T_ROOT}）" >&2; exit 2; }
[ -d "$S_ROOT" ] || { echo "[UNKNOWN] 見本の置き場が見つからないため判定できません（参照したパス: ${S_ROOT}）" >&2; exit 2; }

pairs=0; mismatch=0; missing=0
while IFS= read -r t; do
  [ -n "$t" ] || continue
  base="$(basename "$t")"
  s="$(find "$S_ROOT" -name "$base" -type f 2>/dev/null | LC_ALL=C sort | head -1)"
  if [ -z "$s" ]; then
    missing=$((missing + 1))
    echo "  見本なし: ${t#"$T_ROOT"/}"
    continue
  fi
  pairs=$((pairs + 1))
  if ! diff -q <(LC_ALL=en_US.UTF-8 grep -E '^## ' "$t" 2>/dev/null) \
                <(LC_ALL=en_US.UTF-8 grep -E '^## ' "$s" 2>/dev/null) >/dev/null 2>&1; then
    mismatch=$((mismatch + 1))
    echo "  節構成のずれ: ${base}"
  fi
done < <(find "$T_ROOT" -name '*.md' -type f 2>/dev/null | LC_ALL=C sort)

echo "対応 ${pairs} 組 / ずれ ${mismatch} 組 / 見本なし ${missing} 件"
if [ "$mismatch" -eq 0 ] && [ "$missing" -eq 0 ]; then
  echo "[PASS] 様式と見本の節構成が一致"
  exit 0
fi
echo "[FAIL] 一致しない様式がある"
exit 1
