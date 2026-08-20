#!/usr/bin/env bash
# check-self-portal-links.sh — このリポジトリ自身のポータル（docs/portal/index.html）の
# リンク切れを検査する
#
# 何を見るか:
#   docs/portal/index.html（既定。引数で別ページを指定できる）の中の href="..." を
#   すべて取り出す。
#
# 何を違反とするか:
#   href の値を、ページのある場所からの相対パスとして解決する。解決した先が
#   実在しなければ違反とする。
#
# 対象外にすること（意図的）:
#   外部への参照（http:// / https:// で始まるもの）と、ページ内アンカーのみの
#   参照（# で始まるもの）は対象外にする。値の末尾に付く # 以降のフラグメント
#   （例: href="a.html#section"）は、実在確認の前に切り落として解決する。
#
# 使い方:
#   check-self-portal-links.sh [<検査対象のHTML>]   既定は docs/portal/index.html
#   check-self-portal-links.sh --self-test          判定の妥当性を検査する
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEFAULT_TARGET="$REPO_ROOT/docs/portal/index.html"

HREF_RE='href="[^"]*"'

# 1 ページから href の値だけを抜き出す。
extract_hrefs() {
  local page="$1"
  grep -oE "$HREF_RE" "$page" 2>/dev/null | sed -E 's/^href="//; s/"$//'
}

# 対象外（外部参照・ページ内アンカーのみ）と判定する。
is_excluded() {
  case "$1" in
    http://*|https://*|\#*) return 0 ;;
    *) return 1 ;;
  esac
}

scan() {
  local page="$1"
  if [ ! -f "$page" ]; then
    echo "ERROR: 検査対象が存在しません: $page" >&2
    return 2
  fi
  local dir total=0 broken=0 href anchor resolved
  dir="$(dirname "$page")"
  while IFS= read -r href; do
    [ -z "$href" ] && continue
    is_excluded "$href" && continue
    total=$((total + 1))
    anchor="${href%%#*}"
    if [ -z "$anchor" ]; then
      echo "[FAIL] $href"
      broken=$((broken + 1))
      continue
    fi
    resolved="$(cd "$dir" 2>/dev/null && realpath "$anchor" 2>/dev/null)" || resolved=""
    if [ -z "$resolved" ] || [ ! -e "$resolved" ]; then
      echo "[FAIL] $href"
      broken=$((broken + 1))
    fi
  done < <(extract_hrefs "$page")

  echo "検査 $total 件 / 切れ $broken 件"
  [ "$broken" -eq 0 ]
}

self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/self-portal-links.XXXXXX" 2>/dev/null)" || tmp=""
  if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
    echo "[FAIL] 一時ディレクトリを作れないため自己検査を実行できない"
    echo "実行 1 件 / 合格 0 件 / 不合格 1 件"
    return 1
  fi

  local page="$tmp/index.html"

  # ケース1: すべてのリンクが実在する場合は合格と判定する
  mkdir -p "$tmp/design"
  : > "$tmp/design/target.md"
  printf '<a href="design/target.md">対象</a>\n' > "$page"
  if scan "$page" >/dev/null 2>&1; then
    echo "[PASS] すべてのリンクが実在する場合は合格と判定する"; pass=$((pass + 1))
  else
    echo "[FAIL] すべてのリンクが実在する場合は合格と判定する"; fail=$((fail + 1))
  fi
  rm -f "$page"

  # ケース2: 実在しないリンク先を切れとして検出し不合格にする
  printf '<a href="design/missing.md">存在しない</a>\n' > "$page"
  if scan "$page" >/dev/null 2>&1; then
    echo "[FAIL] 実在しないリンク先を切れとして検出し不合格にする"; fail=$((fail + 1))
  else
    echo "[PASS] 実在しないリンク先を切れとして検出し不合格にする"; pass=$((pass + 1))
  fi
  rm -f "$page"

  # ケース3: 外部参照とページ内アンカーのみの参照は対象外にする
  printf '<a href="https://example.com/x">外部</a>\n<a href="#top">アンカー</a>\n' > "$page"
  if scan "$page" >/dev/null 2>&1; then
    echo "[PASS] 外部参照とページ内アンカーのみの参照は対象外にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 外部参照とページ内アンカーのみの参照は対象外にする"; fail=$((fail + 1))
  fi
  rm -f "$page"

  # ケース4: フラグメント付きリンク（path#anchor）は実在確認の前に切り落として解決する
  printf '<a href="design/target.md#section">対象+アンカー</a>\n' > "$page"
  if scan "$page" >/dev/null 2>&1; then
    echo "[PASS] フラグメント付きリンクは実在確認の前に切り落として解決する"; pass=$((pass + 1))
  else
    echo "[FAIL] フラグメント付きリンクは実在確認の前に切り落として解決する"; fail=$((fail + 1))
  fi
  rm -f "$page"

  # ケース5: 検査対象のページ自体が存在しない場合は異常終了として扱う
  rm -f "$tmp/no-such-page.html"
  if scan "$tmp/no-such-page.html" >/dev/null 2>&1; then
    echo "[FAIL] 検査対象のページ自体が存在しない場合は異常終了として扱う"; fail=$((fail + 1))
  else
    echo "[PASS] 検査対象のページ自体が存在しない場合は異常終了として扱う"; pass=$((pass + 1))
  fi

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
    scan "$DEFAULT_TARGET"
    exit $?
    ;;
  *)
    scan "$1"
    exit $?
    ;;
esac
