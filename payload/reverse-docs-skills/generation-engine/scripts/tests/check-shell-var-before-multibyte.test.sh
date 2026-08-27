#!/usr/bin/env bash
# 第1層の集約へ載せるための入口。
# 本体（docs/scripts/check-shell-var-before-multibyte.sh）の自己テストを呼び、
# 終了コードをそのまま返す。判定の中身はここへ写さない。
# 集約が走査するのは generation-engine/scripts/ と
# delivery-payload/templates/rules/checkers/ だけである。
# 本体は docs/scripts/ に置くため、この入口が無いと一度も実行されない。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TARGET="$SCRIPT_DIR/../../../docs/scripts/check-shell-var-before-multibyte.sh"
if [ ! -f "$TARGET" ]; then
  echo "[UNKNOWN] 本体が見つからないため判定できません（${TARGET}）"
  exit 2
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
