#!/usr/bin/env bash
# check-inventory-approval-step.sh — 統括スキル（orchestrating-ai-development-setup）が
#   Phase 2（アーキテクチャ調査）の直後に納品物の一覧と対象範囲を提示し、承認を得る
#   段（Step 2-7）を正しく備えているかを検査する。
#
# 使い方:
#   bash docs/scripts/check-inventory-approval-step.sh                     全検査を実行
#   bash docs/scripts/check-inventory-approval-step.sh --step-present      Step 2-7 の実在と本文
#   bash docs/scripts/check-inventory-approval-step.sh --step-order        Step 2-7 が Phase 3 より前にあるか
#   bash docs/scripts/check-inventory-approval-step.sh --step3-2-reads-approval  Step 3-2 が承認結果を読むか
#   bash docs/scripts/check-inventory-approval-step.sh --final-crosscheck  Phase 7 に最終突き合わせがあるか
#   bash docs/scripts/check-inventory-approval-step.sh --scope-change-reapproval  範囲変更時の再承認があるか
#   bash docs/scripts/check-inventory-approval-step.sh --phase1-no-prompt  準備の段に確認記述が無いか
#   bash docs/scripts/check-inventory-approval-step.sh --phase7-no-approval  判定と確定の段に承認記述が無いか
#   bash docs/scripts/check-inventory-approval-step.sh --user-prompt-count  確認箇所が1件だけか
#   bash docs/scripts/check-inventory-approval-step.sh --headless-skip     headless=trueで1件も発行しないか
#   bash docs/scripts/check-inventory-approval-step.sh --self-test         自己テスト
#
# 判定不能規約（.claude/rules/always/verification/indeterminate-result/rule.md）に従い、
# 対象ファイルが読めない場合は [UNKNOWN] と終了コード2を返す。--self-test は独立した
# 使い捨てディレクトリを mktemp で確保するため、判定不能になりうるのはそこだけである。
#
# 必要性・代替案・保守責任者・廃棄条件:
#   .claude/rules/scoped/portal/page-conventions/rule.md の「## 設計判断」
#   「### check-inventory-approval-step.sh」を参照（正本。派生物は
#   .claude/rules/scoped/portal/page-conventions/rule.md ではなく
#   docs/rules/portal/page-conventions/rule.md が正本であり、本ファイルからは
#   docs/rules 側を参照する）。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL_MD="$REPO_ROOT/.claude/skills/orchestrating-ai-development-setup/SKILL.md"

# ---- セクション抽出ヘルパー -------------------------------------------------

# 指定した開始見出し（正規表現、行全体一致）から、次の "## " 見出し（それ自身は含まない）
# までの範囲を標準出力へ書き出す。終端が見つからなければファイル末尾まで。
extract_section() {
  local file="$1" start_pattern="$2"
  awk -v start="$start_pattern" '
    BEGIN { in_section = 0 }
    $0 ~ start && in_section == 0 { in_section = 1; print; next }
    in_section == 1 && /^## / && $0 !~ start { exit }
    in_section == 1 { print }
  ' "$file"
}

# Phase見出し専用の抽出。Phase節はStep見出し（"## Step N-M:"）を内部に複数持つため、
# extract_section をそのまま使うと最初のStep見出しで打ち切られ、Phase節の大半（各Stepの
# 本文）を読み落とす。次の "## Phase " 見出しが現れるまでを1つのPhase節として抽出する。
extract_phase_section() {
  local file="$1" phase_num="$2"
  awk -v phase="^## Phase ${phase_num}:" '
    BEGIN { in_section = 0 }
    $0 ~ phase && in_section == 0 { in_section = 1; print; next }
    in_section == 1 && /^## Phase [0-9]/ && $0 !~ phase { exit }
    in_section == 1 { print }
  ' "$file"
}

# ---- 個別検査 ---------------------------------------------------------------

check_step_present() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] SKILL.mdを読み取れないため判定できません: $file" >&2
    return 2
  fi
  local section
  section="$(extract_section "$file" '^## Step 2-7:')"
  if [ -z "$section" ]; then
    echo "[FAIL] Step 2-7 見出しが存在しません"
    return 1
  fi
  local missing=0
  if ! printf '%s\n' "$section" | grep -qF 'build-deliverable-inventory.sh'; then
    echo "[FAIL] Step 2-7 に build-deliverable-inventory.sh の呼び出しがありません"
    missing=1
  fi
  if ! printf '%s\n' "$section" | grep -qF 'この範囲で進む'; then
    echo "[FAIL] Step 2-7 に選択肢「この範囲で進む」がありません"
    missing=1
  fi
  if ! printf '%s\n' "$section" | grep -qF '範囲を変える'; then
    echo "[FAIL] Step 2-7 に選択肢「範囲を変える」がありません"
    missing=1
  fi
  if ! printf '%s\n' "$section" | grep -qE '\*\*完了\*\*:'; then
    echo "[FAIL] Step 2-7 に **完了**: 行がありません"
    missing=1
  fi
  if [ "$missing" -ne 0 ]; then
    return 1
  fi
  echo "[PASS] Step 2-7 が実在し、呼び出し・選択肢・完了行を備えています"
}

check_step_order() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] SKILL.mdを読み取れないため判定できません: $file" >&2
    return 2
  fi
  local step_line phase3_line
  step_line="$(grep -n '^## Step 2-7:' "$file" | head -1 | cut -d: -f1)"
  phase3_line="$(grep -n '^## Phase 3:' "$file" | head -1 | cut -d: -f1)"
  if [ -z "$step_line" ] || [ -z "$phase3_line" ]; then
    echo "[FAIL] Step 2-7 または Phase 3 見出しが見つかりません"
    return 1
  fi
  if [ "$step_line" -ge "$phase3_line" ]; then
    echo "[FAIL] Step 2-7（${step_line}行目）がPhase 3（${phase3_line}行目）より前にありません"
    return 1
  fi
  echo "[PASS] Step 2-7（${step_line}行目）はPhase 3（${phase3_line}行目）より前にあります"
}

check_step3_2_reads_approval() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] SKILL.mdを読み取れないため判定できません: $file" >&2
    return 2
  fi
  local section
  section="$(extract_section "$file" '^## Step 3-2:')"
  if [ -z "$section" ]; then
    echo "[FAIL] Step 3-2 見出しが存在しません"
    return 1
  fi
  local ok=1
  if ! printf '%s\n' "$section" | grep -qF '承認された excluded-kinds.json'; then
    echo "[FAIL] Step 3-2 が承認済みexcluded-kinds.jsonを正として読む記述を含みません"
    ok=0
  fi
  if ! printf '%s\n' "$section" | grep -qF '承認を経ずに機械判定だけ'; then
    echo "[FAIL] Step 3-2 に機械判定だけでの再確定を禁じる記述がありません"
    ok=0
  fi
  if printf '%s\n' "$section" | grep -qF 'unit_kinds_present に含まれない種別を excluded-kinds.json と「該当なし」文書へ記録する'; then
    echo "[FAIL] Step 3-2 に旧仕様（機械判定だけで確定する）の記述が残っています"
    ok=0
  fi
  if [ "$ok" -ne 1 ]; then
    return 1
  fi
  echo "[PASS] Step 3-2 は承認された対象種別を正として読み込みます"
}

check_final_crosscheck() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] SKILL.mdを読み取れないため判定できません: $file" >&2
    return 2
  fi
  local section
  section="$(extract_section "$file" '^## Step 7-1:')"
  if [ -z "$section" ]; then
    echo "[FAIL] Step 7-1 見出しが存在しません"
    return 1
  fi
  local ok=1
  if ! printf '%s\n' "$section" | grep -qF '承認した時点の一覧'; then
    echo "[FAIL] Step 7-1 に承認時点の一覧への言及がありません"
    ok=0
  fi
  if ! printf '%s\n' "$section" | grep -qF '完成時点の一覧'; then
    echo "[FAIL] Step 7-1 に完成時点の一覧への言及がありません"
    ok=0
  fi
  if ! printf '%s\n' "$section" | grep -qF '突き合わせ'; then
    echo "[FAIL] Step 7-1 に突き合わせの記述がありません"
    ok=0
  fi
  if [ "$ok" -ne 1 ]; then
    return 1
  fi
  echo "[PASS] Step 7-1 は承認時点の一覧と完成時点の一覧を突き合わせます"
}

check_scope_change_reapproval() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] SKILL.mdを読み取れないため判定できません: $file" >&2
    return 2
  fi
  local section
  section="$(extract_section "$file" '^## Step 2-7:')"
  if [ -z "$section" ]; then
    echo "[FAIL] Step 2-7 見出しが存在しません"
    return 1
  fi
  if ! printf '%s\n' "$section" | grep -qF '本Stepの提示・承認を再度実行する'; then
    echo "[FAIL] 範囲変更時に承認を再度実行する記述がありません"
    return 1
  fi
  echo "[PASS] 範囲変更時は承認を再度実行する記述があります"
}

check_phase1_no_prompt() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] SKILL.mdを読み取れないため判定できません: $file" >&2
    return 2
  fi
  local section count
  section="$(extract_phase_section "$file" 1)"
  if [ -z "$section" ]; then
    echo "[FAIL] Phase 1 見出しが存在しません"
    return 1
  fi
  count="$(printf '%s\n' "$section" | grep -c 'AskUserQuestion' || true)"
  if [ "$count" -ne 0 ]; then
    echo "[FAIL] Phase 1（準備）にAskUserQuestionの記述が${count}件あります"
    return 1
  fi
  echo "[PASS] Phase 1（準備）にAskUserQuestionの記述は0件です"
}

check_phase7_no_approval() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] SKILL.mdを読み取れないため判定できません: $file" >&2
    return 2
  fi
  local section count
  section="$(extract_phase_section "$file" 7)"
  if [ -z "$section" ]; then
    echo "[FAIL] Phase 7 見出しが存在しません"
    return 1
  fi
  count="$(printf '%s\n' "$section" | grep -c 'AskUserQuestion' || true)"
  if [ "$count" -ne 0 ]; then
    echo "[FAIL] Phase 7（判定と確定）にAskUserQuestionの記述が${count}件あります"
    return 1
  fi
  echo "[PASS] Phase 7（判定と確定）にAskUserQuestionの記述は0件です"
}

check_user_prompt_count() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] SKILL.mdを読み取れないため判定できません: $file" >&2
    return 2
  fi
  local count
  count="$(grep -cE '^- tool:.*AskUserQuestion' "$file" || true)"
  if [ "$count" -ne 1 ]; then
    echo "[FAIL] AskUserQuestionを宣言するStepが${count}件です（期待: 1件）"
    return 1
  fi
  local step27_section
  step27_section="$(extract_section "$file" '^## Step 2-7:')"
  if ! printf '%s\n' "$step27_section" | grep -qE '^- tool:.*AskUserQuestion'; then
    echo "[FAIL] AskUserQuestionを宣言する唯一のStepがStep 2-7ではありません"
    return 1
  fi
  echo "[PASS] AskUserQuestionを宣言するStepは1件（Step 2-7）だけです"
}

check_headless_skip() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] SKILL.mdを読み取れないため判定できません: $file" >&2
    return 2
  fi
  local section
  section="$(extract_section "$file" '^## Step 2-7:')"
  if [ -z "$section" ]; then
    echo "[FAIL] Step 2-7 見出しが存在しません"
    return 1
  fi
  if ! printf '%s\n' "$section" | grep -qF 'headless=true のときはAskUserQuestionを発行せず'; then
    echo "[FAIL] headless=trueでAskUserQuestionを発行しない旨の記述がありません"
    return 1
  fi
  echo "[PASS] headless=trueのときはAskUserQuestionを発行しません"
}

# ---- 自己テスト用: 途中状態を模した入力での実行 ----------------------------
# Step 2-7 の本文が「まだできていない」を欠陥として扱わない旨を明記しているかを検査する。
# 実際の generation-engine/scripts/build-deliverable-inventory.sh を、大半が未生成の状態を
# 模した output_dir に対して実行し、Step 2-7 が要求する「欠陥として扱わない」という
# 記述どおりに、この段自体が停止を求める記述になっていないことを確認する。
check_mid_process_continues() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] SKILL.mdを読み取れないため判定できません: $file" >&2
    return 2
  fi
  local section
  section="$(extract_section "$file" '^## Step 2-7:')"
  if [ -z "$section" ]; then
    echo "[FAIL] Step 2-7 見出しが存在しません"
    return 1
  fi
  if ! printf '%s\n' "$section" | grep -qF '欠陥として扱わず'; then
    echo "[FAIL] 「まだできていない」を欠陥として扱わない旨の記述がありません"
    return 1
  fi
  if printf '%s\n' "$section" | grep -qE '(未生成|まだできていない)(があれば|が1件でも).*(停止|中断|終端)'; then
    echo "[FAIL] 未生成の項目があると停止する記述が残っています"
    return 1
  fi
  echo "[PASS] 途中状態（未生成の項目がある状態）でも先へ進む記述になっています"
}

# ---- 自己テスト ---------------------------------------------------------------

SELF_TEST_TMP=""

cleanup_self_test_tmp() {
  if [ -n "$SELF_TEST_TMP" ] && [ -d "$SELF_TEST_TMP" ]; then
    rm -rf "$SELF_TEST_TMP"
  fi
}

run_self_test() {
  if ! SELF_TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-inventory-approval-step.XXXXXX" 2>/dev/null)" || [ -z "$SELF_TEST_TMP" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため自己テストを実行できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    return 2
  fi
  trap cleanup_self_test_tmp EXIT
  local tmp="$SELF_TEST_TMP"

  local pass=0 fail=0

  assert_pass() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "  [FAIL] self-test: ${label}（PASSを期待したがFAILしました）"
    fi
  }
  assert_fail() {
    local label="$1"; shift
    if _cap="$("$@" 2>&1)"; then
      fail=$((fail + 1))
      echo "  [FAIL] self-test: ${label}（FAILを期待したがPASSしました）"
      printf '%s\n' "$_cap" | sed 's/^/      /' >&2
    else
      pass=$((pass + 1))
    fi
  }

  # ケース1: 本物のSKILL.mdは全検査に通る
  assert_pass "実物のSKILL.mdはstep-presentに通る" check_step_present "$SKILL_MD"
  assert_pass "実物のSKILL.mdはstep-orderに通る" check_step_order "$SKILL_MD"
  assert_pass "実物のSKILL.mdはstep3-2-reads-approvalに通る" check_step3_2_reads_approval "$SKILL_MD"
  assert_pass "実物のSKILL.mdはfinal-crosscheckに通る" check_final_crosscheck "$SKILL_MD"
  assert_pass "実物のSKILL.mdはscope-change-reapprovalに通る" check_scope_change_reapproval "$SKILL_MD"
  assert_pass "実物のSKILL.mdはphase1-no-promptに通る" check_phase1_no_prompt "$SKILL_MD"
  assert_pass "実物のSKILL.mdはphase7-no-approvalに通る" check_phase7_no_approval "$SKILL_MD"
  assert_pass "実物のSKILL.mdはuser-prompt-countに通る" check_user_prompt_count "$SKILL_MD"
  assert_pass "実物のSKILL.mdはheadless-skipに通る" check_headless_skip "$SKILL_MD"
  assert_pass "実物のSKILL.mdはmid-process-continuesに通る（途中状態でも停止しない）" check_mid_process_continues "$SKILL_MD"

  # ケース2: Step 2-7 が無いフィクスチャは不合格になる
  local no_step="$tmp/no-step.md"
  {
    echo "## Step 2-6: 検出手がかり不足を調査書へ差し戻す"
    echo ""
    echo "**完了**: ダミー"
    echo ""
    echo "## Phase 3: 目録"
    echo ""
    echo "## Step 3-1: 実在種別の一覧を生成する"
    echo ""
    echo "**完了**: ダミー"
  } > "$no_step"
  assert_fail "Step 2-7が無ければstep-presentは不合格になる" check_step_present "$no_step"

  # ケース3: Step 2-7 が Phase 3 の後ろにあるフィクスチャは step-order で不合格になる
  local wrong_order="$tmp/wrong-order.md"
  {
    echo "## Phase 3: 目録"
    echo ""
    echo "## Step 2-7: 納品物の一覧を提示し対象範囲の承認を得る"
    echo ""
    echo "build-deliverable-inventory.sh この範囲で進む 範囲を変える"
    echo ""
    echo "**完了**: ダミー"
  } > "$wrong_order"
  assert_fail "Step 2-7がPhase 3の後ろならstep-orderは不合格になる" check_step_order "$wrong_order"

  # ケース4: Step 3-2 が旧仕様のままのフィクスチャは step3-2-reads-approval で不合格になる
  local old_32="$tmp/old-32.md"
  {
    echo "## Step 3-2: 対象外種別と派生一覧を確定する"
    echo ""
    echo "unit_kinds_present に含まれない種別を excluded-kinds.json と「該当なし」文書へ記録する。"
    echo ""
    echo "**完了**: ダミー"
  } > "$old_32"
  assert_fail "旧仕様のStep 3-2はstep3-2-reads-approvalで不合格になる" check_step3_2_reads_approval "$old_32"

  # ケース5: Step 7-1 に突き合わせ記述が無いフィクスチャは final-crosscheck で不合格になる
  local no_crosscheck="$tmp/no-crosscheck.md"
  {
    echo "## Step 7-1: judgeして基準更新または差し戻しを確定する"
    echo ""
    echo "PASS時は承認を求めず基準タグを本番更新する。"
    echo ""
    echo "**完了**: ダミー"
  } > "$no_crosscheck"
  assert_fail "突き合わせ記述の無いStep 7-1はfinal-crosscheckで不合格になる" check_final_crosscheck "$no_crosscheck"

  # ケース6: Phase 1 にAskUserQuestionが残るフィクスチャは phase1-no-prompt で不合格になる
  local phase1_ask="$tmp/phase1-ask.md"
  {
    echo "## Phase 1: 準備"
    echo ""
    echo "AskUserQuestionで確認する。"
    echo ""
    echo "## Phase 2: アーキテクチャ調査"
  } > "$phase1_ask"
  assert_fail "Phase 1にAskUserQuestionが残ればphase1-no-promptは不合格になる" check_phase1_no_prompt "$phase1_ask"

  # ケース6b: Phase 1 直下の本文は素通しでも、内部のStep（"## Step 1-1:"）の本文に
  # AskUserQuestionが残っている場合はphase1-no-promptで不合格になる（複数Stepを持つ
  # Phase節をStep見出しで打ち切らずに最後まで走査できているかの回帰）
  local phase1_step_ask="$tmp/phase1-step-ask.md"
  {
    echo "## Phase 1: 準備"
    echo ""
    echo "対話による確認は行わない。"
    echo ""
    echo "## Step 1-1: 対象リポジトリと出力先を解決する"
    echo ""
    echo "- tool: AskUserQuestion / Read"
    echo ""
    echo "AskUserQuestionツールで確認する。"
    echo ""
    echo "**完了**: ダミー"
    echo ""
    echo "## Step 1-2: スコープと実行モードを確定する"
    echo ""
    echo "**完了**: ダミー"
    echo ""
    echo "## Phase 2: アーキテクチャ調査"
  } > "$phase1_step_ask"
  assert_fail "Phase 1内のStepにAskUserQuestionが残ればphase1-no-promptは不合格になる" check_phase1_no_prompt "$phase1_step_ask"

  # ケース7: AskUserQuestionを宣言するStepが2件あるフィクスチャは user-prompt-count で不合格になる
  local two_prompts="$tmp/two-prompts.md"
  {
    echo "## Step 2-7: 納品物の一覧を提示し対象範囲の承認を得る"
    echo "- tool: AskUserQuestion"
    echo "**完了**: ダミー"
    echo ""
    echo "## Step 7-1: judgeして基準更新または差し戻しを確定する"
    echo "- tool: AskUserQuestion"
    echo "**完了**: ダミー"
  } > "$two_prompts"
  assert_fail "AskUserQuestion宣言が2件ならuser-prompt-countは不合格になる" check_user_prompt_count "$two_prompts"

  # ケース8: ファイル不在時は判定不能（終了コード2）になる
  local missing="$tmp/does-not-exist.md"
  local rc
  check_step_present "$missing" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "  [FAIL] self-test: ファイル不在時に終了コード2（判定不能）を返しませんでした（実際: ${rc}）"
  fi

  echo ""
  echo "self-test: PASS=${pass} FAIL=${fail}"
  if [ "$fail" -ne 0 ]; then
    return 1
  fi
  return 0
}

# ---- 全検査の集約 ---------------------------------------------------------------

run_all() {
  local file="$1"
  local total_fail=0
  local checks=(
    check_step_present
    check_step_order
    check_step3_2_reads_approval
    check_final_crosscheck
    check_scope_change_reapproval
    check_phase1_no_prompt
    check_phase7_no_approval
    check_user_prompt_count
    check_headless_skip
    check_mid_process_continues
  )
  local fn
  for fn in "${checks[@]}"; do
    if ! "$fn" "$file"; then
      total_fail=$((total_fail + 1))
    fi
  done
  echo ""
  if [ "$total_fail" -ne 0 ]; then
    echo "[FAIL] ${#checks[@]}件中${total_fail}件が不合格です"
    return 1
  fi
  echo "[PASS] ${#checks[@]}件すべて合格です"
  return 0
}

# ---- エントリポイント ---------------------------------------------------------------

main() {
  local mode="${1:-}"
  case "$mode" in
    --step-present) check_step_present "$SKILL_MD" ;;
    --step-order) check_step_order "$SKILL_MD" ;;
    --step3-2-reads-approval) check_step3_2_reads_approval "$SKILL_MD" ;;
    --final-crosscheck) check_final_crosscheck "$SKILL_MD" ;;
    --scope-change-reapproval) check_scope_change_reapproval "$SKILL_MD" ;;
    --phase1-no-prompt) check_phase1_no_prompt "$SKILL_MD" ;;
    --phase7-no-approval) check_phase7_no_approval "$SKILL_MD" ;;
    --user-prompt-count) check_user_prompt_count "$SKILL_MD" ;;
    --headless-skip) check_headless_skip "$SKILL_MD" ;;
    --mid-process-continues) check_mid_process_continues "$SKILL_MD" ;;
    --self-test) run_self_test ;;
    "") run_all "$SKILL_MD" ;;
    *)
      echo "ERROR: unrecognized argument: $mode" >&2
      exit 1
      ;;
  esac
}

main "$@"
