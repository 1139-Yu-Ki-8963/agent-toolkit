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

# 見出しを突き合わせる形へ揃える。
# 様式は書き手向けの案内を含む。「（実測）」は「ここは観測した事実で埋める」
# という書き手への指示であり、書き上がった文書には残らない。「traced の条件」
# のような節も書き方の説明であり、成果物には出ない。これらを差として数えると、
# 正しく出ている見本まで「ずれ」と判定してしまう
# （実測 2026-08-24: 9 組のうち 3 組はこの注記だけの差だった）。
norm_headings() {
  LC_ALL=en_US.UTF-8 grep -E '^## ' "$1" 2>/dev/null \
    | LC_ALL=en_US.UTF-8 sed -e 's/（実測）//' -e 's/[[:space:]]*$//' \
    | LC_ALL=en_US.UTF-8 grep -vE '^## (traced の条件|記入規則|本書の使い方)$'
}

pairs=0; mismatch=0; missing=0
while IFS= read -r t; do
  [ -n "$t" ] || continue
  base="$(basename "$t")"
  # 様式は種別ごとのフォルダの下にある。同じ名前の様式が別の種別に
  # 並ぶことがあるため（DESIGN.md はプロジェクト共通と画面の両方にある）、
  # 名前だけで見本を選ぶと取り違える。種別を見て絞り込む。
  kind_dir="$(printf '%s' "${t#"$T_ROOT"/}" | cut -d/ -f1)"
  case "$kind_dir" in
    API) sub=apis ;; テーブル) sub=tables ;; バッチ) sub=batches ;;
    帳票) sub=reports ;; 外部連携) sub=externals ;; 機能) sub=features ;;
    画面) sub=screens ;; プロジェクト共通) sub=common ;; *) sub="" ;;
  esac
  s=""
  [ -n "$sub" ] && [ -d "$S_ROOT/$sub" ] \
    && s="$(find "$S_ROOT/$sub" -name "$base" -type f 2>/dev/null | LC_ALL=C sort | head -1)"
  if [ -z "$s" ]; then
    missing=$((missing + 1))
    echo "  見本なし: ${t#"$T_ROOT"/}"
    continue
  fi
  pairs=$((pairs + 1))
  if ! diff -q <(norm_headings "$t") <(norm_headings "$s") >/dev/null 2>&1; then
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
