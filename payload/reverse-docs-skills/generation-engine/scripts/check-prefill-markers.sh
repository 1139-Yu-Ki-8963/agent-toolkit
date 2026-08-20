#!/usr/bin/env bash
set -euo pipefail

# check-prefill-markers.sh — 『著述・未確認』マーカーの残存検査
#
# 使い方:
#   check-prefill-markers.sh <設計書ファイルまたはディレクトリ>
#   check-prefill-markers.sh --self-test
#
# prefill-design-from-facts.sh（facts.ymlからの機械転記）が挿入する
# 『【著述・未確認:<章番号>-<種別>】』マーカーの残存を検査する完全性ゲート。
# 残存が0件ならexit 0、1件以上残っていればexit 1（該当箇所をstderrへ出力。fail-closed）。
# generating-reverse-detailed-design の Phase 5 完全性ゲートに、prefill-design-from-facts.sh
# を使った場合の追加検査として組み込む（SKILL.md参照）。
#
# 保守責任者: 人手（ユーザー）。prefill-design-from-facts.sh のマーカー書式（mk_marker関数）を
# 変更した時に本スクリプトの検査パターンも追従させる。
# macOS bash 3.2 互換。

MARKER_PATTERN='【著述・未確認'

check_target() { # $1=対象ファイルまたはディレクトリ
  local target="$1"
  local hits
  if [ -d "$target" ]; then
    hits="$(grep -rn "$MARKER_PATTERN" "$target" 2>/dev/null || true)"
  elif [ -f "$target" ]; then
    hits="$(grep -n "$MARKER_PATTERN" "$target" 2>/dev/null || true)"
  else
    echo "エラー: 対象が見つかりません: $target" >&2
    return 2
  fi
  if [ -n "$hits" ]; then
    echo "残存マーカー検出:" >&2
    printf '%s\n' "$hits" | sed 's/^/  /' >&2
    return 1
  fi
  return 0
}

self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-prefill-markers-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  local rc=0

  local with_marker="$tmp/with-marker.md"
  printf '# タイトル\n\n| 変数名 | 型 |\n|---|---|\n| rows | 【著述・未確認:5-型】 |\n' > "$with_marker"
  if check_target "$with_marker" >/dev/null 2>&1; then
    echo "  [FAIL] マーカー残存時にexit 0で通過してしまった" >&2
    rc=1
  else
    echo "  [PASS] マーカー残存時にexit 1で検出"
  fi

  local without_marker="$tmp/without-marker.md"
  printf '# タイトル\n\n| 変数名 | 型 |\n|---|---|\n| rows | RowType[] |\n' > "$without_marker"
  if check_target "$without_marker" >/dev/null 2>&1; then
    echo "  [PASS] マーカー全置換後にexit 0で通過"
  else
    echo "  [FAIL] マーカーが無いのにexit 1になった" >&2
    rc=1
  fi

  # ディレクトリ指定でも再帰的に検出できること
  local dir="$tmp/dir"
  mkdir -p "$dir/sub"
  cp "$with_marker" "$dir/sub/design.md"
  if check_target "$dir" >/dev/null 2>&1; then
    echo "  [FAIL] ディレクトリ指定でマーカー残存を検出できなかった" >&2
    rc=1
  else
    echo "  [PASS] ディレクトリ指定でマーカー残存を検出できた"
  fi

  # 対象が存在しない場合はexit 2
  if check_target "$tmp/does-not-exist.md" >/dev/null 2>&1; then
    echo "  [FAIL] 対象不在なのにexit 0になった" >&2
    rc=1
  else
    missing_rc=$?
    if [ "$missing_rc" = "2" ]; then
      echo "  [PASS] 対象不在でexit 2"
    else
      echo "  [FAIL] 対象不在時のexitコードが2でない（実測=${missing_rc}）" >&2
      rc=1
    fi
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

target="${1:?使い方: check-prefill-markers.sh <設計書ファイルまたはディレクトリ> ／ check-prefill-markers.sh --self-test}"
check_target "$target"
exit $?
