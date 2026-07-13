#!/usr/bin/env bash
# check-phase-entry-tasks.sh の回帰テスト（9 ケース）
# 実行: bash check-phase-entry-tasks.test.sh → exit 0（全 PASS）/ 1（FAIL あり）
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-phase-entry-tasks.sh"
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

run_case() { # $1=command 文字列
  local json
  json=$(jq -n --arg cmd "$1" --arg cwd "$WORKDIR" --arg session "$SESSION" \
    '{session_id: $session, cwd: $cwd, tool_input: {command: $cmd}}')
  STDERR_LOG="$TMPROOT/stderr.log"
  printf '%s' "$json" | bash "$SCRIPT" > "$TMPROOT/stdout.log" 2> "$STDERR_LOG"
  RC=$?
}

assert() { # $1=期待値判定(0/1) $2=ケース名
  if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); printf 'PASS: %s\n' "$2"
  else FAIL=$((FAIL+1)); printf 'FAIL: %s (rc=%s)\n' "$2" "$RC"; fi
}

UFS='bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh'

# C1: 非対象コマンドは素通り
reset_markers
run_case 'git status'
assert "$([ "$RC" -eq 0 ]; echo $?)" '非対象コマンド素通り'

# C2: --init は素通り
reset_markers
run_case "$UFS --init feature-with-full-planning"
assert "$([ "$RC" -eq 0 ]; echo $?)" '--init 素通り'

# C3: 新 phase 突入 + カウンタなし → block
reset_markers
run_case "$UFS 3 \"計画\" 0 5 \"設計書作成\""
assert "$([ "$RC" -eq 2 ] && grep -q 'PHASE-TASK-BLOCK' "$STDERR_LOG"; echo $?)" '新phase・カウンタなし block'

# C4: 新 phase 突入 + カウンタ不足（2/5）→ block
reset_markers
mkdir -p "$MARKER_DIR"; printf '2' > "$MARKER_DIR/phase-step-task-count-3"
run_case "$UFS 3 \"計画\" 0 5 \"設計書作成\""
assert "$([ "$RC" -eq 2 ] && grep -q '登録 2 / 必要 5' "$STDERR_LOG"; echo $?)" '新phase・カウンタ不足 block'

# C5: 新 phase 突入 + カウンタ充足（5/5）→ 通過 + last-phase 記録
reset_markers
mkdir -p "$MARKER_DIR"; printf '5' > "$MARKER_DIR/phase-step-task-count-3"
run_case "$UFS 3 \"計画\" 0 5 \"設計書作成\""
assert "$([ "$RC" -eq 0 ] && [ "$(cat "$MARKER_DIR/phase-step-task-last-phase")" = '3' ]; echo $?)" '充足通過・last-phase 記録'

# C6: 同一 phase の step 更新はカウンタなしでも素通り
reset_markers
mkdir -p "$MARKER_DIR"; printf '3' > "$MARKER_DIR/phase-step-task-last-phase"
run_case "$UFS 3 \"計画\" 2 5 \"レビュー\""
assert "$([ "$RC" -eq 0 ]; echo $?)" '同一phase step更新素通り'

# C7: Phase D は素通り
reset_markers
run_case "$UFS D \"ドキュメント\" 0 3 \"編集\""
assert "$([ "$RC" -eq 0 ]; echo $?)" 'Phase D 素通り'

# C8: Phase I は素通り
reset_markers
run_case "$UFS I \"インシデント\" 0 3 \"復旧\""
assert "$([ "$RC" -eq 0 ]; echo $?)" 'Phase I 素通り'

# C9: 引数不足（パース不能）は fail-safe 素通り
reset_markers
run_case "$UFS 3"
assert "$([ "$RC" -eq 0 ]; echo $?)" 'パース不能 fail-safe'

# C10: 行継続（\ + 改行）付きコマンド + カウンタ不足 → block（実機検証 #1 で検出した回帰）
reset_markers
run_case "$(printf '%s \\\n  4 "実装" 0 3 "コード作成"' "$UFS")"
assert "$([ "$RC" -eq 2 ] && grep -q 'PHASE-TASK-BLOCK' "$STDERR_LOG"; echo $?)" '行継続コマンドでも block'

# C11: 行継続付き + カウンタ充足 → 通過
reset_markers
mkdir -p "$MARKER_DIR"; printf '3' > "$MARKER_DIR/phase-step-task-count-4"
run_case "$(printf '%s \\\n  4 "実装" 0 3 "コード作成"' "$UFS")"
assert "$([ "$RC" -eq 0 ] && [ "$(cat "$MARKER_DIR/phase-step-task-last-phase")" = '4' ]; echo $?)" '行継続コマンドで充足通過'

printf '\n%s PASS / %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
