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

# mktemp を「呼んでいる」行だけを対象にする。行の中の mktemp の直前が
# コマンドの始まる位置（行頭・パイプ・分号・かつ・または・$( ・逆引用符）で
# ある行だけを数える。文字列の中の言及・コメント・ファイル名の一致は数えない。
# 実測（2026-08-28）で、この絞りが無いと3本を誤って拾った。内訳は
# ファイル名に mktemp を含むもの2本と、説明文の中で言及するもの1本である。
#
# perl の exit は END ブロックを実行してから終わるため、
# 途中で exit 0 しても END の exit 1 が終了コードを上書きする。
# 実測（2026-08-28）でこれを踏み、常に「呼んでいない」を返していた。
# フラグを立てて END で一度だけ返す形にする。
calls_mktemp() {
  perl -ne 'BEGIN { $found = 0 }
            $found = 1 if /(^|[|;&(`]|\$\()\s*(if\s+!\s+)?([A-Za-z_]\w*="?\$\()?\s*mktemp\b/;
            END { exit($found ? 0 : 1) }' "$1" 2>/dev/null
}

# mktemp をヘルパー関数の中で呼び、その関数の戻り値を呼び出し側が
# if ! で検査している形も失敗チェックとして認める。
# 実測（2026-08-28）で、この形を認めないと正しく書かれた2本を
# 誤って拾った。内訳は check-confirmation-doc-handover.sh と
# check-sample-sections.sh である。どちらも呼び出し側で
# `if ! tmp="$(_mk_tmp)" || [ -z "$tmp" ]` と検査していた。
# 行末の継続（バックスラッシュ）で次の行へ `||` を置く形も認める。
# GUARD_RE は1行の中だけを見るため、この形を拾えない。
# 実測（2026-08-28）で、正しく書かれた2本を誤って拾った。内訳は
# check-publish-complete.test.sh と check-template-sample-sync.test.sh である。
guarded_by_continuation() {
  perl -0777 -ne 'exit(/mktemp[^\n]*\\\s*\n\s*\|\|/ ? 0 : 1)' "$1" 2>/dev/null
}

guarded_via_helper() {
  perl -0777 -ne '
    my $found = 0;
    # mktemp を呼ぶ行を含む関数の名前を集める
    my %fn;
    my $cur = "";
    for my $line (split /\n/, $_) {
      if ($line =~ /^\s*(?:function\s+)?([A-Za-z_]\w*)\s*\(\)\s*\{/) { $cur = $1; }
      elsif ($line =~ /^\}/) { $cur = ""; }
      elsif ($cur ne "" && $line =~ /\bmktemp\b/ && $line !~ /^\s*#/) { $fn{$cur} = 1; }
    }
    # その関数名が if ! で検査されているか
    for my $name (keys %fn) {
      $found = 1 if /if\s+!\s+[A-Za-z_]\w*="\$\(\s*\Q$name\E\b/;
    }
    exit($found ? 0 : 1);
  ' "$1" 2>/dev/null
}

collect() {
  local root="$1" f
  [ -d "$root" ] || return 0
  while IFS= read -r f; do
    calls_mktemp "$f" || continue
    grep -qE "$GUARD_RE" "$f" 2>/dev/null && continue
    guarded_by_continuation "$f" && continue
    guarded_via_helper "$f" && continue
    printf '%s\n' "$f"
  done < <(find "$root" -name '*.sh' -type f 2>/dev/null | sort)
}

judge() {
  # 既定で止める。2026-08-28 に123本すべてを直し終え、該当0本になった。
  # 以後に該当が生まれたら、それは新しく書かれた無防備な mktemp である。
  # --lenient を渡すと報告のみで止めない（移行の途中で使う口を残す）。
  local strict=1
  if [ "${1:-}" = "--strict" ]; then shift
  elif [ "${1:-}" = "--lenient" ]; then strict=0; shift; fi

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

  # 既定は止めること。
  if judge "$tmp/bad" >/dev/null 2>&1; then
    echo "  [FAIL] 既定: 該当があるのに止まらない"; fail=$((fail + 1))
  else
    echo "  [PASS] 既定: 該当があれば止める"; pass=$((pass + 1))
  fi

  # --lenient は止めないこと。
  if judge --lenient "$tmp/bad" >/dev/null 2>&1; then
    echo "  [PASS] 緩和: --lenient は該当があっても止めない"; pass=$((pass + 1))
  else
    echo "  [FAIL] 緩和: --lenient なのに止まってしまう"; fail=$((fail + 1))
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
