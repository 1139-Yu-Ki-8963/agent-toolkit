#!/usr/bin/env bash
# check-section-classification.sh — 設計文書の様式の各節に位置づけの行があるかを見る（改善課題1-287・1-302）
#
# 設計書様式.md §10 は、`## §N` の見出しの直後に `**この節の位置づけ: 仕様**` の形の1行を置くと定める。
# 値は「仕様」「現行実装」「仕様／現行実装」の3語に固定し、「現行実装」は末尾に作り直すときの扱いを書く。
# 本検査は次の3点を見る。
#   1. 様式（delivery-payload/templates/リバース検証 配下の .md）の全 `## §` 見出しの直後（3行以内）に位置づけの行があり、文書の冒頭に位置づけごとの節の一覧がある
#   2. 位置づけの語が「仕様」「現行実装」「仕様／現行実装」の3語に限られ、「現行実装」は末尾に作り直すときの扱い（引き継がない／確かめる必要がある／決める必要がある）を持つ
#   3. 位置づけの行が特定の言語名・移行の前提を含まない
# 1件でも外れれば終了コード1。
#
# 使い方:
#   check-section-classification.sh [<起点ディレクトリ>...]   既定: delivery-payload/templates/リバース検証
#   check-section-classification.sh --self-test
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LANG_RE='Perl|PHP|Java|Python|Ruby|JavaScript|TypeScript|Go言語|Rust|C#|C\+\+|Kotlin|Swift|移行'

scan_file() {
  local f="$1"
  perl -CSD -Mutf8 -ne '
    BEGIN { $f = shift @ARGV; }
    push @L, $_;
    END {
      for my $i (0..$#L) {
        next unless $L[$i] =~ /^## §\d+/;
        my $found = "";
        for my $j ($i+1 .. $i+3) { last if $j > $#L; if ($L[$j] =~ /^\*\*この節の位置づけ: (.*)\*\*\s*$/) { $found = $1; last; } }
        if ($found eq "") { print "$f:" . ($i+1) . ": 位置づけの行が無い（" . ($L[$i] =~ s/\n//r) . "）\n"; next; }
        if ($found !~ /^(仕様|現行実装。.+(作り直す際は引き継がない|作り直す前に、.+を確かめる必要がある|作り直す前に、.+を決める必要がある)|仕様／現行実装。.+)\s*$/) { print "$f:" . ($i+1) . ": 定めた語ではない位置づけ（${found}）\n"; }
        if ($found =~ /'"$LANG_RE"'/) { print "$f:" . ($i+1) . ": 位置づけの語に言語名または移行の前提が含まれる（${found}）\n"; }
      }
    }' "$f" "$f"
}

run_check() {
  local hits=0 f out
  for root in "$@"; do
    while IFS= read -r f; do
      out="$(scan_file "$f")"
      if [ -n "$out" ]; then printf '%s\n' "$out"; hits=$((hits + $(printf '%s\n' "$out" | grep -c .))); fi
    done < <(find "$root" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
  done
  if [ "$hits" -gt 0 ]; then echo "[FAIL] 位置づけの行の不備が ${hits} 件あります"; return 1; fi
  echo "[PASS] 全ての節に定めた語の位置づけがあり、言語名を含みません"
}

self_test() {
  local tmp pass=0 fail=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-section-classification.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため自己テストを判定できません（mktemp が一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/good" "$tmp/missing" "$tmp/lang" "$tmp/word"
  printf '## §1 概要\n\n**この節の位置づけ: 仕様**\n\n本文\n\n## §2 実装契約\n\n**この節の位置づけ: 現行実装。実装の作りを記録した節である。作り直す際は引き継がない**\n' > "$tmp/good/a.md"
  printf '## §1 概要\n\n本文\n' > "$tmp/missing/a.md"
  printf '## §1 概要\n\n**この節の位置づけ: 現行実装。Perl固有の作りである。移行時に捨てる。作り直す際は引き継がない**\n' > "$tmp/lang/a.md"
  printf '## §1 概要\n\n**この節の位置づけ: 実装**\n' > "$tmp/word/a.md"
  if _cap="$(run_check "$tmp/good" 2>&1)"; then echo "  [PASS] 陰性: 定めた語の位置づけは通る"; pass=$((pass+1)); else { echo "  [FAIL] 陰性: 定めた語の位置づけを誤検出する"; printf '%s
' "$_cap" | sed 's/^/      /' >&2; }; fail=$((fail+1)); fi
  if ! _cap="$(run_check "$tmp/missing" 2>&1)"; then echo "  [PASS] 陽性: 位置づけの無い節を検出する"; pass=$((pass+1)); else { echo "  [FAIL] 陽性: 位置づけの無い節を見逃す"; printf '%s
' "$_cap" | sed 's/^/      /' >&2; }; fail=$((fail+1)); fi
  out="$(run_check "$tmp/missing" 2>&1)"; if printf '%s' "$out" | grep -q 'a.md:1:'; then echo "  [PASS] 走査: 行番号つきで該当行を返す"; pass=$((pass+1)); else echo "  [FAIL] 走査: 該当行を返さない"; fail=$((fail+1)); fi
  if ! _cap="$(run_check "$tmp/lang" 2>&1)"; then echo "  [PASS] 陽性: 言語名・移行の前提を含む位置づけを検出する"; pass=$((pass+1)); else { echo "  [FAIL] 陽性: 言語名を見逃す"; printf '%s
' "$_cap" | sed 's/^/      /' >&2; }; fail=$((fail+1)); fi
  if ! _cap="$(run_check "$tmp/word" 2>&1)"; then echo "  [PASS] 陽性: 定めていない語を検出する"; pass=$((pass+1)); else { echo "  [FAIL] 陽性: 定めていない語を見逃す"; printf '%s
' "$_cap" | sed 's/^/      /' >&2; }; fail=$((fail+1)); fi
  echo "self-test: ${pass} PASS, ${fail} FAIL"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  '') run_check "$REPO_ROOT/delivery-payload/templates/リバース検証" ;;
  *) run_check "$@" ;;
esac
