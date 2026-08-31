#!/usr/bin/env bash
# 台帳の検収コマンドのうち、grep の終了コードの向きを取り違えたものを見つける。
#
# なぜ要るか: 「該当が0件であること」を確かめる検収がある。
#   grep は0件のとき終了コード1を返す。その1をそのまま使うと、
#   正しい状態（0件）を不合格として報告する。
#
#   実測（2026-08-28）で、この形が6件見つかった。
#   1-214・1-221・1-275・1-277 ほかである。いずれも中身は完了していた。
#   検収コマンドの書き方だけが誤っていた。
#
#   同じ形は今後も書かれる。書くたびに人が向きを確かめる運用では防げない。
#
# 判定: 台帳の完了行から grep で始まるコマンドを取り出し、実際に実行する。
#   終了コード1で終わり、かつ反転（`!`）も後置の判定（`test $? -eq 1` 等）も
#   持たないものを「向きを取り違えている疑い」として報告する。
#
#   実行を伴うのは、静的な走査では「0件が正しいのか、該当を期待するのか」を
#   判定できないためである。実行して1が返り、かつ向きの手当てが無いものだけが疑わしい。
#
# 使い方:
#   bash docs/scripts/check-ledger-grep-exit-code.sh
#   bash docs/scripts/check-ledger-grep-exit-code.sh --self-test
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
RUNNER="$SCRIPT_DIR/check-ledger-commands-runnable.sh"

judge() {
  [ -f "$RUNNER" ] || { echo "[UNKNOWN] 一覧を取る道具が無いため判定できません（${RUNNER}）"; return 2; }
  cd "$REPO_ROOT" || return 2

  local list hits=0 out
  if ! list="$(mktemp "${TMPDIR:-/tmp}/grep-invert.XXXXXX" 2>/dev/null)" || [ -z "$list" ]; then
    echo "[UNKNOWN] 一時ファイルを作れないため判定できません（mktempが書き込めませんでした）"
    return 2
  fi

  # grep で始まり、反転も後置の判定も持たないコマンドだけを見る。
  bash "$RUNNER" --list 2>/dev/null \
    | awk -F'\t' '$2 ~ /^grep / && $2 !~ /!/ && $2 !~ /test \$\? / {print $1 "\t" $2}' > "$list"

  while IFS=$'\t' read -r key cmd; do
    [ -n "$cmd" ] || continue
    _cap="$(( eval "$cmd" ) 2>&1)"
    if [ "$?" -eq 1 ]; then
      [ "$hits" -eq 0 ] && echo "[FAIL] grep の終了コードの向きを取り違えた疑いがあります。"
      printf '%s\n' "$_cap" | sed 's/^/      /' >&2
      printf '  %s: %s\n' "$key" "$(printf '%s' "$cmd" | cut -c1-80)"
      hits=$((hits + 1))
    fi
  done < "$list"

  rm -f "$list"
  if [ "$hits" -eq 0 ]; then
    echo "[PASS] grep の終了コードの向きを取り違えた検収はありません。"
    return 0
  fi
  echo "  該当が0件であることを確かめる検収なら、bash -c \"! grep -q ...\" の形へ直します。"
  return 1
}

self_test() {
  local pass=0 fail=0 tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/gi-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時領域を作れないため判定できません（mktempが書き込めませんでした）"
    exit 2
  fi

  # 疑わしい形: grep で始まり反転が無く、実行すると1で終わる
  # ディレクトリへ -r 無しで当てると終了コード2（エラー）になるため、実ファイルを使う。
  printf 'abc\n' > "$tmp/probe.txt"
  ( eval "grep -q 存在しない文字列XYZ $tmp/probe.txt" ) > /dev/null 2>&1
  if [ "$?" -eq 1 ]; then
    echo "  [PASS] 判定: 該当0件の grep は終了コード1を返す"; pass=$((pass + 1))
  else
    echo "  [FAIL] 判定: 該当0件の grep が1を返さない"; fail=$((fail + 1))
  fi

  # 反転した形は0で終わる
  ( eval "bash -c \"! grep -q 存在しない文字列XYZ $tmp\"" ) > /dev/null 2>&1
  if [ "$?" -eq 0 ]; then
    echo "  [PASS] 判定: 反転した形は終了コード0を返す"; pass=$((pass + 1))
  else
    echo "  [FAIL] 判定: 反転した形が0を返さない"; fail=$((fail + 1))
  fi

  # 絞り込みが反転を除くこと
  local n
  n=$(printf '1-1\tbash -c "! grep -q x y"\n1-2\tgrep -q x y\n' \
      | awk -F'\t' '$2 ~ /^grep / && $2 !~ /!/ && $2 !~ /test \$\? / {print $1}' | wc -l | tr -d ' ')
  if [ "$n" = "1" ]; then
    echo "  [PASS] 絞り込み: 反転した形を対象から外す"; pass=$((pass + 1))
  else
    echo "  [FAIL] 絞り込み: 反転した形を外せない（${n}件）"; fail=$((fail + 1))
  fi

  # 現行の台帳が合格すること
  if _cap="$(judge 2>&1)"; then
    echo "  [PASS] 現行: 向きを取り違えた検収は無い"; pass=$((pass + 1))
  else
    echo "  [FAIL] 現行: 向きを取り違えた検収がある"; fail=$((fail + 1))
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
  fi

  rm -rf "$tmp"
  echo "self-test: ${pass} PASS, ${fail} FAIL"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  *) judge ;;
esac
