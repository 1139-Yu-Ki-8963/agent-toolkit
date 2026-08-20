#!/usr/bin/env bash
# record-step-tasks.sh の回帰テスト（9 ケース）
# 実行: bash record-step-tasks.test.sh → exit 0（全 PASS）/ 1（FAIL あり）
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/record-step-tasks.sh"
TMPROOT="$(mktemp -d)"
WORKDIR="$TMPROOT/work"
mkdir -p "$WORKDIR"
SESSION="testsession-$$"
MARKER_DIR="/tmp/claude-hooks/$SESSION"
PASS=0
FAIL=0

cleanup() { rm -rf "$TMPROOT" "$MARKER_DIR"; }
trap cleanup EXIT

reset_markers() { rm -rf "$MARKER_DIR"; }

run_case() { # $1=subject（空文字なら subject なし入力）
  local json
  if [ -n "$1" ]; then
    json=$(jq -n --arg subject "$1" --arg cwd "$WORKDIR" --arg session "$SESSION" \
      '{session_id: $session, cwd: $cwd, tool_input: {subject: $subject, description: "x"}}')
  else
    json=$(jq -n --arg cwd "$WORKDIR" --arg session "$SESSION" \
      '{session_id: $session, cwd: $cwd, tool_input: {file_path: "/tmp/x"}}')
  fi
  STDOUT_LOG="$TMPROOT/stdout.log"
  printf '%s' "$json" | bash "$SCRIPT" > "$STDOUT_LOG" 2> "$TMPROOT/stderr.log"
  RC=$?
}

assert() { # $1=期待値判定(0/1) $2=ケース名
  if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); printf 'PASS: %s\n' "$2"
  else FAIL=$((FAIL+1)); printf 'FAIL: %s (rc=%s)\n' "$2" "$RC"; fi
}

# R1: 形式合致 subject → transcript 用タグを出力
reset_markers
run_case 'Phase 3 Step 3-1: rule.md を作成する'
assert "$([ "$RC" -eq 0 ] && grep -q 'STEP-TASK-RECORDED:3:1' "$STDOUT_LOG"; echo $?)" '形式合致で記録タグ'

# R2: 別stepも同じphaseの記録タグを出力
run_case 'Phase 3 Step 3-2: hook を作成する'
assert "$([ "$RC" -eq 0 ] && grep -q 'STEP-TASK-RECORDED:3:2' "$STDOUT_LOG"; echo $?)" '2件目も記録タグ'

# R3: phase/step 番号不一致 + フロー実行中 → advisory・記録タグなし
reset_markers
mkdir -p "$MARKER_DIR"; printf '{}' > "$MARKER_DIR/flow-status.json"
run_case 'Phase 3 Step 2-1: 番号が食い違うタスク'
assert "$([ "$RC" -eq 0 ] && grep -q 'STEP-TASK-FORMAT' "$STDOUT_LOG" && ! grep -q 'STEP-TASK-RECORDED' "$STDOUT_LOG"; echo $?)" '番号不一致は advisory・非記録'

# R4: 形式違反 + フロー実行中 → advisory
reset_markers
mkdir -p "$MARKER_DIR"; printf '{}' > "$MARKER_DIR/flow-status.json"
run_case 'Phase 3 の作業をまとめてやる'
assert "$([ "$RC" -eq 0 ] && grep -q 'STEP-TASK-FORMAT' "$STDOUT_LOG"; echo $?)" '形式違反は advisory'

# R5: 形式違反 + フロー外 → 沈黙して素通り
reset_markers
run_case '普通のタスク'
assert "$([ "$RC" -eq 0 ] && [ ! -s "$STDOUT_LOG" ]; echo $?)" 'フロー外は沈黙'

# R6: subject なし入力 → 素通り
reset_markers
run_case ''
assert "$([ "$RC" -eq 0 ] && [ ! -s "$STDOUT_LOG" ]; echo $?)" 'subject なし素通り'

# R7: Phase D の形式合致 → カウンタ加算
reset_markers
run_case 'Phase D Step D-1: ドキュメントを修正する'
assert "$([ "$RC" -eq 0 ] && grep -q 'STEP-TASK-RECORDED:D:1' "$STDOUT_LOG"; echo $?)" 'Phase D 形式合致記録'

# R8: Codex update_plan の pending/in_progress 複数stepを一括記録し、completedは再記録しない
reset_markers
json=$(jq -nc --arg cwd "$WORKDIR" --arg session "$SESSION" '{
  session_id:$session,
  cwd:$cwd,
  tool_name:"update_plan",
  tool_input:{plan:[
    {step:"Phase 4 Step 4-1: 仕様を確定する",status:"in_progress"},
    {step:"Phase 4 Step 4-2: 実装を検証する",status:"pending"},
    {step:"Phase 4 Step 4-3: 完了済み作業",status:"completed"}
  ]}
}')
printf '%s' "$json" | bash "$SCRIPT" >"$TMPROOT/codex-plan.log"
plan_rc=$?
assert "$([ "$plan_rc" -eq 0 ] \
  && grep -q 'STEP-TASK-RECORDED:4:1' "$TMPROOT/codex-plan.log" \
  && grep -q 'STEP-TASK-RECORDED:4:2' "$TMPROOT/codex-plan.log" \
  && ! grep -q 'STEP-TASK-RECORDED:4:3' "$TMPROOT/codex-plan.log"; echo $?)" \
  'Codex update_plan 複数step記録'

# R9: linked worktree では共有 marker_path の flow-status を参照する
MAIN_REPO="$TMPROOT/main-repo"
LINKED_WORKTREE="$TMPROOT/linked-worktree"
git init -q "$MAIN_REPO"
git -C "$MAIN_REPO" config user.email test@example.com
git -C "$MAIN_REPO" config user.name test
touch "$MAIN_REPO/seed"
git -C "$MAIN_REPO" add seed
git -C "$MAIN_REPO" commit -qm seed
git -C "$MAIN_REPO" worktree add -qb test-worktree "$LINKED_WORKTREE"
WORKTREE_MARKER="$LINKED_WORKTREE/.claude/markers/$SESSION"
mkdir -p "$WORKTREE_MARKER"
printf '{}' >"$WORKTREE_MARKER/flow-status.json"
json=$(jq -nc --arg cwd "$LINKED_WORKTREE" --arg session "$SESSION" '{
  session_id:$session,
  cwd:$cwd,
  tool_input:{subject:"形式違反のフロータスク"}
}')
printf '%s' "$json" | bash "$SCRIPT" >"$TMPROOT/worktree-marker.log"
worktree_rc=$?
assert "$([ "$worktree_rc" -eq 0 ] \
  && grep -q 'STEP-TASK-FORMAT' "$TMPROOT/worktree-marker.log"; echo $?)" \
  'linked worktree の共有 flow-status を参照'

printf '\n%s PASS / %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
