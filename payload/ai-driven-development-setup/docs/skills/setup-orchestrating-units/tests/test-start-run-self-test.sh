#!/usr/bin/env bash
set -euo pipefail

# test-start-run-self-test.sh — start-run.sh 自身の --self-test を実行する

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_RUN_SCRIPT="${SCRIPT_DIR}/../scripts/start-run.sh"

exec "$START_RUN_SCRIPT" --self-test
