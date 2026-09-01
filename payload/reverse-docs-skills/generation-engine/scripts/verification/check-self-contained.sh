#!/usr/bin/env bash
# check-self-contained.sh — 自立の判定。納品物がこのマシン固有の場所（ホーム配下・
# 絶対パス・~/Projects/ 等）へ依存していないかを走査する。
#
# 判定: 走査対象のファイル本文に、コメント行（# 始まり）を除き、/Users/ または
#   /home/ で始まる2階層以上の絶対パス、もしくは ~/ 展開のホーム参照（~/Projects/
#   を含む）が現れたら違反として数える。${HOME} 変数参照そのものは、実行時に環境へ
#   追従するため違反としない。
# 対象: 納品対象の全体（.claude/skills・delivery-payload・generation-engine の
#   .sh と .md、および README.md・RUNBOOK.md）。当初は generation-engine/scripts
#   の6ディレクトリに限っていたが、固有値の混入の全部が見ていない範囲にあった実測
#   （台帳キー: 自立検査-走査範囲不足）を受けて納品物全体へ広げた。
#
# 使い方:
#   check-self-contained.sh              実データを走査する（違反1件以上で終了コード1）
#   check-self-contained.sh --repo <パス> 走査の起点を差し替える（検証ループ用）
#   check-self-contained.sh --self-test  判定の妥当性を検査する
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

SCAN_DIRS=".claude/skills delivery-payload generation-engine"
SCAN_FILES="README.md RUNBOOK.md"

scan() {
  local base="$1" violations=0 f rel line d
  local self_rel="generation-engine/scripts/verification/check-self-contained.sh"
  local targets=()
  for d in $SCAN_DIRS; do
    [ -d "$base/$d" ] && targets+=("$base/$d")
  done
  if [ "${#targets[@]}" -eq 0 ]; then
    echo "[UNKNOWN] 走査対象のディレクトリが1件も見つからないため判定できません（base=${base}）"
    return 2
  fi
  {
    find "${targets[@]}" -type f \( -name '*.sh' -o -name '*.md' \) 2>/dev/null
    for f in $SCAN_FILES; do
      [ -f "$base/$f" ] && printf '%s\n' "$base/$f"
    done
  } | LC_ALL=C sort -u | while IFS= read -r f; do
    rel="${f#"$base"/}"
    [ "$rel" = "$self_rel" ] && continue
    awk -v rel="$rel" '
      /^[[:space:]]*#/ { next }
      /(^|["=[:space:](])\/Users\/[A-Za-z0-9_.-]+\// || /(^|["=[:space:](])\/home\/[A-Za-z0-9_.-]+\// || /(^|["'"'"'=[:space:](`])~\// { print "[FAIL] " rel ":" NR }
    ' "$f"
  done > "${TMPDIR:-/tmp}/.self-contained-hits.$$" || true
  violations="$(grep -c '^\[FAIL\]' "${TMPDIR:-/tmp}/.self-contained-hits.$$" 2>/dev/null | head -1)"
  : "${violations:=0}"
  cat "${TMPDIR:-/tmp}/.self-contained-hits.$$"
  rm -f "${TMPDIR:-/tmp}/.self-contained-hits.$$"
  if [ "$violations" -eq 0 ]; then
    echo "[PASS] 自立: マシン固有パスへの依存なし"
  fi
  echo "自立違反 $violations 件"
  [ "$violations" -eq 0 ]
}

self_test() {
  local tmp pass=0 fail=0 out
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/self-contained.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした）"
    return 2
  fi
  mkdir -p "$tmp/base/delivery-payload"
  printf '%s\n' '#!/usr/bin/env bash' 'cp /Users/somebody/data.txt ./out' > "$tmp/base/delivery-payload/a.sh"
  if out="$(scan "$tmp/base" 2>&1)"; then
    echo "  [FAIL] ホーム配下の絶対パスを違反と判定する"; fail=$((fail + 1))
    printf '%s\n' "$out" | sed 's/^/    /' >&2
  elif printf '%s' "$out" | grep -q 'a.sh:2'; then
    echo "  [PASS] ホーム配下の絶対パスを違反と判定し行番号を示す"; pass=$((pass + 1))
  else
    echo "  [FAIL] 違反は出たが行番号を示さない"; fail=$((fail + 1))
    printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
  printf '%s\n' '手順は ~/Projects/example で行う' > "$tmp/base/README.md"
  printf '%s\n' '#!/usr/bin/env bash' 'echo ok' > "$tmp/base/delivery-payload/a.sh"
  if out="$(scan "$tmp/base" 2>&1)"; then
    echo "  [FAIL] README の ~/Projects/ 参照を違反と判定する"; fail=$((fail + 1))
    printf '%s\n' "$out" | sed 's/^/    /' >&2
  elif printf '%s' "$out" | grep -q 'README.md:1'; then
    echo "  [PASS] README の ~/Projects/ 参照を違反と判定する"; pass=$((pass + 1))
  else
    echo "  [FAIL] 違反は出たが場所を示さない"; fail=$((fail + 1))
    printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
  rm -f "$tmp/base/README.md"
  printf '%s\n' '#!/usr/bin/env bash' '# コメントの /Users/example は違反にしない' 'echo "${HOME}/ok"' > "$tmp/base/delivery-payload/a.sh"
  if out="$(scan "$tmp/base" 2>&1)"; then
    echo "  [PASS] コメントと \${HOME} 参照は違反にしない"; pass=$((pass + 1))
  else
    echo "  [FAIL] コメントと \${HOME} 参照は違反にしない"; fail=$((fail + 1))
    printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
  rm -rf "$tmp"
  echo "実行 $((pass + fail)) 件 / 合格 $pass 件 / 不合格 $fail 件"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  --repo)
    [ -n "${2:-}" ] || { echo "使い方: $(basename "$0") [--self-test|--repo <パス>]" >&2; exit 2; }
    scan "$2"; exit $?
    ;;
  "") scan "$REPO_ROOT"; exit $? ;;
  *) echo "使い方: $(basename "$0") [--self-test|--repo <パス>]" >&2; exit 2 ;;
esac
