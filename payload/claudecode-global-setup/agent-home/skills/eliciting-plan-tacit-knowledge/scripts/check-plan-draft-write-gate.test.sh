#!/usr/bin/env bash
# check-plan-draft-write-gate.test.sh — check-plan-draft-write-gate.sh の回帰テスト。
# パスフィルタ・agent_id スキップ・既存ファイルスキップ・消費機構（両ゲート合算）・自動解除を網羅する。
# 実行: bash check-plan-draft-write-gate.test.sh（全ケース PASS で exit 0）
set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/check-plan-draft-write-gate.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/plan-draft-gate-test.XXXXXX")"
SESSION="plan-draft-gate-test-$$"
LOG_DIR="$HOME/agent-home/sessions/.skill-log"
LOG="$LOG_DIR/${SESSION}.jsonl"
mkdir -p "$LOG_DIR"
PLAN_DIR="$TMP/.claude/plans"
mkdir -p "$PLAN_DIR"
PLAN_NEW="$PLAN_DIR/new-plan.md"
cleanup() { rm -rf "$TMP"; rm -f "$LOG"; }
trap cleanup EXIT

pass_n=0
fail_n=0

run() {
  local name="$1" expected="$2" json="$3" must="${4:-}" rc=0 out
  out="$(printf '%s' "$json" | env -u CLAUDE_HOOKS_TEST -u CLAUDE_HOOK_SUMMARY_RUNNING -u CLAUDE_HOOK_FLOW_REPORT_RUNNING "$HOOK" 2>/dev/null)" || rc=$?
  if [ "$rc" -ne "$expected" ]; then
    fail_n=$((fail_n + 1)); echo "FAIL: $name (exit expected=$expected actual=$rc)"; return
  fi
  if [ -n "$must" ] && ! printf '%s' "$out" | grep -qF "$must"; then
    fail_n=$((fail_n + 1)); echo "FAIL: $name (stdout に $must が無い)"; return
  fi
  pass_n=$((pass_n + 1)); echo "PASS: $name"
}

# mkjson <tool> <file_path> <transcript_path> <agent_id>
mkjson() {
  jq -n --arg tool "$1" --arg fp "$2" --arg s "$SESSION" --arg tp "$3" --arg aid "$4" \
    '{tool_name:$tool, session_id:$s, transcript_path:$tp, tool_input:{file_path:$fp}, agent_id:$aid}'
}

t_empty="$TMP/empty.jsonl"; : > "$t_empty"

rm -f "$LOG"
run "G1 Write 以外は素通り" 0 "$(mkjson Edit "$PLAN_NEW" "$t_empty" "")"

run "G2 計画ファイル以外のパスは素通り" 0 "$(mkjson Write "$TMP/other.md" "$t_empty" "")"

run "G3 agent_id 非空は素通り" 0 "$(mkjson Write "$PLAN_NEW" "$t_empty" "worker-sonnet")"

PLAN_EXIST="$PLAN_DIR/existing-plan.md"
printf 'x\n' > "$PLAN_EXIST"
run "G4 既存ファイルへの Write は素通り" 0 "$(mkjson Write "$PLAN_EXIST" "$t_empty" "")"

run "B1 発火なしで block" 2 "$(mkjson Write "$PLAN_NEW" "$t_empty" "")"

PLAN_DIR_ALT="$TMP/.claude-custom/plans"
mkdir -p "$PLAN_DIR_ALT"
run "B1b 別名の設定ディレクトリ（.claude-* 系）配下の計画ファイルも block" 2 "$(mkjson Write "$PLAN_DIR_ALT/new-plan.md" "$t_empty" "")"

printf '{"ts":"2026-07-18T00:00:00Z","skill":"eliciting-plan-tacit-knowledge"}\n' > "$LOG"
run "G5 発火 1・消費 0 で通過" 0 "$(mkjson Write "$PLAN_NEW" "$t_empty" "")" "[PLAN-DRAFT-WRITE-GATE-PASS](fired=1 consumed=0)"

t_c1="$TMP/consumed-write.jsonl"
printf '%s\n' "[PLAN-DRAFT-WRITE-GATE-PASS](fired=1 consumed=0) 通過済み" > "$t_c1"
run "B2 消費済み（Write 側）で block" 2 "$(mkjson Write "$PLAN_NEW" "$t_c1" "")"

t_c2="$TMP/consumed-exit.jsonl"
printf '%s\n' "[PLAN-TACIT-KNOWLEDGE-GATE-PASS](fired=1 consumed=0) 通過済み" > "$t_c2"
run "B3 消費済み（ExitPlanMode 側合算）で block" 2 "$(mkjson Write "$PLAN_NEW" "$t_c2" "")"

rm -f "$LOG"
t_b3="$TMP/blocks3.jsonl"
{
  printf '%s\n' "[PLAN-DRAFT-WRITE-GATE-BLOCK](fired=0 consumed=0) x"
  printf '%s\n' "[PLAN-DRAFT-WRITE-GATE-BLOCK](fired=0 consumed=0) x"
  printf '%s\n' "[PLAN-DRAFT-WRITE-GATE-BLOCK](fired=0 consumed=0) x"
} > "$t_b3"
run "G6 block 3 回で自動解除" 0 "$(mkjson Write "$PLAN_NEW" "$t_b3" "")"

rc=0
printf '%s' "$(mkjson Write "$PLAN_NEW" "$t_empty" "")" | CLAUDE_HOOKS_TEST=1 "$HOOK" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then pass_n=$((pass_n + 1)); echo "PASS: G7 CLAUDE_HOOKS_TEST で素通り"; else fail_n=$((fail_n + 1)); echo "FAIL: G7 CLAUDE_HOOKS_TEST で素通り (exit=$rc)"; fi

echo "----"
echo "PASS ${pass_n} / FAIL ${fail_n}"
[ "$fail_n" -eq 0 ]
