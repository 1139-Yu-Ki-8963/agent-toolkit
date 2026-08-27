#!/usr/bin/env bash
# mktemp を使うのに失敗チェックを1つも持たないスクリプトを数える。
#
# なぜ要るか: mktemp は実行環境の制約で失敗する。サンドボックスの下では
#   「Operation not permitted」を返す。戻り値を見ないスクリプトは、
#   空文字のまま処理を続ける。実測（2026-08-28）で build-portal.sh が
#   `/repo` や `/docs` という絶対パスへ書こうとし、62件の自己テストが
#   まとめて不合格になった。対象の中身には何の問題も無かった。
#
#   判定不能の規約（.claude/rules/always/verification/indeterminate-result/rule.md）は
#   「実行できなかった」と「不合格だった」を区別することを定めるが、
#   その適合は機械で判定できないとして機械強制を見送っている。
#   本検査はその手前の一段だけを見る。失敗チェックが1つも無いことは機械で分かる。
#
# 既定は報告のみで終了コード0を返す。実測時点で122本が該当し、一度に止めると
#   直すまで集約が動かなくなる。--strict のときだけ1件でもあれば終了コード1を返す。
#   この形は check-ledger-completion-reproducibility.sh の先例に倣う。
#
# 既知の限界: ファイルの中に失敗チェックが1つでもあれば合格とする。
#   複数の mktemp 呼び出しのうち一部だけが無防備な場合は拾えない。
#   実測（2026-08-28）で build-portal.sh がこれに当たった。8箇所のうち
#   ヘルパー1箇所だけがチェックを持ち、残る3箇所は戻り値を見ていなかった。
#   呼び出し回数とチェック回数を比べる形にすると、ヘルパー経由で複数箇所を
#   守っている場合を誤って不合格にする。まず「1つも無い」を拾う最低線から始める。
#
# 使い方:
#   bash docs/scripts/check-mktemp-failure-guard.sh [--strict] [対象ディレクトリ...]
#   bash docs/scripts/check-mktemp-failure-guard.sh --self-test
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"

# 失敗チェックとして認める形。
#   if ! VAR="$(mktemp ...)"  … 条件式の中で代入と検査を同時に行う
#   mktemp ... || …           … 直後に代替の処理を置く
GUARD_RE='if ! [A-Za-z_][A-Za-z0-9_]*="\$\(mktemp|mktemp[^|]*\|\|'

collect() {
  local root="$1" f
  [ -d "$root" ] || return 0
  while IFS= read -r f; do
    grep -q 'mktemp' "$f" 2>/dev/null || continue
    grep -qE "$GUARD_RE" "$f" 2>/dev/null && continue
    printf '%s\n' "$f"
  done < <(find "$root" -name '*.sh' -type f 2>/dev/null | sort)
}

judge() {
  local strict=0
  if [ "${1:-}" = "--strict" ]; then strict=1; shift; fi

  local roots=("$@")
  if [ "$#" -eq 0 ]; then
    roots=(
      "$REPO_ROOT/docs/scripts"
      "$REPO_ROOT/generation-engine/scripts"
      "$REPO_ROOT/delivery-payload/templates/rules/checkers"
      "$REPO_ROOT/.claude/rules"
    )
  fi

  local hits="" r out
  for r in "${roots[@]}"; do
    out="$(collect "$r")"
    [ -n "$out" ] && hits="${hits}${out}"$'\n'
  done
  hits="$(printf '%s' "$hits" | sed '/^$/d')"

  local n=0
  [ -n "$hits" ] && n="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"

  if [ "$n" -eq 0 ]; then
    echo "[PASS] mktemp の失敗チェックを欠くスクリプトはありません。"
    return 0
  fi

  if [ "$strict" -eq 1 ]; then
    echo "[FAIL] mktemp の失敗チェックを欠くスクリプトが ${n} 本あります。"
    printf '%s\n' "$hits" | head -20
    return 1
  fi

  echo "[INFO] mktemp の失敗チェックを欠くスクリプトが ${n} 本あります。既定では止めません。"
  echo "[INFO] 止めるには --strict を渡します。直し方は判定不能の規約を見ます。"
  return 0
}

self_test() {
  local pass=0 fail=0 tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/mtguard.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時領域を作れないため判定できません（mktempが書き込めませんでした）"
    exit 2
  fi

  mkdir -p "$tmp/bad" "$tmp/good1" "$tmp/good2" "$tmp/none"
  printf '#!/usr/bin/env bash\nT="$(mktemp)"\necho "$T"\n' > "$tmp/bad/probe.sh"
  printf '#!/usr/bin/env bash\nif ! T="$(mktemp)" || [ -z "$T" ]; then exit 2; fi\n' > "$tmp/good1/probe.sh"
  printf '#!/usr/bin/env bash\nT="$(mktemp)" || exit 2\n' > "$tmp/good2/probe.sh"
  printf '#!/usr/bin/env bash\necho "一時ファイルを使わない"\n' > "$tmp/none/probe.sh"

  if judge --strict "$tmp/bad" >/dev/null 2>&1; then
    echo "  [FAIL] 陽性: 失敗チェックなしを検出できない"; fail=$((fail + 1))
  else
    echo "  [PASS] 陽性: 失敗チェックなしを検出する"; pass=$((pass + 1))
  fi

  if judge --strict "$tmp/good1" >/dev/null 2>&1; then
    echo "  [PASS] 陰性: if ! の形は検出しない"; pass=$((pass + 1))
  else
    echo "  [FAIL] 陰性: if ! の形を誤検出する"; fail=$((fail + 1))
  fi

  if judge --strict "$tmp/good2" >/dev/null 2>&1; then
    echo "  [PASS] 陰性: || の形は検出しない"; pass=$((pass + 1))
  else
    echo "  [FAIL] 陰性: || の形を誤検出する"; fail=$((fail + 1))
  fi

  if judge --strict "$tmp/none" >/dev/null 2>&1; then
    echo "  [PASS] 陰性: mktemp を使わない形は対象外"; pass=$((pass + 1))
  else
    echo "  [FAIL] 陰性: mktemp を使わない形を誤検出する"; fail=$((fail + 1))
  fi

  # 既定は止めないこと。
  if judge "$tmp/bad" >/dev/null 2>&1; then
    echo "  [PASS] 既定: 該当があっても止めない"; pass=$((pass + 1))
  else
    echo "  [FAIL] 既定: 該当があると止まってしまう"; fail=$((fail + 1))
  fi

  # 走査が実際に動いたことを確かめる。
  local probe_out
  probe_out="$(collect "$tmp/bad")"
  if printf '%s' "$probe_out" | grep -q 'bad/probe.sh'; then
    echo "  [PASS] 走査: 該当ファイルの名前を返す"; pass=$((pass + 1))
  else
    echo "  [FAIL] 走査: 該当ファイルを返さない（走査そのものが動いていない疑い）"; fail=$((fail + 1))
  fi

  rm -rf "$tmp"
  echo "self-test: ${pass} PASS, ${fail} FAIL"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  *) judge "$@" ;;
esac
