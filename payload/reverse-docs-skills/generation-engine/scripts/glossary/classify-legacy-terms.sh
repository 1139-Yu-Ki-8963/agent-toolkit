#!/usr/bin/env bash
# classify-legacy-terms.py の入口。python の選び方を validate-semantic-glossary.sh と揃える。
#
# --self-test: 3状態への分類が実際に働くことを、合成した用語集で確かめる。
#   実行できない場合（PyYAML 不在等）は [UNKNOWN] と終了コード2で終える
#   （.claude/rules/always/verification/indeterminate-result/rule.md）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_python() {
  local bin="${GLOSSARY_PYTHON:-}"
  local venv="$SCRIPT_DIR/.venv/bin/python"
  if [ -z "$bin" ] && [ -x "$venv" ]; then bin="$venv"; fi
  if [ -z "$bin" ]; then bin="python3"; fi
  printf '%s' "$bin"
}

self_test() {
  local py tmp pass=0 fail=0
  py="$(resolve_python)"
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/classify-legacy.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時領域を確保できないため判定できません（mktemp が失敗しました）"
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  # 3状態それぞれに当たる用語を1件ずつ持つ合成の用語集
  cat > "$tmp/g.yaml" <<'YAML'
glossary_key: t
glossary_schema_version: 1.0.0
content_version: 1.0.0
terms:
  - key: approved_one
    definition: 承認の記録が揃う用語
    provenance:
      sources: [{type: doc, ref: a}]
      decision_ref: proposals/p
      change_ref: changes/c
  - key: candidate_one
    definition: 出典はあるが承認の記録が欠ける用語
    provenance:
      sources: [{type: doc, ref: b}]
  - key: legacy_one
    definition: 出典が無い用語
    provenance:
      sources: []
YAML

  local out
  if ! out="$("$py" "$SCRIPT_DIR/classify-legacy-terms.py" --input "$tmp/g.yaml" 2>"$tmp/err")"; then
    if grep -q 'PyYAML' "$tmp/err" 2>/dev/null; then
      echo "[UNKNOWN] PyYAML が無いため判定できません（$SCRIPT_DIR/.venv を作るか requirements.txt の依存を入れてください）"
      exit 2
    fi
    echo "FAIL: 分類器を実行できない（$(head -1 "$tmp/err" | cut -c1-70)）"
    echo "実行 1 件 / 成功 0 件 / 失敗 1 件"
    return 1
  fi

  check() {
    local name="$1" expr="$2" want="$3" got
    got="$(printf '%s' "$out" | "$py" -c "import json,sys; d=json.load(sys.stdin); print($expr)")"
    if [ "$got" = "$want" ]; then
      echo "PASS: $name"; pass=$((pass + 1))
    else
      echo "FAIL: $name（期待 $want・実際 $got）"; fail=$((fail + 1))
    fi
  }

  check "承認の記録が揃う用語を approved にする" "d['分類']['approved']" 1
  check "承認の記録が欠ける用語を candidate にする" "d['分類']['candidate']" 1
  check "出典が無い用語を legacy_migrated にする" "d['分類']['legacy_migrated']" 1
  check "全行を分類する" "d['総数']" 3
  check "分類の合計が総数と一致する" "sum(d['分類'].values())" 3
  check "候補を自動で承認しない" "'candidate_one' in d['内訳']['candidate']" True
  check "判断の理由を残す" "len(d['理由']) == 3" True

  echo "実行 $((pass + fail)) 件 / 成功 $pass 件 / 失敗 $fail 件"
  [ "$fail" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

exec "$(resolve_python)" "$SCRIPT_DIR/classify-legacy-terms.py" "$@"
