#!/bin/bash -p
# check-delegation-completion-criteria.test.sh — check-delegation-completion-criteria.sh の回帰テスト
#
# 本体が持つ --self-test をそのまま実行する。判定の中身を二重に持たないのは、
# 本体の --self-test が唯一の正としてケースを持ち、こちらが写しを持つと
# 両者がずれたときにどちらが正しいか分からなくなるためである。
#
# シェバンと`bash -p`は対にする（2026-09-06第20版）。`bash`を明示指定して
# 委譲する`exec`はこの入口自身のシェバンを引き継がないため、委譲先にも
# `-p`を明示する（check-work-records.test.shと同じ対処）。
#
# 使い方: bash check-delegation-completion-criteria.test.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash -p "${here}/check-delegation-completion-criteria.sh" --self-test
