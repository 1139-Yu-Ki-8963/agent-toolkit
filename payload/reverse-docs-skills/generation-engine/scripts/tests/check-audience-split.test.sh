#!/usr/bin/env bash
# 第1層の集約へ載せるための入口。
# 本体（.claude/rules/always/docs/audience-split/check-audience-split.sh）の自己テストを呼び、終了コードをそのまま返す。
# 判定の中身はここへ写さない。
# 集約は generation-engine/scripts/ と delivery-payload/templates/rules/checkers/ だけを
# 走査するため、.claude/rules/ に置いた本体はこの入口が無いと一度も実行されない。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TARGET="$SCRIPT_DIR/../../../.claude/rules/always/docs/audience-split/check-audience-split.sh"
# 本体は .claude/rules/ にあり、配布先へは配られない。
# 本体が無いのは「測れなかった」ではなく「測る対象が無い」である。
# 判定不能ではなく対象なしとして 0 を返す。
if [ ! -f "$TARGET" ]; then
  echo "[SKIP] 本体が無いため対象なしです。このリポジトリ専用の検査であり、配布先には対象がありません。"
  exit 0
fi

case "${1:-}" in
  ""|--self-test)
    exec bash "$TARGET" --self-test
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
