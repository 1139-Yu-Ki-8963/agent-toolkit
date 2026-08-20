#!/usr/bin/env bash
# check-plan-tacit-knowledge-gate.test.sh — check-plan-tacit-knowledge-gate.sh の回帰テスト。
# 素通り(G*)・block(B*)・消費機構（両ゲート合算）・自動解除・未展開文字列の誤カウント防止を網羅する。
# 実行: bash check-plan-tacit-knowledge-gate.test.sh（全ケース PASS で exit 0）
set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/check-plan-tacit-knowledge-gate.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/plan-tacit-gate-test.XXXXXX")"
SESSION="plan-tacit-gate-test-$$"
LOG_DIR="$HOME/agent-home/sessions/.skill-log"
LOG="$LOG_DIR/${SESSION}.jsonl"
mkdir -p "$LOG_DIR"
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

mkjson() {
  jq -n --arg tool "$1" --arg s "$SESSION" --arg tp "$2" \
    '{tool_name:$tool, session_id:$s, transcript_path:$tp}'
}

t_empty="$TMP/empty.jsonl"; : > "$t_empty"

rm -f "$LOG"
run "G1 ExitPlanMode 以外は素通り" 0 "$(mkjson Bash "$t_empty")"

run "B1 発火なしで block" 2 "$(mkjson ExitPlanMode "$t_empty")"

printf '{"ts":"2026-07-18T00:00:00Z","skill":"eliciting-plan-tacit-knowledge"}\n' > "$LOG"
run "G2 発火 1・消費 0 で通過" 0 "$(mkjson ExitPlanMode "$t_empty")" "[PLAN-TACIT-KNOWLEDGE-GATE-PASS](fired=1 consumed=0)"

t_c1="$TMP/consumed-exit.jsonl"
printf '%s\n' "[PLAN-TACIT-KNOWLEDGE-GATE-PASS](fired=1 consumed=0) 通過済み" > "$t_c1"
run "B2 消費済み（ExitPlanMode 側）で block" 2 "$(mkjson ExitPlanMode "$t_c1")"

t_c2="$TMP/consumed-write.jsonl"
printf '%s\n' "[PLAN-DRAFT-WRITE-GATE-PASS](fired=1 consumed=0) 通過済み" > "$t_c2"
run "B3 消費済み（Write 側合算）で block" 2 "$(mkjson ExitPlanMode "$t_c2")"

t_raw="$TMP/unexpanded.jsonl"
printf '%s\n' "[PLAN-TACIT-KNOWLEDGE-GATE-PASS](fired=N consumed=M) ドキュメント引用" > "$t_raw"
run "G3 未展開文字列は消費に数えない" 0 "$(mkjson ExitPlanMode "$t_raw")"

rm -f "$LOG"
t_b3="$TMP/blocks3.jsonl"
{
  printf '%s\n' "[PLAN-TACIT-KNOWLEDGE-GATE-BLOCK](fired=0 consumed=0) x"
  printf '%s\n' "[PLAN-TACIT-KNOWLEDGE-GATE-BLOCK](fired=0 consumed=0) x"
  printf '%s\n' "[PLAN-TACIT-KNOWLEDGE-GATE-BLOCK](fired=0 consumed=0) x"
} > "$t_b3"
run "G4 block 3 回で自動解除" 0 "$(mkjson ExitPlanMode "$t_b3")"

rc=0
printf '%s' "$(mkjson ExitPlanMode "$t_empty")" | CLAUDE_HOOKS_TEST=1 "$HOOK" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then pass_n=$((pass_n + 1)); echo "PASS: G5 CLAUDE_HOOKS_TEST で素通り"; else fail_n=$((fail_n + 1)); echo "FAIL: G5 CLAUDE_HOOKS_TEST で素通り (exit=$rc)"; fi

echo "----"
echo "PASS ${pass_n} / FAIL ${fail_n}"
[ "$fail_n" -eq 0 ]
