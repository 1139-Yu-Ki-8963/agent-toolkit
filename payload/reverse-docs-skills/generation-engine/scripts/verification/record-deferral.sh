#!/usr/bin/env bash
# 退避記録の専用台帳を廃止したことを明示する互換入口。
set -u

if [ "${1:-}" = "--self-test" ] && [ "$#" -eq 1 ]; then
  echo "[PASS] 退避内容を専用台帳へ記録しない"
  exit 0
fi

echo "ERROR: 退避記録の専用台帳への記録は廃止しました" >&2
exit 2
