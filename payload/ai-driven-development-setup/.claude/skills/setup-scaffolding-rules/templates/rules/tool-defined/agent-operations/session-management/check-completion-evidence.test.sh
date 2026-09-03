#!/usr/bin/env bash
# check-completion-evidence.test.sh — check-completion-evidence.sh の回帰テスト
#
# 本体が持つ --self-test をそのまま実行する。判定の中身を二重に持たないのは、
# 本体の --self-test が唯一の正としてケースを持ち、こちらが写しを持つと
# 両者がずれたときにどちらが正しいか分からなくなるためである。
#
# 使い方: bash check-completion-evidence.test.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${here}/check-completion-evidence.sh" --self-test
