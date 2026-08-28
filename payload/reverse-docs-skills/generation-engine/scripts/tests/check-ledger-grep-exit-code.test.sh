#!/usr/bin/env bash
# 第1層の集約へ載せるための入口。
# 本体（docs/scripts/check-ledger-grep-exit-code.sh）の自己テストを呼び、
# 終了コードをそのまま返す。判定の中身はここへ写さない。
# 集約が走査するのは generation-engine/scripts/ と
# delivery-payload/templates/rules/checkers/ だけである。
# 本体は docs/scripts/ に置くため、この入口が無いと一度も実行されない。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TARGET="$SCRIPT_DIR/../../../docs/scripts/check-ledger-grep-exit-code.sh"

# 本体は台帳を読む。台帳はこのリポジトリ専用であり配布先へは配られない。
# 本体が無いのは「測れなかった」ではなく「測る対象が無い」である。
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
