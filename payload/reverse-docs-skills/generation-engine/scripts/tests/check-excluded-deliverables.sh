#!/usr/bin/env bash
# check-excluded-deliverables.sh — docs/scripts/check-excluded-deliverables.sh の
# 回帰テストを第1層の機械検証(run-layer-machine-checks.sh)から拾えるようにする
# 入口。
#
# 背景: docs/scripts/ 配下は第1層の集約の走査対象に入らない。走査対象は
# generation-engine/scripts/ と delivery-payload/templates/rules/checkers/ の
# 2箇所だけである。本体(docs/scripts/check-excluded-deliverables.sh)は
# --self-test を持つが、置き場所が集約の走査対象外のため、このままでは
# 第1層から一度も実行されない。本体の --self-test を呼び、終了コードを
# そのまま返すだけのラッパーをここへ置くことで集約に載せる。判定の中身を
# 写して持たないのは、本体の --self-test を唯一の正とし、両者がずれたときに
# どちらが正しいか分からなくなる事態を避けるためである
# （check-depends-on-kind.sh と同じ形）。
#
# 使い方: bash check-excluded-deliverables.sh --self-test
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET="$REPO_ROOT/docs/scripts/check-excluded-deliverables.sh"

case "${1:-}" in
  --self-test)
    exec bash "$TARGET" --self-test
    ;;
  *)
    echo "usage: $0 --self-test" >&2
    exit 2
    ;;
esac
