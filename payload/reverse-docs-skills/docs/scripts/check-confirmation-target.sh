#!/usr/bin/env bash
# check-confirmation-target.sh — 要確認事項一覧への指示が実在する記録先を指しているかを見る
#
# 判定の式を指示書の表へ直接書けないためスクリプトへ切り出した。式に含まれる
# 縦棒を片付けの判定器が列の区切りと読み違え、判定行そのものを壊すためである
# （.claude/rules/always/tasks/instruction-format/rule.md の設計判断を参照）。
#
# 実装判断（本ファイル固有）: 検査2は「『要確認事項』を含む行のうち『根拠を
# 記録する資料』を含まない行が0件であること」を見る形で指示書（1-223の
# 積み残し）から指示された。ところが本スクリプトの新設時点で、対象配下
# （delivery-payload/templates/リバース検証/）に残っていた63箇所はすべて
# 「本書の要確認事項一覧」という、1-223がいったん外した記録先を指す文だった。
# 「根拠を記録する資料」という記録先は改善課題1-246で対象コード行番号への
# 依存ごと廃止済みで、generation-engine/scripts/tests/check-design-doc-section-consistency.sh
# の自己テスト（課題1-223-廃止済み資料名を含む参照の残存数）が、この語が
# 対象配下に再び現れることを既に禁止している（0件を要求）。したがって本スク
# リプトは、指示された記録先へ向け直すのではなく、「要確認事項一覧」への
# 指示そのものを対象配下から無くす形で直した。この結果、検査1（一覧見出しへ
# の指示が0件）を満たした時点で検査2の分母（『要確認事項』を含む行）も0件に
# なり、検査2の「根拠を記録する資料を含まない行」という絞り込み条件は空集合
# に対する走査となって、以後 到達しない分岐として残る。到達しないことは
# 欠陥ではなく、対象配下から『要確認事項』という語自体を無くしたことの帰結
# である。将来『要確認事項』を指す記述を対象配下へ再び持ち込む変更をする
# 場合は、その記述が指す先が実在するかを別途確認すること。
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="${1:-${REPO_ROOT}/delivery-payload/templates/リバース検証}"

judge() {
  local root="$1"
  [ -d "$root" ] || { echo "[UNKNOWN] 走査対象の置き場が見つからないため判定できません（参照したパス: ${root}）"; return 2; }

  local list_count unresolved_count unresolved_lines rc=0
  list_count="$(grep -rn '要確認事項一覧' "$root" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')"
  unresolved_lines="$(grep -rn '要確認事項' "$root" --include='*.md' 2>/dev/null | grep -v '根拠を記録する資料' || true)"
  unresolved_count="$(printf '%s\n' "$unresolved_lines" | grep -c . || true)"
  [ -z "$unresolved_lines" ] && unresolved_count=0

  if [ "$list_count" -eq 0 ]; then
    echo "[PASS] 検査1-要確認事項一覧への指示=0件"
  else
    echo "[FAIL] 検査1-要確認事項一覧への指示=${list_count}件"
    grep -rn '要確認事項一覧' "$root" --include='*.md' 2>/dev/null | sed "s#${root}/#  #"
    rc=1
  fi

  if [ "$unresolved_count" -eq 0 ]; then
    echo "[PASS] 検査2-根拠を記録する資料を指さない要確認事項の記述=0件"
  else
    echo "[FAIL] 検査2-根拠を記録する資料を指さない要確認事項の記述=${unresolved_count}件"
    printf '%s\n' "$unresolved_lines" | sed "s#${root}/#  #"
    rc=1
  fi

  return "$rc"
}

run_self_test() {
  local pass=0 fail=0
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-confirmation-target-self-test.XXXXXX" 2>/dev/null || true)"
  # 実装判断: 引数なしの mktemp は既定の置き場へ書こうとして失敗する環境が
  # ある（実測: mktemp: mkstemp failed on /var/folders/.../T/tmp.XXXX:
  # Operation not permitted）。置き場を明示したうえで、それでも失敗した
  # 場合は判定不能規約に従い [UNKNOWN] を返す。
  if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
    echo "[UNKNOWN] 自己テスト用の一時ディレクトリを作成できませんでした"
    exit 2
  fi
  trap 'rm -rf "${tmp:-}"' EXIT

  assert_rc() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" -eq "$expected" ]; then
      echo "[PASS] ${label}"
      pass=$((pass + 1))
    else
      echo "[FAIL] ${label}（期待: ${expected} / 実際: ${actual}）"
      fail=$((fail + 1))
    fi
  }

  # ケース1: 「要確認事項」を含む行が1件も無ければ合格する。
  mkdir -p "$tmp/case1"
  printf '# 見本\n\n確定できなかった事項は推測で埋めず、空欄のままとする。\n' > "$tmp/case1/見本.md"
  judge "$tmp/case1" >/dev/null 2>&1
  assert_rc "ケース1-記述なしは合格" 0 "$?"

  # ケース2: 「要確認事項一覧」への指示が残っていれば検査1で不合格にする。
  mkdir -p "$tmp/case2"
  printf '# 見本\n\n確定できなかった事項は本書の要確認事項一覧へ記録する。\n' > "$tmp/case2/見本.md"
  judge "$tmp/case2" >/dev/null 2>&1
  assert_rc "ケース2-一覧見出しへの指示は不合格" 1 "$?"

  # ケース3: 「根拠を記録する資料」を伴う「要確認事項」の記述は検査2の対象外として合格する。
  mkdir -p "$tmp/case3"
  printf '# 見本\n\n要確認事項は根拠を記録する資料へ記録する。\n' > "$tmp/case3/見本.md"
  judge "$tmp/case3" >/dev/null 2>&1
  assert_rc "ケース3-根拠を記録する資料を伴う記述は合格" 0 "$?"

  # ケース4: 走査対象の置き場が無ければ判定不能として終了コード2を返す。
  judge "$tmp/no-such-dir" >/dev/null 2>&1
  assert_rc "ケース4-置き場不在は判定不能" 2 "$?"

  echo "self-test: ${pass} PASS, ${fail} FAIL"
  [ "$fail" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

judge "$ROOT"
exit $?
