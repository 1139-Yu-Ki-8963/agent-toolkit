#!/usr/bin/env bash
# project-semantic-glossary.pyのread_input_once+run_validatorのTOCTOU対策
# (docs/design/batches/batch-detail-pages/detail-design/バッチ詳細設計書.md参照)を、実際に
# 検証中に元ファイルを差し替えるレースを再現して検証する。素直な形(通常のpython3を
# そのまま呼ぶ)を避け、"python"の代わりに元ファイルを差し替えてから本物のpythonへ
# execするラッパースクリプトをGLOSSARY_PYTHON経由で注入する(validate-semantic-glossary.sh
# がGLOSSARY_PYTHONを読む口を使う)。この注入無しに同じレースを機械的に再現する手段はない。
set -euo pipefail

# 実装判断: 無引数の実行で検査本体が走り切る構造のため、--self-test を
#   受けても同じ動作をすればよい。集約（run-layer-machine-checks.sh）は
#   --self-test の文字列を持つスクリプトを対象として集めるため、この分岐が
#   無いと「自己テスト未整備」として警告される。2026-08-21 に追加。
case "${1:-}" in --self-test) ;; esac

# 2026-08-19 に次の 2 点が変わり、この検査は集約へ載せ直された。
#   1. 集約の収集の条件へ、名前が test-*.sh に一致するものを拾う経路が加わった
#      （run-layer-machine-checks.sh の list_targets）。この検査は --self-test の
#      受け口を持たないが、名前で拾われる。収集は 149 件から 160 件へ増えた。
#   2. 集約が終了コード 2 を [UNKNOWN] として不合格と区別するようになった
#      （同スクリプト 440〜442 行目）。判定不能は集計行に現れるが、集約全体の
#      終了コードには影響しない（同 470 行目の条件は failed・suspect・timed_out のみ）。
# 引数なしの実行はいまも終了コード 2 を返す（PyYAML がこの環境に無いため）。
# 集約では終了コードだけで [UNKNOWN] と判定されるため、集約全体の終了コードは
# 1 にならない。ただし本スクリプト自身の出力は「ERROR: PyYAML is unavailable」
# （project-semantic-glossary.py が返す汎用エラー文言）のままで、判定不能の決まり
# （indeterminate-result）が求める [UNKNOWN] ラベルを持たなかった。1-244実測
# （2026-08-21）でこれを検出し、下記の事前確認で [UNKNOWN] ラベル付きの終了コード 2
# を本スクリプト自身が返す形へ改めた（project-semantic-glossary.py 側は本検査の対象
# 3本の外であり変更していない）。

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
projector="$script_dir/project-semantic-glossary.py"
fixture="$repo_root/generation-engine/scripts/glossary/fixtures/valid-glossary.yaml"
registry="$repo_root/generation-engine/scripts/glossary/fixtures/canonical-registry"
# 配布先には .venv が無い。呼び出し元が渡す GLOSSARY_PYTHON(check-payload-layer1.sh が
# 正本の実行系を渡す)を最優先で使い、無ければ正本の .venv、最後に python3 へ落とす。
real_python="${GLOSSARY_PYTHON:-}"
if [ -z "$real_python" ] || [ ! -x "$real_python" ]; then
  real_python="$repo_root/generation-engine/scripts/glossary/.venv/bin/python"
fi
[ -x "$real_python" ] || real_python="python3"

if ! "$real_python" -c 'import yaml' >/dev/null 2>&1; then
  # PyYAMLがこの環境（${real_python}）に無いのは実行できなかったことであり、検査対象
  # （TOCTOU対策）が不合格だったことではない。判定不能の決まり（indeterminate-result）
  # に従い、test-validate-semantic-glossary.shと同じ書式で終了コード2を返す。
  echo "[UNKNOWN] PyYAMLの読み込みに失敗したため判定できません（$real_python で import yaml を実行できませんでした。PyYAMLが未導入、または選択したPython実行系から参照できない可能性があります）" >&2
  exit 2
fi

if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/semantic-glossary-projector-race.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
  echo "[UNKNOWN] 一時ディレクトリを作成できないため判定できません（mktemp -d が一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
  exit 2
fi
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
  "$real_python" "$projector" --input "$original" --registry "$registry" --output "$output" \
  >/dev/null 2>"$tmp/projector.stderr" && projector_exit=0 || projector_exit=$?

if [ "$projector_exit" -eq 2 ]; then
  if ! grep -qE 'PyYAML is unavailable|required dependency is unavailable|Python 3\.13 is required|PyYAML>=6,<7 is required|jsonschema>=4\.23,<5 is required' "$tmp/projector.stderr"; then
    echo "FAIL: 投影器が固定した検査入力に対して終了コード2を返しました" >&2
    cat "$tmp/projector.stderr" >&2
    exit 1
  fi
  echo "[UNKNOWN] 投影器の依存を利用できないため判定できません（$real_python $projector が依存不足を報告して終了コード2を返しました。Pythonの版数または依存パッケージが原因です）" >&2
  cat "$tmp/projector.stderr" >&2
  exit 2
fi
if [ "$projector_exit" -ne 0 ]; then
  cat "$tmp/projector.stderr" >&2
  exit "$projector_exit"
fi

"$real_python" - "$output" "$original" <<'PY'
import json
import pathlib
import sys

output, original = map(pathlib.Path, sys.argv[1:])
assert json.loads(output.read_text(encoding="utf-8"))["title"] == "Commerce platform glossary"
assert "title: RACE_REPLACEMENT" in original.read_text(encoding="utf-8")
PY

printf 'PASS: projector validates and projects the same input bytes across a source-path replacement\n'
