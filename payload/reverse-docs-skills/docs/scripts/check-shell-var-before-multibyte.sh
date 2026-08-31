#!/usr/bin/env bash
# シェルスクリプトで、変数展開の直後に全角文字が来る形を見つける。
#
# なぜ要るか: bash は変数名を英数字とアンダースコアで区切るが、macOS の bash 3.2 は
#   直後に続く全角文字を変数名の一部として飲み込む。実測（2026-08-28）で、
#   全角の丸括弧で囲んだ中の裸の変数展開が、閉じ括弧まで名前に取り込まれた。
#   set -u の下では「unbound variable」でスクリプトが止まり、
#   set -u が無い場合は値が欠けたうえ閉じ括弧のバイトが壊れて出力された。
#
#   この形は実際に31ファイル・49箇所に潜んでいた。うち1件は
#   check-payload-layer1.sh の実行を止めており、残りは値の欠けた報告を出していた。
#   直し方は波括弧で囲むだけである。
#
# 実装判断（走査に perl を使い grep を使わない）: BSD grep の -E は
#   16進のエスケープを解さず、UTF-8 のロケールの下で
#   「invalid character range」を返して終了コード2で止まる。実測（2026-08-28）で、
#   同じパターンを grep へ渡すと走査そのものが行われないまま「該当なし」に見えた。
#   perl は多バイトを正しく扱い、ロケールに左右されない。
#   perl を複数ファイルへ一度に当てると行番号が積み上がるため、
#   ファイルごとに1回ずつ呼ぶ。
#
# 使い方:
#   bash docs/scripts/check-shell-var-before-multibyte.sh [対象ディレクトリ...]
#   bash docs/scripts/check-shell-var-before-multibyte.sh --self-test
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SELF_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

scan() {
  local root="$1" f
  [ -d "$root" ] || return 0
  while IFS= read -r f; do
    # 自分自身は説明とフィクスチャに検出対象の形を持つため走査から外す。
    [ "$(cd "$(dirname "$f")" && pwd -P)/$(basename "$f")" = "$SELF_PATH" ] && continue
    perl -CSD -ne 'print "$ARGV:$.:$_" if /\$[A-Za-z_]\w*(?=[^\x00-\x7F])/' "$f" 2>/dev/null
  done < <(find "$root" -name '*.sh' -type f 2>/dev/null | sort)
}

judge() {
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
    out="$(scan "$r")"
    [ -n "$out" ] && hits="${hits}${out}"$'\n'
  done
  hits="$(printf '%s' "$hits" | sed '/^$/d')"

  if [ -n "$hits" ]; then
    local n
    n="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
    echo "[FAIL] 変数展開の直後に全角文字が来る形が ${n} 件あります。波括弧で囲んでください。"
    printf '%s\n' "$hits" | head -20
    return 1
  fi

  echo "[PASS] 変数展開の直後に全角文字が来る形はありません。"
  return 0
}

self_test() {
  local pass=0 fail=0 tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/varmb.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時領域を作れないため判定できません（mktempが書き込めませんでした）"
    exit 2
  fi

  mkdir -p "$tmp/bad" "$tmp/good" "$tmp/ascii"
  printf '#!/usr/bin/env bash\nV=7\necho "（exit $V）"\n' > "$tmp/bad/probe.sh"
  printf '#!/usr/bin/env bash\nV=7\necho "（exit ${V}）"\n' > "$tmp/good/probe.sh"
  printf '#!/usr/bin/env bash\nV=7\necho "(exit $V)"\n' > "$tmp/ascii/probe.sh"

  if _cap="$(judge "$tmp/bad" 2>&1)"; then
    echo "  [FAIL] 陽性: 裸の変数展開を検出できない"; fail=$((fail + 1))
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
  else
    echo "  [PASS] 陽性: 裸の変数展開を検出する"; pass=$((pass + 1))
  fi

  if _cap="$(judge "$tmp/good" 2>&1)"; then
    echo "  [PASS] 陰性: 波括弧で囲んだ形は検出しない"; pass=$((pass + 1))
  else
    echo "  [FAIL] 陰性: 波括弧で囲んだ形を誤検出する"; fail=$((fail + 1))
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
  fi

  if _cap="$(judge "$tmp/ascii" 2>&1)"; then
    echo "  [PASS] 陰性: 直後が半角なら検出しない"; pass=$((pass + 1))
  else
    echo "  [FAIL] 陰性: 直後が半角の形を誤検出する"; fail=$((fail + 1))
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
  fi

  # 走査が実際に行われたことを確かめる。走査そのものが失敗して
  # 「該当なし」に見える事故（BSD grep の invalid character range）を防ぐ。
  local probe_out
  probe_out="$(scan "$tmp/bad")"
  if printf '%s' "$probe_out" | grep -q 'probe.sh:3:'; then
    echo "  [PASS] 走査: 行番号つきで該当行を返す"; pass=$((pass + 1))
  else
    echo "  [FAIL] 走査: 該当行を返さない（走査そのものが動いていない疑い）"; fail=$((fail + 1))
  fi

  if _cap="$(judge 2>&1)"; then
    echo "  [PASS] 現行: 走査対象に該当なし"; pass=$((pass + 1))
  else
    echo "  [FAIL] 現行: 走査対象に該当あり"; fail=$((fail + 1))
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
  fi

  rm -rf "$tmp"
  echo "self-test: ${pass} PASS, ${fail} FAIL"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  *) judge "$@" ;;
esac
