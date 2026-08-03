#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
projector="$script_dir/project-semantic-glossary.py"
fixture="$repo_root/shared/scripts/glossary/fixtures/valid-glossary.yaml"
registry="$repo_root/shared/scripts/glossary/fixtures/canonical-registry"
real_python="$repo_root/shared/scripts/glossary/.venv/bin/python"
[ -x "$real_python" ] || real_python="python3"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/semantic-glossary-projector-race.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
original="$tmp/original.yaml"
replacement="$tmp/replacement.yaml"
output="$tmp/page-data.json"
wrapper="$tmp/swap-original-before-validation.sh"
cp "$fixture" "$original"
sed 's/title: Commerce platform glossary/title: RACE_REPLACEMENT/' "$fixture" >"$replacement"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'cp "$RACE_REPLACEMENT" "$RACE_ORIGINAL"' \
  'exec "$REAL_PYTHON" "$@"' >"$wrapper"
chmod 700 "$wrapper"

GLOSSARY_PYTHON="$wrapper" \
REAL_PYTHON="$real_python" \
RACE_ORIGINAL="$original" \
RACE_REPLACEMENT="$replacement" \
  "$real_python" "$projector" --input "$original" --registry "$registry" --output "$output" >/dev/null

"$real_python" - "$output" "$original" <<'PY'
import json
import pathlib
import sys

output, original = map(pathlib.Path, sys.argv[1:])
assert json.loads(output.read_text(encoding="utf-8"))["title"] == "Commerce platform glossary"
assert "title: RACE_REPLACEMENT" in original.read_text(encoding="utf-8")
PY

printf 'PASS: projector validates and projects the same input bytes across a source-path replacement\n'
