#!/usr/bin/env bash
# 実行記録の専用台帳を廃止したことを明示する互換入口。
set -u

if [ "${1:-}" = "--self-test" ] && [ "$#" -eq 1 ]; then
  echo "[PASS] 専用台帳を使った前回比較を行わない"
  exit 0
fi

echo "ERROR: 専用台帳を使った前回比較は廃止しました" >&2
exit 2
