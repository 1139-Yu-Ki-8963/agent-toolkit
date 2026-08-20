#!/usr/bin/env bash
# check-delivery-doc-links.sh — 納品対象が、配られない docs/ を指していないか検査する
#
# 何を見るか:
#   納品対象 7 件（.claude/skills・delivery-payload・generation-engine・
#   .claude/rules/scoped/portal/page-conventions/rule.md・
#   .claude/rules/always/verification/reverse-verification/rule.md・
#   README.md・RUNBOOK.md）配下の *.md と *.html を対象にする。
#   本文中の「リンクの形で書かれた参照」だけを見る。
#     1. Markdown のリンク: ](パス)
#     2. HTML のリンク: href="パス"
#   どちらも、パスに docs/ を含むものだけを候補にする。
#
# 何を違反とするか:
#   候補のパスを、そのファイルのあるディレクトリからの相対として解決する。
#   解決した先がこのリポジトリのルート直下の docs/ の配下になり、
#   かつ実在する場合だけを違反とする。
#
# 見逃す設計にしていること（意図的）:
#   納品先のプロジェクト内に生成される docs/（例: generation-engine/samples/ 配下の
#   出力に現れる docs/design/screens/... 等）は、そのファイルから相対で解決しても
#   このリポジトリのルート直下の docs/ には到達しない（別の階層の docs/ を指す）。
#   そのため本検査の定義では違反にならない。これは意図した設計であり、
#   検査漏れではない。
#
# なぜ要るか:
#   設計判断は .claude/rules/scoped/portal/page-conventions/rule.md の
#   「## 設計判断」内「### check-delivery-doc-links.sh」に置く。
#
# 使い方:
#   check-delivery-doc-links.sh             納品対象 7 件を走査する
#   check-delivery-doc-links.sh --self-test  判定の妥当性を検査する
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

TARGETS=(
  ".claude/skills"
  "delivery-payload"
  "generation-engine"
  ".claude/rules/scoped/portal/page-conventions/rule.md"
  ".claude/rules/always/verification/reverse-verification/rule.md"
  "README.md"
  "RUNBOOK.md"
)

MD_RE='\][(][^)]*docs/[^)]*[)]'
HREF_RE='href="[^"]*docs/[^"]*"'

# 納品対象 7 件配下の *.md / *.html を列挙する。
collect_files() {
  local base="$1" t p
  for t in "${TARGETS[@]}"; do
    p="$base/$t"
    if [ -d "$p" ]; then
      find "$p" -type f \( -name '*.md' -o -name '*.html' \) 2>/dev/null
    elif [ -f "$p" ]; then
      case "$t" in
        *.md|*.html) echo "$p" ;;
      esac
    fi
  done
}

# 1 ファイルから候補パス（docs/ を含むリンク先）を抜き出す。
extract_candidates() {
  local f="$1"
  {
    grep -oE "$MD_RE" "$f" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//'
    grep -oE "$HREF_RE" "$f" 2>/dev/null | sed -E 's/^href="//; s/"$//'
  } | LC_ALL=C sort -u
}

scan() {
  local base="$1"
  local repo_docs=""
  if [ -d "$base/docs" ]; then
    repo_docs="$(cd "$base" && realpath "docs" 2>/dev/null)" || repo_docs=""
  fi

  local total=0 violations=0 f d p anchor resolved
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    d="$(dirname "$f")"
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      total=$((total + 1))
      anchor="${p%%#*}"
      anchor="${anchor%%\?*}"
      [ -z "$anchor" ] && continue
      resolved="$(cd "$d" 2>/dev/null && realpath "$anchor" 2>/dev/null)" || resolved=""
      [ -z "$resolved" ] && continue
      if [ -n "$repo_docs" ]; then
        case "$resolved" in
          "$repo_docs"/*)
            echo "[FAIL] $f -> $p"
            violations=$((violations + 1))
            ;;
        esac
      fi
    done < <(extract_candidates "$f")
  done < <(collect_files "$base" | LC_ALL=C sort -u)

  echo "走査 $total 件 / 違反 $violations 件"
  [ "$violations" -eq 0 ]
}

self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/delivery-doc-links.XXXXXX" 2>/dev/null)" || tmp=""
  if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
    echo "[FAIL] 一時ディレクトリを作れないため自己検査を実行できない"
    echo "実行 1 件 / 合格 0 件 / 不合格 1 件"
    return 1
  fi

  local base="$tmp/base"

  # ケース1: リポジトリの docs を指すリンクを違反と判定する
  mkdir -p "$base/docs" "$base/README.md.d"
  : > "$base/docs/plan.md"
  printf '%s\n' '参照: [計画](docs/plan.md)' > "$base/README.md"
  if scan "$base" >/dev/null 2>&1; then
    echo "[FAIL] リポジトリの docs を指すリンクを違反と判定する"; fail=$((fail + 1))
  else
    echo "[PASS] リポジトリの docs を指すリンクを違反と判定する"; pass=$((pass + 1))
  fi
  rm -rf "$base"

  # ケース2: 納品先の生成物の docs（別の場所へ解決される docs）を違反にしない
  mkdir -p "$base/generation-engine/samples/project-portal" "$base/generation-engine/samples/docs/design"
  : > "$base/generation-engine/samples/docs/design/detail.md"
  printf '%s\n' 'href="../docs/design/detail.md"' > "$base/generation-engine/samples/project-portal/page.html"
  if scan "$base" >/dev/null 2>&1; then
    echo "[PASS] 納品先の生成物の docs は違反にしない"; pass=$((pass + 1))
  else
    echo "[FAIL] 納品先の生成物の docs は違反にしない"; fail=$((fail + 1))
  fi
  rm -rf "$base"

  # ケース3: リンクの形でない、ただの文中のパスの記載は違反にしない
  mkdir -p "$base/docs"
  : > "$base/docs/plan.md"
  printf '%s\n' 'docs/plan.md は文中にそのまま書いてあるだけ（リンクではない）' > "$base/README.md"
  if scan "$base" >/dev/null 2>&1; then
    echo "[PASS] リンクの形でない文中のパス記載は違反にしない"; pass=$((pass + 1))
  else
    echo "[FAIL] リンクの形でない文中のパス記載は違反にしない"; fail=$((fail + 1))
  fi
  rm -rf "$base"

  # ケース4: 対象が1件も無い場合は合格と判定する
  mkdir -p "$base"
  if scan "$base" >/dev/null 2>&1; then
    echo "[PASS] 対象が1件も無い場合は合格と判定する"; pass=$((pass + 1))
  else
    echo "[FAIL] 対象が1件も無い場合は合格と判定する"; fail=$((fail + 1))
  fi
  rm -rf "$base"

  rm -rf "$tmp"
  echo "実行 $((pass + fail)) 件 / 合格 $pass 件 / 不合格 $fail 件"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test)
    self_test
    exit $?
    ;;
  "")
    scan "$REPO_ROOT"
    exit $?
    ;;
  *)
    echo "使い方: $(basename "$0") [--self-test]" >&2
    exit 2
    ;;
esac
