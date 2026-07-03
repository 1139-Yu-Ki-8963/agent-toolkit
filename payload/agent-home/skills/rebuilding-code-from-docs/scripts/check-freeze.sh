#!/usr/bin/env bash
# check-freeze.sh — Phase 9 の凍結検証
#
# 用途: Phase 6 で確定した凍結コミットハッシュ以降、reverse-code worktree に
#   一切の変更が加えられていないことを検証する。Phase 7〜8 は「コード修正禁止」
#   フェーズであり、本スクリプトはその事後機械検証を担う。
#
# 引数:
#   $1 = reverse-code worktree パス
#   $2 = 凍結コミットハッシュ（Phase 6 で確定したもの）
#
# 検査:
#   (1) HEAD が $2 と一致する
#   (2) `git status --porcelain` が空（作業ツリーの汚染なし）
#
# 終了コード: PASS = 0 / 違反 = 1（違反内容は stderr）
#
# 使い方:
#   ./check-freeze.sh <reverse-code worktree パス> <凍結コミットハッシュ>

set -euo pipefail

WORKTREE_PATH="${1:-}"
FROZEN_HASH="${2:-}"

if [ -z "$WORKTREE_PATH" ] || [ -z "$FROZEN_HASH" ]; then
  echo "使い方: $0 <reverse-code worktree パス> <凍結コミットハッシュ>" >&2
  exit 1
fi

if [ ! -d "$WORKTREE_PATH" ]; then
  echo "エラー: worktree パスが存在しません: $WORKTREE_PATH" >&2
  exit 1
fi

if ! git -C "$WORKTREE_PATH" rev-parse --git-dir >/dev/null 2>&1; then
  echo "エラー: git リポジトリではありません: $WORKTREE_PATH" >&2
  exit 1
fi

VIOLATIONS=0

CURRENT_HEAD="$(git -C "$WORKTREE_PATH" rev-parse HEAD)"
FROZEN_HEAD_FULL="$(git -C "$WORKTREE_PATH" rev-parse "$FROZEN_HASH" 2>/dev/null || true)"

if [ -z "$FROZEN_HEAD_FULL" ]; then
  echo "違反: 凍結コミットハッシュが解決できません: $FROZEN_HASH" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
elif [ "$CURRENT_HEAD" != "$FROZEN_HEAD_FULL" ]; then
  echo "違反: HEAD が凍結コミットと一致しません" >&2
  echo "  現在の HEAD : $CURRENT_HEAD" >&2
  echo "  凍結コミット: $FROZEN_HEAD_FULL ($FROZEN_HASH)" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo "OK: HEAD が凍結コミットと一致 ($CURRENT_HEAD)"
fi

DIRTY_STATUS="$(git -C "$WORKTREE_PATH" status --porcelain)"
if [ -n "$DIRTY_STATUS" ]; then
  echo "違反: 作業ツリーが汚染されています（凍結後の変更が検出されました）" >&2
  echo "$DIRTY_STATUS" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo "OK: 作業ツリーはクリーン"
fi

echo ""
if [ "$VIOLATIONS" -gt 0 ]; then
  echo "=== 凍結検証: FAIL（$VIOLATIONS 件の違反） ===" >&2
  exit 1
fi

echo "=== 凍結検証: PASS ==="
exit 0
