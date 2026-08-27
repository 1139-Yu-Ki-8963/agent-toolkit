#!/usr/bin/env bash
# ケース1へ故障を注入した自己テストが、注入した旨を出力へ含めることを確かめる。
#
# なぜ要るか: 自己テストは故障を注入すると終了コード1で終わる。これは期待した動きである。
#   終了コードだけを見ると不合格に見えるため、台帳の検収が不合格を返していた（2026-08-28実測）。
#   出力に注入の印が現れるかを見る形にする。
#
#   同じ形の先例として check-fault-injection.sh がある。あちらは
#   build-detail-page.sh の故障注入を扱う。こちらは build-portal.sh を扱う。
#
# 実装判断（パイプへ繋がず出力を一度受け取る）: pipefail の下で終了コード1を
#   パイプへ繋ぐと、その1がパイプ全体の終了コードになる。grep が一致しても
#   不合格になる。出力を一時ファイルへ受け取ってから見る。
#
# 使い方: bash docs/scripts/check-portal-case1-injection.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
MARK='継続確認用の強制不合格fixture'

cd "$REPO_ROOT" || exit 2

if ! out="$(mktemp "${TMPDIR:-/tmp}/case1-inject.XXXXXX" 2>/dev/null)" || [ -z "$out" ]; then
  echo "[UNKNOWN] 一時ファイルを作れないため判定できません（mktempが書き込めませんでした）"
  exit 2
fi

BUILD_PORTAL_SELF_TEST_FORCE_CASE1_FAILURE=1 \
  bash generation-engine/scripts/build-portal.sh --self-test > "$out" 2>&1

if grep -q "$MARK" "$out"; then
  echo "[PASS] 注入した故障が出力に現れる"
  rm -f "$out"
  exit 0
fi
echo "[FAIL] 注入した故障が出力に現れない" >&2
tail -3 "$out" >&2
rm -f "$out"
exit 1
