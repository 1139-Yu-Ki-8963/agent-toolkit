#!/usr/bin/env bash
# check-instruction-writing.test.sh — 本体の --self-test を実行する回帰試験。
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${here}/check-instruction-writing.sh" --self-test
