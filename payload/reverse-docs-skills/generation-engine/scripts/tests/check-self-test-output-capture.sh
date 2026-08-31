#!/usr/bin/env bash
# check-self-test-output-capture.sh — 自己テストが検査対象の出力を捨てたまま
# [FAIL] だけを報告する箇所（1-57）を列挙する。出力を捨てると失敗の理由が
# 残らず、失敗のたびに実行環境の再現が要る。
#
# 判定: >/dev/null 2>&1 で出力を捨てる行の直後3行以内に [FAIL] を含む行が
#   あるものを違反とする（検証側と同じ検出方法）。
# 対象: generation-engine/scripts・delivery-payload/templates/rules/checkers・
#   docs/scripts 配下の .sh（自分自身は除く）。
# 使い方:
#   check-self-test-output-capture.sh             実データを走査する（違反1件以上で終了コード1）
#   check-self-test-output-capture.sh --self-test 判定の妥当性を検査する
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SELF="generation-engine/scripts/tests/check-self-test-output-capture.sh"

scan() {
  local base="$1" violations=0 f rel
  while IFS= read -r f; do
    rel="${f#"$base"/}"
    [ "$rel" = "$SELF" ] && continue
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      echo "[FAIL] ${rel}:${line}"
      violations=$((violations + 1))
    done < <(awk '
      /> *\/dev\/null 2>&1/ { mark = NR }
      /\[FAIL\]/ && mark && NR - mark <= 3 && NR > mark { print mark; mark = 0 }
    ' "$f")
  done < <(find "$base/generation-engine/scripts" "$base/delivery-payload/templates/rules/checkers" "$base/docs/scripts" -type f -name '*.sh' 2>/dev/null | LC_ALL=C sort)
  echo "出力捨て違反 $violations 件"
  [ "$violations" -eq 0 ]
}

self_test() {
  local tmp pass=0 fail=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/output-capture.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした）"
    return 2
  fi
  mkdir -p "$tmp/base/docs/scripts"
  printf '%s\n' 'if ! run >/dev/null 2>&1; then' '  echo "  [FAIL] x" >&2' 'fi' > "$tmp/base/docs/scripts/a.sh"
  local out
  if out="$(scan "$tmp/base" 2>&1)"; then
    echo "[FAIL] 出力を捨てた直後のFAILを違反と判定する"; fail=$((fail + 1))
    printf '%s\n' "$out" | sed 's/^/    /' >&2
  elif printf '%s' "$out" | grep -q 'docs/scripts/a.sh:1'; then
    echo "[PASS] 出力を捨てた直後のFAILを違反と判定し行番号を示す"; pass=$((pass + 1))
  else
    echo "[FAIL] 違反は出たが行番号を示さない"; fail=$((fail + 1))
    printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
  printf '%s\n' 'if ! out="$(run 2>&1)"; then' '  echo "  [FAIL] x" >&2' '  printf "%s\n" "$out" >&2' 'fi' > "$tmp/base/docs/scripts/a.sh"
  if out="$(scan "$tmp/base" 2>&1)"; then
    echo "[PASS] 出力を受けてから報告する形は違反にしない"; pass=$((pass + 1))
  else
    echo "[FAIL] 出力を受けてから報告する形は違反にしない"; fail=$((fail + 1))
    printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
  rm -rf "$tmp"
  echo "実行 $((pass + fail)) 件 / 合格 $pass 件 / 不合格 $fail 件"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  "") scan "$REPO_ROOT"; exit $? ;;
  *) echo "使い方: $(basename "$0") [--self-test]" >&2; exit 2 ;;
esac
