#!/usr/bin/env bash
# 台帳の検収コマンドに雛形が残っていないかを見る。
#
# なぜ要るか: 検証する側は台帳のコマンドをそのまま実行する。
#   `<生成物>` や `<各項目の状態行>` のような雛形が残っていると、
#   そのコマンドは実行できない。実測（2026-08-28）で、134件のうち2件が
#   この形のまま残っていた。どちらも「完了」と記録された項目である。
#
#   雛形は、書いた本人には何を指すか分かる。読む側には分からない。
#   検証する側が再現できないコマンドは、記録として成立しない。
#
# 実装判断（走査に perl を使い grep を使わない）: BSD grep の -E は
#   ロケールによって多バイトの扱いが変わる。台帳は日本語であり、
#   雛形の中身も日本語である。perl はロケールに左右されない。
#
# 対象外とするもの: grep のパターンの中に現れる山括弧は雛形ではない。
#   `<th>要確認事項</th>` のように、探す対象そのものが山括弧を含む場合がある。
#   コマンドが grep で始まり、山括弧が引用符の内側にある場合は数えない。
#
# 使い方:
#   bash docs/scripts/check-ledger-command-placeholders.sh [台帳のパス]
#   bash docs/scripts/check-ledger-command-placeholders.sh --self-test
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"

scan() {
  local ledger="$1"
  [ -f "$ledger" ] || return 0
  perl -ne '
    next unless /^\*\*状態\*\*:/;
    my $line = $_;
    my $n = 0;
    while ($line =~ /`([^`]+)`/g) {
      my $cmd = $1;
      # 引用符の中の山括弧は探す対象であり雛形ではない。
      # 引用符の内側を消してから判定する。grep のパターンがこれに当たる。
      my $outside = $cmd;
      $outside =~ s/'"'"'[^'"'"']*'"'"'//g;
      $outside =~ s/"[^"]*"//g;
      $cmd = $outside;
      # 山括弧の中身が日本語（多バイト）なら雛形とみなす。
      # 山括弧の中身が英数字とハイフンだけなら、コマンドの引数の説明であり
      # 実行できない形なので同じく雛形とみなす。
      if ($cmd =~ /<[^>]*[^\x00-\x7F][^>]*>/ || $cmd =~ /<[a-zA-Z_][a-zA-Z0-9_-]*>/) {
        print "$.:$cmd\n";
        $n++;
      }
    }
  ' "$ledger"
}

judge() {
  local ledger="${1:-$REPO_ROOT/docs/tasks/指摘改善一覧.md}"
  if [ ! -f "$ledger" ]; then
    echo "[UNKNOWN] 台帳が見つからないため判定できません（${ledger}）"
    return 2
  fi

  local hits n
  hits="$(scan "$ledger")"
  if [ -z "$hits" ]; then
    echo "[PASS] 検収コマンドに雛形は残っていません。"
    return 0
  fi

  n="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
  echo "[FAIL] 検収コマンドに雛形が ${n} 件残っています。実在するパスへ直してください。"
  printf '%s\n' "$hits" | head -10
  return 1
}

self_test() {
  local pass=0 fail=0 tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/ledger-ph.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時領域を作れないため判定できません（mktempが書き込めませんでした）"
    exit 2
  fi

  printf '### 1-1. 試し\n\n**状態**: 完了。確かめたコマンドは `grep -oE "x" <生成物>` である。\n' > "$tmp/bad.md"
  printf '### 1-1. 試し\n\n**状態**: 完了。確かめたコマンドは `grep -oE "x" docs/a.html` である。\n' > "$tmp/good.md"
  printf '### 1-1. 試し\n\n**状態**: 完了。確かめたコマンドは `grep -r -e "<th>要確認事項</th>" docs` である。\n' > "$tmp/greppat.md"
  printf '### 1-1. 試し\n\n**状態**: 完了。確かめたコマンドは `bash x.sh <対象>` である。\n' > "$tmp/bad2.md"

  if judge "$tmp/bad.md" >/dev/null 2>&1; then
    echo "  [FAIL] 陽性: 日本語の雛形を検出できない"; fail=$((fail + 1))
  else
    echo "  [PASS] 陽性: 日本語の雛形を検出する"; pass=$((pass + 1))
  fi

  if judge "$tmp/bad2.md" >/dev/null 2>&1; then
    echo "  [FAIL] 陽性: 引数の雛形を検出できない"; fail=$((fail + 1))
  else
    echo "  [PASS] 陽性: 引数の雛形を検出する"; pass=$((pass + 1))
  fi

  if judge "$tmp/good.md" >/dev/null 2>&1; then
    echo "  [PASS] 陰性: 実在するパスは検出しない"; pass=$((pass + 1))
  else
    echo "  [FAIL] 陰性: 実在するパスを誤検出する"; fail=$((fail + 1))
  fi

  if judge "$tmp/greppat.md" >/dev/null 2>&1; then
    echo "  [PASS] 陰性: grep のパターンの山括弧は検出しない"; pass=$((pass + 1))
  else
    echo "  [FAIL] 陰性: grep のパターンの山括弧を誤検出する"; fail=$((fail + 1))
  fi

  # 走査が実際に動いたことを確かめる。
  local probe
  probe="$(scan "$tmp/bad.md")"
  if printf '%s' "$probe" | grep -q '生成物'; then
    echo "  [PASS] 走査: 行番号つきで該当を返す"; pass=$((pass + 1))
  else
    echo "  [FAIL] 走査: 該当を返さない（走査そのものが動いていない疑い）"; fail=$((fail + 1))
  fi

  if judge >/dev/null 2>&1; then
    echo "  [PASS] 現行: 台帳に雛形は無い"; pass=$((pass + 1))
  else
    echo "  [FAIL] 現行: 台帳に雛形が残っている"; fail=$((fail + 1))
  fi

  rm -rf "$tmp"
  echo "self-test: ${pass} PASS, ${fail} FAIL"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  *) judge "$@" ;;
esac
