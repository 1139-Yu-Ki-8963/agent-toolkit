#!/usr/bin/env bash
# project-semantic-glossary.pyのread_input_once+run_validatorのTOCTOU対策
# (docs/design/generation-engine/detail-pages/詳細設計書.md参照)を、実際に
# 検証中に元ファイルを差し替えるレースを再現して検証する。素直な形(通常のpython3を
# そのまま呼ぶ)を避け、"python"の代わりに元ファイルを差し替えてから本物のpythonへ
# execするラッパースクリプトをGLOSSARY_PYTHON経由で注入する(validate-semantic-glossary.sh
# がGLOSSARY_PYTHONを読む口を使う)。この注入無しに同じレースを機械的に再現する手段はない。
set -euo pipefail

# 2026-08-19 に次の 2 点が変わり、この検査は集約へ載せ直された。
#   1. 集約の収集の条件へ、名前が test-*.sh に一致するものを拾う経路が加わった
#      （run-layer-machine-checks.sh の list_targets）。この検査は --self-test の
#      受け口を持たないが、名前で拾われる。収集は 149 件から 160 件へ増えた。
#   2. 集約が終了コード 2 を [UNKNOWN] として不合格と区別するようになった
#      （同スクリプト 440〜442 行目）。判定不能は集計行に現れるが、集約全体の
#      終了コードには影響しない（同 470 行目の条件は failed・suspect・timed_out のみ）。
# 引数なしの実行はいまも終了コード 2 を返す（PyYAML がこの環境に無いため）。
# 集約では [UNKNOWN] として扱われ、全体の終了コードを 1 にしない。

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
projector="$script_dir/project-semantic-glossary.py"
fixture="$repo_root/generation-engine/scripts/glossary/fixtures/valid-glossary.yaml"
registry="$repo_root/generation-engine/scripts/glossary/fixtures/canonical-registry"
real_python="$repo_root/generation-engine/scripts/glossary/.venv/bin/python"
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
