#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${GLOSSARY_PYTHON:-}"

if [ -z "$PYTHON_BIN" ] && [ -x "$SCRIPT_DIR/.venv/bin/python" ]; then
  PYTHON_BIN="$SCRIPT_DIR/.venv/bin/python"
fi
if [ -z "$PYTHON_BIN" ]; then
  PYTHON_BIN="python3"
fi

exec "$PYTHON_BIN" "$SCRIPT_DIR/validate-semantic-glossary.py" "$@"
