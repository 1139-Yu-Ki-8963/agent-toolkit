#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
exec bash "$SCRIPT_DIR/../../../docs/scripts/check-reference-json-integrity.sh" --self-test
