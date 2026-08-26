#!/usr/bin/env bash
# check-portal-rule-exclusions.sh — ポータル規約が除外する場所の実在を検査する
#
# 何を見るか:
#   .claude/rules/scoped/portal/page-conventions/rule.md の「## 適用対象」節に
#   逆引用符で書かれた場所のうち、リポジトリ内のパスに見えるものが実在するかを見る。
#   `*` を含む書き方も対象にし、1 件でも当たれば実在と判定する。
#
# なぜ要るか:
#   除外の記述は「そこに何かがある」ことを前提にしている。
#   何も無い場所を除外しても効果は無く、読み手には
#   「あるはずのものが無い」のか「除外が古い」のかが判別できない。
#   実際に、存在しないフォルダを除外したまま残っていた。
#   設計判断は同 rule.md の「## 設計判断」内
#   「### check-portal-rule-exclusions.sh」に置く。
#
# 使い方:
#   check-portal-rule-exclusions.sh             規約を走査する
#   check-portal-rule-exclusions.sh --self-test 判定の妥当性を検査する
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

RULE_REL='.claude/rules/scoped/portal/page-conventions/rule.md'

# 「## 適用対象」節に書かれたリポジトリ内のパスを取り出す。
extract_paths() {
  local rule="$1"
  awk '/^## 適用対象/{f=1; next} /^## /{f=0} f' "$rule" \
    | grep -oE '`[^`]+`' \
    | tr -d '`' \
    | grep -E '^(\.claude|docs|delivery-payload|generation-engine)/' \
    | sed -E 's/:[0-9]+(-[0-9]+)?$//' \
    | grep -v ':' \
    | sed -E 's#/+$##' \
    | LC_ALL=C sort -u
}

scan() {
  local base="$1"
  local rule="$base/$RULE_REL"
  local total=0 missing=0 p
  if [ ! -f "$rule" ]; then
    echo "走査 0 件 / 不在 0 件"
    return 0
  fi
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    total=$((total + 1))
    local match_out
    if ! match_out="$(cd "$base" && compgen -G "$p" 2>&1)"; then
      echo "[FAIL] 除外に書かれた場所が実在しない: $p"
      printf '%s\n' "$match_out" | sed 's/^/    /'
      missing=$((missing + 1))
    fi
  done < <(extract_paths "$rule")
  echo "走査 $total 件 / 不在 $missing 件"
  [ "$missing" -eq 0 ]
}

self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/portal-rule-exclusions.XXXXXX" 2>/dev/null)" || tmp=""
  if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
    echo "[FAIL] 一時ディレクトリを作れないため自己検査を実行できない"
    echo "実行 1 件 / 合格 0 件 / 不合格 1 件"
    return 1
  fi

  local base="$tmp/base"
  local ruledir="$base/.claude/rules/scoped/portal/page-conventions"
  mkdir -p "$ruledir" "$base/docs" "$base/.claude/skills/a/references"
  : > "$base/docs/present.html"
  : > "$base/.claude/skills/a/references/guide.html"

  printf '%s\n' '## 適用対象' '`docs/present.html` は対象から外す。' '`*.html` は対象である。' '## カラーシステム' > "$ruledir/rule.md"
  if _gt_out1="$(scan "$base" 2>&1)"; then
    echo "[PASS] 実在する除外先だけの規約を合格と判定する"; pass=$((pass + 1))
  else
    echo "[FAIL] 実在する除外先だけの規約を合格と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out1" | sed 's/^/    /' >&2
  fi

  printf '%s\n' '## 適用対象' '`.claude/skills/*/references/guide.html` は対象から外す。' '## カラーシステム' > "$ruledir/rule.md"
  if _gt_out2="$(scan "$base" 2>&1)"; then
    echo "[PASS] 星印を含む書き方を1件でも当たれば実在と判定する"; pass=$((pass + 1))
  else
    echo "[FAIL] 星印を含む書き方を1件でも当たれば実在と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out2" | sed 's/^/    /' >&2
  fi

  printf '%s\n' '## 適用対象' '`docs/absent.html` は対象から外す。' '## カラーシステム' > "$ruledir/rule.md"
  if _gt_out3="$(scan "$base" 2>&1)"; then
    echo "[FAIL] 不在の除外先を不合格と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out3" | sed 's/^/    /' >&2
  else
    echo "[PASS] 不在の除外先を不合格と判定する"; pass=$((pass + 1))
  fi

  printf '%s\n' '## 適用対象' '`docs/present.html` は対象から外す。' '## カラーシステム' '`docs/absent.html` は別の節の記述である。' > "$ruledir/rule.md"
  if _gt_out4="$(scan "$base" 2>&1)"; then
    echo "[PASS] 適用対象の節の外は見ない"; pass=$((pass + 1))
  else
    echo "[FAIL] 適用対象の節の外は見ない"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out4" | sed 's/^/    /' >&2
  fi

  if _gt_out5="$(scan "$tmp/none" 2>&1)"; then
    echo "[PASS] 規約が無い場合は合格と判定する"; pass=$((pass + 1))
  else
    echo "[FAIL] 規約が無い場合は合格と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out5" | sed 's/^/    /' >&2
  fi

  printf '%s\n' '## 適用対象' '`docs/present.html:36` は対象から外す。' '## カラーシステム' > "$ruledir/rule.md"
  if _gt_out6="$(scan "$base" 2>&1)"; then
    echo "[PASS] 実在する除外先に添えた行番号を無視して合格と判定する"; pass=$((pass + 1))
  else
    echo "[FAIL] 実在する除外先に添えた行番号を無視して合格と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out6" | sed 's/^/    /' >&2
  fi

  printf '%s\n' '## 適用対象' '`docs/present.html:36-42` は対象から外す。' '## カラーシステム' > "$ruledir/rule.md"
  if _gt_out7="$(scan "$base" 2>&1)"; then
    echo "[PASS] 実在する除外先に添えた行範囲を無視して合格と判定する"; pass=$((pass + 1))
  else
    echo "[FAIL] 実在する除外先に添えた行範囲を無視して合格と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out7" | sed 's/^/    /' >&2
  fi

  printf '%s\n' '## 適用対象' '`docs/absent.html:36-42` は対象から外す。' '## カラーシステム' > "$ruledir/rule.md"
  if _gt_out8="$(scan "$base" 2>&1)"; then
    echo "[FAIL] 不在の除外先に添えた行範囲を不合格と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out8" | sed 's/^/    /' >&2
  else
    echo "[PASS] 不在の除外先に添えた行範囲を不合格と判定する"; pass=$((pass + 1))
  fi

  printf '%s\n' '## 適用対象' '`docs/present.html:reference` は対象から外す。' '## カラーシステム' > "$ruledir/rule.md"
  if _gt_out9="$(scan "$base" 2>&1)"; then
    echo "[PASS] 行番号ではないコロンを含む記述を候補外と判定する"; pass=$((pass + 1))
  else
    echo "[FAIL] 行番号ではないコロンを含む記述を候補外と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out9" | sed 's/^/    /' >&2
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
    scan "$REPO_ROOT"
    exit $?
    ;;
  *)
    echo "使い方: $(basename "$0") [--self-test]" >&2
    exit 2
    ;;
esac
