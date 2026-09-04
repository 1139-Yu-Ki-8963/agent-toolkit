#!/usr/bin/env bash
set -euo pipefail

# test-self-tests.sh — plan-reverse.sh 自身の --self-test を実行する

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN_SCRIPT="${SCRIPT_DIR}/../scripts/plan-reverse.sh"

exec "$PLAN_SCRIPT" --self-test
