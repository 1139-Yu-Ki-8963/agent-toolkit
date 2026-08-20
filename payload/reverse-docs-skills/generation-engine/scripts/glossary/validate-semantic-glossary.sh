#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --self-test: このラッパー自身の振る舞い（python の選択・引数の受け渡し・
# 依存不足時の案内）を検証する。python 本体（validate-semantic-glossary.py）の
# 用語妥当性判定は generation-engine/scripts/glossary/tests/test-validate-semantic-glossary.sh
# が別途担うため、ここでは扱わない。
self_test() {
  local rc=0 total=0 pass=0 fail=0
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-semantic-glossary-self-test.XXXXXX")" || {
    echo "[FAIL] 一時ディレクトリを作成できない" >&2
    echo "実行 0 件 / 成功 0 件 / 失敗 1 件"
    return 1
  }
  trap 'rm -rf "$tmp"' RETURN

  # ケース1: python の選択 — GLOSSARY_PYTHON で指定した python が使われること
  cat > "$tmp/fake-python-marker.sh" <<'FAKEPY'
#!/usr/bin/env bash
echo "MARKER:glossary-self-test-python-A"
exit 0
FAKEPY
  chmod +x "$tmp/fake-python-marker.sh"

  total=$((total + 1))
  local out1
  out1="$(GLOSSARY_PYTHON="$tmp/fake-python-marker.sh" bash "$SCRIPT_DIR/validate-semantic-glossary.sh" 2>&1)"
  if printf '%s\n' "$out1" | grep -qx 'MARKER:glossary-self-test-python-A'; then
    echo "[PASS] python選択: GLOSSARY_PYTHON で指定した python が使われる"
    pass=$((pass + 1))
  else
    echo "[FAIL] python選択: GLOSSARY_PYTHON で指定した python が使われない（出力: ${out1}）" >&2
    fail=$((fail + 1))
    rc=1
  fi

  # ケース2: 引数の受け渡し — 空白を含む値も分割されずそのまま python へ届くこと
  cat > "$tmp/fake-python-echo-args.sh" <<'FAKEPY'
#!/usr/bin/env bash
for a in "$@"; do
  printf 'ARG:%s\n' "$a"
done
exit 0
FAKEPY
  chmod +x "$tmp/fake-python-echo-args.sh"

  total=$((total + 1))
  local out2 out2_tail expected2
  out2="$(GLOSSARY_PYTHON="$tmp/fake-python-echo-args.sh" bash "$SCRIPT_DIR/validate-semantic-glossary.sh" --glossary "x y.md" --strict 2>&1)"
  # ラッパーは python本体のパス（validate-semantic-glossary.py）を先頭引数として
  # 常に渡すため、それに続く末尾3行だけを検証対象にする
  out2_tail="$(printf '%s\n' "$out2" | tail -n 3)"
  expected2=$'ARG:--glossary\nARG:x y.md\nARG:--strict'
  if [ "$out2_tail" = "$expected2" ]; then
    echo "[PASS] 引数の受け渡し: 渡した引数（空白を含む値も含めて）がそのまま python へ届く"
    pass=$((pass + 1))
  else
    echo "[FAIL] 引数の受け渡し: 引数が正しく届かない（出力: ${out2}）" >&2
    fail=$((fail + 1))
    rc=1
  fi

  # ケース3: 依存不足時の案内 — 終了コード2・SGD_DEPENDENCY相当の標準エラーに
  # venv構築手順のHINTが追加され、元の終了コード・元の標準エラーは保たれること
  cat > "$tmp/fake-python-dep-fail.sh" <<'FAKEPY'
#!/usr/bin/env bash
echo "SGD_DEPENDENCY: required dependency is unavailable" >&2
exit 2
FAKEPY
  chmod +x "$tmp/fake-python-dep-fail.sh"

  total=$((total + 1))
  local out3 status3
  set +e
  out3="$(GLOSSARY_PYTHON="$tmp/fake-python-dep-fail.sh" bash "$SCRIPT_DIR/validate-semantic-glossary.sh" 2>&1)"
  status3=$?
  set -e
  if [ "$status3" -eq 2 ] \
    && printf '%s\n' "$out3" | grep -q 'SGD_DEPENDENCY' \
    && printf '%s\n' "$out3" | grep -q '^HINT:'; then
    echo "[PASS] 依存不足時の案内: 終了コード2・依存不足エラーに構築手順の案内が追加され、元の終了コードとエラーは保たれる"
    pass=$((pass + 1))
  else
    echo "[FAIL] 依存不足時の案内: 案内が出ない、または終了コード・エラーが変わる（終了コード: ${status3} / 出力: ${out3}）" >&2
    fail=$((fail + 1))
    rc=1
  fi

  echo "実行 ${total} 件 / 成功 ${pass} 件 / 失敗 ${fail} 件"
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

PYTHON_BIN="${GLOSSARY_PYTHON:-}"
VENV_PYTHON="$SCRIPT_DIR/.venv/bin/python"

if [ -z "$PYTHON_BIN" ] && [ -x "$VENV_PYTHON" ]; then
  PYTHON_BIN="$VENV_PYTHON"
fi
if [ -z "$PYTHON_BIN" ]; then
  PYTHON_BIN="python3"
fi

# validate-semantic-glossary.py の dependency_modules() は不足モジュール名・バージョン不一致を
# 明示するが、venv未構築という根本原因までは述べない。ここではその出力を素通しした上で、
# SGD_DEPENDENCY相当の失敗を検知したときだけ venv 構築手順を追加提示する。
# 素直な形(pythonの標準エラーをそのままパイプでgrepへ渡す)を避け、いったんファイルへ
# 書き出す。標準エラーは「呼び出し元へそのまま中継する」用途と「HINT要否をgrepで
# 判定する」用途の2箇所で使うため、パイプで一度だけ消費させず、ファイルへ退避して
# 2回読む必要がある。
STDERR_FILE="$(mktemp "${TMPDIR:-/tmp}/validate-semantic-glossary-stderr.XXXXXX")"
trap 'rm -f "$STDERR_FILE"' EXIT

set +e
"$PYTHON_BIN" "$SCRIPT_DIR/validate-semantic-glossary.py" "$@" 2>"$STDERR_FILE"
status=$?
set -e

cat "$STDERR_FILE" >&2

if [ "$status" -eq 2 ] && grep -qE 'SGD_DEPENDENCY|required dependency is unavailable|Python 3\.13 is required' "$STDERR_FILE" 2>/dev/null; then
  {
    echo "HINT: $PYTHON_BIN に用語検証の実行環境（Python 3.13 系 + requirements.txt の依存）が整っていない。"
    echo "対処: worktree内venvを構築してから再実行する（GLOSSARY_PYTHON で別インタプリタを指す場合も同じ依存が要る）。"
    echo "  python3.13 -m venv $SCRIPT_DIR/.venv"
    echo "  $SCRIPT_DIR/.venv/bin/pip install -r $SCRIPT_DIR/requirements.txt"
  } >&2
fi

exit "$status"
