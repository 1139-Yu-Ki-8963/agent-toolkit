#!/usr/bin/env bash
# check-completion-doc-command-match.sh — 1-75の判定表「3. コマンドが判定表と
# 一致する」の確かめる手段を機械化する。
#
# 背景: docs/design/納品完了の条件.md の「2. 5段の条件」節（第3段の判定表）は
# 各判定キーの「判定コマンド・代替確認」列にコマンドを1つ持つ。「4. 判定の手順」
# 節（§4）は同じコマンドをbashのコメント見出し（# <キー>: <名前>）の直後へ書く。
# 両者が食い違うと、判定表を見て実行した内容と実際の判定手順が一致しない。
# この一致は、両方の場所から対象のコマンド文字列を抜き出して比べれば
# 機械的に確定できる。文面全体の趣旨比較ではなく、コマンドという1つの
# 文字列同士の完全一致比較であるため、「文面の比較を要する」という理由は
# 当たらない。
#
# 使い方:
#   bash docs/scripts/check-completion-doc-command-match.sh              実ファイルを検査
#   bash docs/scripts/check-completion-doc-command-match.sh --self-test  自己テスト
#
# 対象キー: docs-required-items・docs-code-consistency・docs-cross-reference・
#          docs-customer-facing・docs-shorthand-reference・docs-style-register
#
# 終了コード: 0=6キー全件一致。1=1件でも不一致・欠落。2=判定不能。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOC_DEFAULT="$REPO_ROOT/docs/design/納品完了の条件.md"

KEYS="docs-required-items docs-code-consistency docs-cross-reference docs-customer-facing docs-shorthand-reference docs-style-register"

# §2の判定表の該当行から、判定コマンド列（5番目のフィールド）内の
# 最初のバッククォート囲みの文字列を取り出す。
extract_table_command() {
  local file="$1" key="$2"
  grep -F "| $key |" "$file" | head -1 \
    | awk -F'|' '{print $5}' \
    | sed -n 's/^[^`]*`\([^`]*\)`.*/\1/p'
}

# §4のコメント見出し（# <キー>: ...）の直後にある、最初の非空行を取り出す。
extract_step_command() {
  local file="$1" key="$2"
  awk -v key="$key" '
    found == 1 && NF > 0 { print; exit }
    $0 ~ "^# " key ":" { found = 1; next }
  ' "$file"
}

# 前後の空白を取り除く。
trim() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

check_commands() {
  local file="$1" key table_cmd step_cmd fail=0

  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] 対象ファイルが存在しません: $file" >&2
    return 2
  fi

  for key in $KEYS; do
    table_cmd="$(trim "$(extract_table_command "$file" "$key")")"
    step_cmd="$(trim "$(extract_step_command "$file" "$key")")"

    if [ -z "$table_cmd" ]; then
      echo "不合格: ${key} の判定表コマンドが見つかりません"
      fail=1
      continue
    fi
    if [ -z "$step_cmd" ]; then
      echo "不合格: ${key} の手順コマンドが見つかりません"
      fail=1
      continue
    fi
    if [ "$table_cmd" = "$step_cmd" ]; then
      echo "合格: ${key} は判定表と手順のコマンドが一致する"
    else
      echo "不合格: ${key} は判定表と手順のコマンドが不一致"
      echo "  判定表: $table_cmd"
      echo "  手順  : $step_cmd"
      fail=1
    fi
  done

  return "$fail"
}

self_test() {
  local work fail=0
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-completion-doc-command-match-test.XXXXXX" \
      2>/dev/null)" || [ -z "$work" ]; then
    echo "[UNKNOWN] 自己テスト用の一時領域を作成できません" >&2
    return 2
  fi
  trap 'rm -rf "$work"' RETURN

  # ケース1: 6キー全件が一致する合成データは合格する
  cat > "$work/ok.md" <<'EOF'
| docs-required-items | 項目 | 確認先 | `bash x/check-a.sh <p>`（1-230） | 実行主体 |
| docs-code-consistency | 項目 | 確認先 | `bash x/check-b.sh <p>`（1-246） | 実行主体 |
| docs-cross-reference | 項目 | 確認先 | `bash x/check-c.sh <p>`（1-232） | 実行主体 |
| docs-customer-facing | 項目 | 確認先 | `bash x/check-d.sh <p>`（1-233） | 実行主体 |
| docs-shorthand-reference | 項目 | 確認先 | `bash x/check-e.sh <p>`（1-235） | 実行主体 |
| docs-style-register | 項目 | 確認先 | `bash x/check-f.sh <p>`（1-237） | 実行主体 |

# docs-required-items: 名前
bash x/check-a.sh <p>

# docs-code-consistency: 名前
bash x/check-b.sh <p>

# docs-cross-reference: 名前
bash x/check-c.sh <p>

# docs-customer-facing: 名前
bash x/check-d.sh <p>

# docs-shorthand-reference: 名前
bash x/check-e.sh <p>

# docs-style-register: 名前
bash x/check-f.sh <p>
EOF
  if check_commands "$work/ok.md" >/dev/null; then
    echo "PASS: 全件一致を合格と判定した"
  else
    echo "FAIL: 全件一致を不合格と誤判定した" >&2
    fail=1
  fi

  # ケース2: 1件だけ不一致にすると不合格になる（手順側だけを書き換える）
  awk '
    /^# docs-code-consistency:/ { print; getline; print "bash x/check-b-different.sh <p>"; next }
    { print }
  ' "$work/ok.md" > "$work/mismatch.md"
  if ! check_commands "$work/mismatch.md" >/dev/null; then
    echo "PASS: 不一致を不合格と判定した"
  else
    echo "FAIL: 不一致を合格と誤判定した" >&2
    fail=1
  fi

  # ケース3: 手順側の見出しごと欠落すると不合格になる
  awk '/^# docs-style-register:/{skip=2} skip{skip--; next} {print}' \
    "$work/ok.md" > "$work/missing.md"
  if ! check_commands "$work/missing.md" >/dev/null; then
    echo "PASS: 手順の欠落を不合格と判定した"
  else
    echo "FAIL: 手順の欠落を合格と誤判定した" >&2
    fail=1
  fi

  # ケース4: 実ファイルに対しても合格すること
  if [ -f "$DOC_DEFAULT" ]; then
    if check_commands "$DOC_DEFAULT" >/dev/null; then
      echo "PASS: 実ファイル(納品完了の条件.md)を合格と判定した"
    else
      echo "FAIL: 実ファイル(納品完了の条件.md)を不合格と誤判定した" >&2
      fail=1
    fi
  fi

  return "$fail"
}

case "${1:-}" in
  --self-test)
    self_test
    ;;
  *)
    check_commands "$DOC_DEFAULT"
    ;;
esac
