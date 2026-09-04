#!/usr/bin/env bash
set -u

# test-acceptance-on-self.sh - check-acceptance.sh を、このリポジトリ自身の
# ルートに対して実行し、終了コード0になることを確かめる。自分自身を含む
# docs/skills 配下の全機能のtestsが実際に回るため、他の機能を壊した場合に
# ここで検知できる。
#
# ACCEPTANCE_SKIP_SELF=1 を付けて内側の呼び出しを行う。付けないと、この
# testsの実行自体が自分自身の機能（setup-checking-acceptance）のtestsに
# 含まれるため、check-acceptance.shを呼ぶたびにこのtestsがまた呼ばれ、
# 再帰が終わらなくなる。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
CHECK_SCRIPT="${SCRIPT_DIR}/../scripts/check-acceptance.sh"

OUTPUT="$(ACCEPTANCE_SKIP_SELF=1 bash "$CHECK_SCRIPT" "$REPO_ROOT" 2>&1)"
RC=$?

echo "$OUTPUT"
echo "----"
echo "check-acceptance.sh ${REPO_ROOT} の終了コード: ${RC}"

if [ "$RC" -eq 0 ]; then
  echo "PASS: 自分自身に対する合格の集計は終了コード0"
  exit 0
fi
echo "FAIL: 自分自身に対する合格の集計が終了コード0にならない"
exit 1
