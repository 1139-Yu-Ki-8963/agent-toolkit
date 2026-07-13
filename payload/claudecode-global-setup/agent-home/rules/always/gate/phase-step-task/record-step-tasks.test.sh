#!/usr/bin/env bash
# record-step-tasks.sh の回帰テスト（7 ケース）
# 実行: bash record-step-tasks.test.sh → exit 0（全 PASS）/ 1（FAIL あり）
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/record-step-tasks.sh"
TMPROOT="$(mktemp -d)"
WORKDIR="$TMPROOT/work"
mkdir -p "$WORKDIR"
# marker_path() は固定パス /tmp/claude-hooks/${session} を使う（TMPDIR に依存しない）。
# セッション ID は PID でユニーク化し、並列実行・多重実行時の衝突を避ける。
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

count_of() { cat "$MARKER_DIR/phase-step-task-count-$1" 2>/dev/null || echo 0; }

# R1: 形式合致 subject → カウンタ 1
reset_markers
run_case 'Phase 3 Step 3-1: rule.md を作成する'
assert "$([ "$RC" -eq 0 ] && [ "$(count_of 3)" = '1' ]; echo $?)" '形式合致でカウント 1'

# R2: 2 回目の形式合致 → カウンタ 2
run_case 'Phase 3 Step 3-2: hook を作成する'
assert "$([ "$RC" -eq 0 ] && [ "$(count_of 3)" = '2' ]; echo $?)" '形式合致でカウント 2'

# R3: phase/step 番号不一致 + フロー実行中 → advisory + カウント非加算
reset_markers
mkdir -p "$MARKER_DIR"; printf '{}' > "$MARKER_DIR/flow-status.json"
run_case 'Phase 3 Step 2-1: 番号が食い違うタスク'
assert "$([ "$RC" -eq 0 ] && grep -q 'STEP-TASK-FORMAT' "$STDOUT_LOG" && [ "$(count_of 3)" = '0' ]; echo $?)" '番号不一致は advisory・非加算'

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
assert "$([ "$RC" -eq 0 ] && [ "$(count_of D)" = '1' ]; echo $?)" 'Phase D 形式合致カウント'

printf '\n%s PASS / %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
