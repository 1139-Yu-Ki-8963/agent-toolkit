#!/usr/bin/env bash
# check-adjacent-tables.sh — 空行だけを挟んで別の表が始まる箇所が無いことを見る（改善課題1-300）
#
# 版面のパーサは表を閉じる条件を持つが、生成側が表と表の間に閉じる要素（見出し・段落）を
# 置かないと、後ろの表の見出し行が前の表の行として吸収される。様式と見本の Markdown を走査し、
# パイプで始まる行の直前に空行だけを挟んで別の表が始まる箇所を列挙する。1件でもあれば終了コード1。
#
# 使い方:
#   check-adjacent-tables.sh [<起点ディレクトリ>...]   既定: delivery-payload/templates generation-engine/samples generation-engine/samples-api-only
#   check-adjacent-tables.sh --self-test
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

scan_file() {
  # 表の行の直後に空行、その直後に再び表の行が来る箇所を報告する
  awk -v F="$1" '
    { line = $0 }
    prev_table && line == "" { blank = 1; prev_table = 0; next }
    blank && index(line, "|") == 1 { print F ": " NR; blank = 0; prev_table = 1; next }
    { blank = 0 }
    { prev_table = (index(line, "|") == 1) }
  ' "$1"
}

run_check() {
  local hits=0 f
  for root in "$@"; do
    while IFS= read -r f; do
      out="$(scan_file "$f")"
      if [ -n "$out" ]; then printf '%s\n' "$out"; hits=$((hits + $(printf '%s\n' "$out" | grep -c .))); fi
    done < <(find "$root" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
  done
  if [ "$hits" -gt 0 ]; then echo "[FAIL] 空行だけを挟んで続く表が ${hits} 件あります"; return 1; fi
  echo "[PASS] 空行だけを挟んで続く表はありません"
}

self_test() {
  local tmp pass=0 fail=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-adjacent-tables.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため自己テストを判定できません（mktemp が一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/bad" "$tmp/good"
  printf '| a | b |\n|---|---|\n| 1 | 2 |\n\n| c | d |\n|---|---|\n' > "$tmp/bad/x.md"
  printf '| a | b |\n|---|---|\n| 1 | 2 |\n\n説明の段落。\n\n| c | d |\n|---|---|\n' > "$tmp/good/y.md"
  if _cap="$(run_check "$tmp/bad" 2>&1)"; then { echo "  [FAIL] 陽性: 空行だけで続く表を検出しない"; printf '%s\n' "$_cap" | sed 's/^/      /' >&2; }; fail=$((fail+1)); else echo "  [PASS] 陽性: 空行だけで続く表を検出する"; pass=$((pass+1)); fi
  if out="$(run_check "$tmp/bad" 2>&1)" || true; printf '%s' "$out" | grep -q 'x.md: 5'; then echo "  [PASS] 走査: 行番号つきで該当行を返す"; pass=$((pass+1)); else echo "  [FAIL] 走査: 該当行を返さない"; fail=$((fail+1)); fi
  if _cap="$(run_check "$tmp/good" 2>&1)"; then echo "  [PASS] 陰性: 段落で区切った表は通る"; pass=$((pass+1)); else { echo "  [FAIL] 陰性: 段落で区切った表を誤検出する"; printf '%s\n' "$_cap" | sed 's/^/      /' >&2; }; fail=$((fail+1)); fi
  echo "self-test: ${pass} PASS, ${fail} FAIL"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  '') run_check "$REPO_ROOT/delivery-payload/templates" "$REPO_ROOT/generation-engine/samples" "$REPO_ROOT/generation-engine/samples-api-only" ;;
  *) run_check "$@" ;;
esac
