#!/usr/bin/env bash
# check-rule-flow-map-step-order.sh — 1-62の判定表「4. 追加した手順が手順1より
# 後にある」の確かめる手段を機械化する。
#
# 背景: build-rule-flow-map.sh を --target-root 付きで呼ぶ手順は、既存の
# scaffold-rule-definitions.sh 呼び出し（手順1）より後になければならない。
# 手順1が docs/rules/ を配置してから、build-rule-flow-map.sh がその実在を
# 読むためである。この前後関係は、SKILL.md 内の該当節を切り出し、両方の
# 呼び出し行の行番号を比べれば機械的に確定できる。
# 「簡潔なコマンドが無い」は .claude/rules/always/tasks/instruction-format/
# rule.md が認める目視の理由（文面の評価・複数資料の突き合わせ・実行環境
# 依存のいずれか）に当たらないため、このスクリプトへ切り出した。
#
# 使い方:
#   bash docs/scripts/check-rule-flow-map-step-order.sh              実ファイルを検査
#   bash docs/scripts/check-rule-flow-map-step-order.sh --self-test  自己テスト
#
# 終了コード: 0=手順1より後にある。1=無いか順序が逆。2=判定不能。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL_MD="$REPO_ROOT/.claude/skills/orchestrating-ai-development-setup/SKILL.md"
SECTION_HEADING="### 規約配布とAI設定資産生成の手順"
STEP1_PATTERN="scaffold-rule-definitions.sh"
NEW_STEP_PATTERN="build-rule-flow-map.sh"

# 指定ファイルから見出し以降・次の見出し未満の区間を切り出し、その中で
# STEP1_PATTERN と NEW_STEP_PATTERN の最初の行番号を比べる。
check_order() {
  local file="$1" section_file line1 line2

  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] 対象ファイルが存在しません: $file" >&2
    return 2
  fi

  if ! section_file="$(mktemp "${TMPDIR:-/tmp}/check-rule-flow-map-step-order.XXXXXX" \
      2>/dev/null)" || [ -z "$section_file" ]; then
    echo "[UNKNOWN] 一時ファイルを作成できません（mktemp失敗）" >&2
    return 2
  fi

  awk -v heading="$SECTION_HEADING" '
    $0 == heading { infile = 1; next }
    infile && /^### / { infile = 0 }
    infile { print }
  ' "$file" > "$section_file"

  if [ ! -s "$section_file" ]; then
    echo "不合格: 節「${SECTION_HEADING}」が見つかりません"
    rm -f "$section_file"
    return 1
  fi

  line1="$(grep -n -F "$STEP1_PATTERN" "$section_file" | head -1 | cut -d: -f1)"
  line2="$(grep -n -F "$NEW_STEP_PATTERN" "$section_file" | head -1 | cut -d: -f1)"
  rm -f "$section_file"

  if [ -z "$line1" ] || [ -z "$line2" ]; then
    echo "不合格: 手順1（${STEP1_PATTERN}）または新設手順（${NEW_STEP_PATTERN}）が見つかりません"
    return 1
  fi

  if [ "$line2" -gt "$line1" ]; then
    echo "合格: 新設手順（節内 ${line2} 行目）は手順1（節内 ${line1} 行目）より後にある"
    return 0
  fi

  echo "不合格: 新設手順（節内 ${line2} 行目）が手順1（節内 ${line1} 行目）より前にある"
  return 1
}

self_test() {
  local work fail=0
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-rule-flow-map-step-order-test.XXXXXX" \
      2>/dev/null)" || [ -z "$work" ]; then
    echo "[UNKNOWN] 自己テスト用の一時領域を作成できません" >&2
    return 2
  fi
  trap 'rm -rf "$work"' RETURN

  # ケース1: 正しい順序（手順1のあとに新設手順）は合格する
  cat > "$work/ok.md" <<'EOF'
### 規約配布とAI設定資産生成の手順

1. `bash .../scaffold-rule-definitions.sh <target_repo_path> --apply` を実行する
4. `bash .../build-rule-flow-map.sh` で規約とフローの対応ページを生成する

### 次の節
EOF
  if check_order "$work/ok.md" >/dev/null; then
    echo "PASS: 正しい順序を合格と判定した"
  else
    echo "FAIL: 正しい順序を不合格と誤判定した" >&2
    fail=1
  fi

  # ケース2: 逆順（新設手順が先）は不合格になる
  cat > "$work/reversed.md" <<'EOF'
### 規約配布とAI設定資産生成の手順

1. `bash .../build-rule-flow-map.sh` で規約とフローの対応ページを生成する
2. `bash .../scaffold-rule-definitions.sh <target_repo_path> --apply` を実行する

### 次の節
EOF
  if ! check_order "$work/reversed.md" >/dev/null; then
    echo "PASS: 逆順を不合格と判定した"
  else
    echo "FAIL: 逆順を合格と誤判定した" >&2
    fail=1
  fi

  # ケース3: 新設手順の記述が無い場合は不合格になる
  cat > "$work/missing.md" <<'EOF'
### 規約配布とAI設定資産生成の手順

1. `bash .../scaffold-rule-definitions.sh <target_repo_path> --apply` を実行する

### 次の節
EOF
  if ! check_order "$work/missing.md" >/dev/null; then
    echo "PASS: 新設手順が無い場合を不合格と判定した"
  else
    echo "FAIL: 新設手順が無い場合を合格と誤判定した" >&2
    fail=1
  fi

  # ケース4: 実ファイル（SKILL.md）に対しても合格すること
  if [ -f "$SKILL_MD" ]; then
    if check_order "$SKILL_MD" >/dev/null; then
      echo "PASS: 実ファイル(SKILL.md)を合格と判定した"
    else
      echo "FAIL: 実ファイル(SKILL.md)を不合格と誤判定した" >&2
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
    check_order "$SKILL_MD"
    ;;
esac
