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

# 一時ファイルを作る。
#
# 実装判断: プロセス置換（<(...)）を diff・comm など外部コマンドの引数へ
# 渡すと /dev/fd/N が渡るが、実行環境によってはこれを開けない
# （実測 2026-08-24: diff: /dev/fd/11: Operation not permitted）。
# 比較そのものが失敗するため、失敗を「不合格」と読み違えると、中身に問題が
# 無いのに不合格を報告する（実測: 同じ検査が制限下で「ずれ 32 組」、制限を
# 外すと「ずれ 4 組」を返した）。一時ファイルを経由してこの揺れを断つ。
#
# 置き場を明示するのは、引数なしの mktemp が既定の置き場へ書こうとして
# 失敗するためである（実測 2026-08-24:
# mktemp: mkstemp failed on /var/folders/.../T/tmp.XXXX: Operation not
# permitted）。TMPDIR を明示すると成功する。
# この形を素直な mktemp へ戻してはならない。手元で動いても環境が変われば
# 再び壊れる。
_mk_tmp() {
  mktemp "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null
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

  # 設計単位の下に置かない文書がある。プロジェクト全体の結合テスト仕様書が
  # これに当たり、出力先の定義（output-layout.json の projectIntegrationTest）は
  # docs/test-cases/ を指す。設計単位の下だけを探すと見つからない。
  # 実測（2026-08-28）で、この1件が「見本なし」として不合格になっていた。
  # 見本は実在しており、探索先が足りないだけだった。
  if [ -z "$s" ]; then
    s="$(find "${REPO_ROOT}/generation-engine/samples/docs" -name "$base" -type f 2>/dev/null \
         | grep -v '/docs/design/' | LC_ALL=C sort | head -1)"
  fi

  if [ -z "$s" ]; then
    missing=$((missing + 1))
    echo "  見本なし: ${t#"$T_ROOT"/}"
    continue
  fi
  pairs=$((pairs + 1))
  if ! _ta="$(_mk_tmp)" || [ -z "$_ta" ] || ! _tb="$(_mk_tmp)" || [ -z "$_tb" ]; then
    rm -f "${_ta:-}" "${_tb:-}"
    echo "[UNKNOWN] 一時ファイルを作れないため判定できません（mktemp が一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  norm_headings "$t" > "$_ta"
  norm_headings "$s" > "$_tb"
  if ! diff -q "$_ta" "$_tb" >/dev/null 2>&1; then
    mismatch=$((mismatch + 1))
    echo "  節構成のずれ: ${base}"
  fi
  rm -f "$_ta" "$_tb"
done < <(find "$T_ROOT" -name '*.md' -type f 2>/dev/null | LC_ALL=C sort)

echo "対応 ${pairs} 組 / ずれ ${mismatch} 組 / 見本なし ${missing} 件"
if [ "$mismatch" -eq 0 ] && [ "$missing" -eq 0 ]; then
  echo "[PASS] 様式と見本の節構成が一致"
  exit 0
fi
echo "[FAIL] 一致しない様式がある"
exit 1
