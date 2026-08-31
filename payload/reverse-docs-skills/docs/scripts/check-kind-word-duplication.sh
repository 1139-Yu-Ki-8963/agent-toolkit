#!/usr/bin/env bash
# check-kind-word-duplication.sh — 生成した設計文書の本文で種別語が2回連続する箇所を検出する（改善課題1-293）
#
# 用途:
#   bash docs/scripts/check-kind-word-duplication.sh [<走査する起点> ...]   既定: generation-engine/samples 配下3つ
#   bash docs/scripts/check-kind-word-duplication.sh --self-test
#
# 判定:
#   見出し・表題だけでなく本文の地の文と表のセルを含む全行を走査する。
#   種別語（機能・API・テーブル・バッチ・帳票・外部連携・画面）が同じ語で2回連続する箇所が
#   1件でもあれば終了コード1。0件なら終了コード0。走査する対象が1件も無ければ理由付き
#   [UNKNOWN]・終了コード2。
#
# 実装判断:
#   走査は perl で行う。BSD grep は多バイトの文字クラスと後方参照の組み合わせをロケールに
#   よって解さず、走査が動かないまま「該当なし」を返す形になりうるため（判定不能規約の
#   「走査が動かないまま合格に見える」節）。自己テストは走査が実際に動いたことを、行番号
#   つきで該当行を返すかで確かめる。
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

scan() {
  # 引数: 走査する .md ファイルの一覧。該当行を "<path>:<line>: <一致>" で出す。
  perl -CSDA -Mutf8 -ne 'while(/(機能|API|テーブル|バッチ|帳票|外部連携|画面)\1/g){print "$ARGV:$.: $&\n"} close ARGV if eof' "$@"
}

collect() {
  local root; for root in "$@"; do
    [ -d "$root" ] && find "$root" -name '*.md' -type f
  done
}

run_check() {
  local roots=("$@")
  if [ "${#roots[@]}" -eq 0 ]; then
    roots=("${REPO_ROOT}/generation-engine/samples" "${REPO_ROOT}/generation-engine/samples-api-only" "${REPO_ROOT}/generation-engine/samples-no-screen")
  fi
  local files; files="$(collect "${roots[@]}")"
  if [ -z "$files" ]; then
    echo "[UNKNOWN] 走査する .md が1件も無いため判定できません（起点: ${roots[*]}）"
    return 2
  fi
  local hits; hits="$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 perl -CSDA -Mutf8 -ne 'while(/(機能|API|テーブル|バッチ|帳票|外部連携|画面)\1/g){print "$ARGV:$.: $&\n"} close ARGV if eof')"
  local n; n="$(printf '%s' "$hits" | grep -c . || true)"
  if [ "$n" -gt 0 ]; then
    printf '%s\n' "$hits"
    echo "[FAIL] 種別語が2回連続する箇所: ${n} 件（走査 $(printf '%s\n' "$files" | wc -l | tr -d ' ') ファイル）"
    return 1
  fi
  echo "[PASS] 種別語が2回連続する箇所: 0 件（走査 $(printf '%s\n' "$files" | wc -l | tr -d ' ') ファイル）"
  return 0
}

self_test() {
  local tmp rc=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-kind-word-dup.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktemp が一時領域へ書き込めませんでした）"
    return 2
  fi
  mkdir -p "$tmp/bad" "$tmp/good"
  printf '# 注文機能 機能設計書\n\n本書は注文機能機能詳細設計書を参照する。\n' > "$tmp/bad/a.md"
  printf '# 注文機能設計書\n\n本書は注文機能の機能詳細設計書と画面一覧を参照する。API一覧のAPIキーも参照する。\n' > "$tmp/good/a.md"
  local out
  out="$(run_check "$tmp/bad")"; local r=$?
  if [ "$r" -eq 1 ] && printf '%s' "$out" | grep -q 'a.md:3: 機能機能'; then
    echo "  [PASS] 陽性: 本文の地の文の重複を行番号つきで検出する"
  else
    echo "  [FAIL] 陽性: rc=${r} out=${out}"; rc=1
  fi
  if run_check "$tmp/good" >/dev/null; then
    echo "  [PASS] 陰性: 助詞を挟む参照・異なる種別語の連続は検出しない"
  else
    echo "  [FAIL] 陰性: 誤検出"; rc=1
  fi
  local r3=0
  _cap="$(run_check "$tmp/none" 2>&1)" || r3=$?
  if [ "$r3" -eq 2 ]; then echo "  [PASS] 対象なし: 判定不能を終了コード2で返す"; else { echo "  [FAIL] 対象なし: rc=${r3}"; printf '%s\n' "$_cap" | sed 's/^/      /' >&2; }; rc=1; fi
  rm -rf "$tmp"
  if [ "$rc" -eq 0 ]; then echo "self-test PASS"; else echo "self-test FAIL"; fi
  return "$rc"
}

case "${1:-}" in
  --self-test) self_test ;;
  *) run_check "$@" ;;
esac
