#!/usr/bin/env bash
# 故障を注入した自己テストが、注入した理由を出力へ含めることを確かめる。
#
# なぜ要るか: 検収コマンドを台帳の表へ直接書くと1文が100字を超え、
#   台帳の文長の検査に掛かる（2026-08-28実測）。処理をここへ移し、
#   表からは短い名前だけを呼ぶ。
#
#   自己テストは故障を注入すると終了コード1で終わる。これは期待した動きである。
#   終了コードだけを見ると不合格に見えるため、出力に理由が現れるかを見る。
#
# 使い方: bash docs/scripts/check-fault-injection.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
REASON='注入した失敗理由'

cd "$REPO_ROOT" || exit 2

# 自己テストは故障を注入すると終了コード1で終わる。これは期待した動きである。
# pipefail の下でパイプへ繋ぐと、この1がパイプ全体の終了コードになり、
# grep が一致しても不合格になる（2026-08-28実測）。出力を一度受け取ってから見る。
if ! out="$(mktemp "${TMPDIR:-/tmp}/fault-inject.XXXXXX" 2>/dev/null)" || [ -z "$out" ]; then
  echo "[UNKNOWN] 一時ファイルを作れないため判定できません（mktempが書き込めませんでした）"
  exit 2
fi
env SELF_TEST_FORCE_SITE_BUILD_FAILURE="$REASON" \
  bash generation-engine/scripts/detail-pages/build-detail-page.sh --self-test > "$out" 2>&1

if grep -q "$REASON" "$out"; then
  rm -f "$out"
  echo "[PASS] 注入した理由が出力に現れる"
  exit 0
fi
echo "[FAIL] 注入した理由が出力に現れない" >&2
tail -3 "$out" >&2
rm -f "$out"
exit 1
