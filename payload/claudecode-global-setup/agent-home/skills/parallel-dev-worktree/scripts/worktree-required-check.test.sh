#!/bin/bash
# check-worktree-required.sh のテスト (issue#1578)
#
# ADR 0030 / 0038 C1 統一: subagent (agent_id 持ち) は本 hook で素通りし、
# 後続 Hook 3 (check-orchestrator-cwd-write.sh) で正規判定する。
# 指揮官セッション本体 (agent_id 無し) は従来通り block される。
#
# 実行: bash worktree-required-check.test.sh
# 戻り値: 0=全 PASS / 1=1 件以上 FAIL
set -u

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-worktree-required.sh"
pass=0
fail=0
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# メイン作業ツリー擬装: 実際の git init で .git をディレクトリにする
MAIN_REPO="$TMPROOT/main-repo"
git init -q "$MAIN_REPO"
mkdir -p "$MAIN_REPO/src"

# worktree 擬装: git worktree add で .git をファイル形式にする
# (テスト用に最小コミットを入れてから worktree add)
(
  cd "$MAIN_REPO" && git -c user.email=test@test -c user.name=test commit \
    --allow-empty -q -m init
) >/dev/null 2>&1
WT_REPO="$TMPROOT/wt-repo"
git -C "$MAIN_REPO" worktree add -q "$WT_REPO" -b wt-test >/dev/null 2>&1 || {
  # fallback: .git ファイル形式を手動で作る
  mkdir -p "$WT_REPO"
  echo "gitdir: $MAIN_REPO/.git/worktrees/wt-test" > "$WT_REPO/.git"
  mkdir -p "$MAIN_REPO/.git/worktrees/wt-test"
  echo "$WT_REPO/.git" > "$MAIN_REPO/.git/worktrees/wt-test/gitdir"
  echo "../../.." > "$MAIN_REPO/.git/worktrees/wt-test/commondir"
}

run_case() { # $1=case_id $2=stdin_json
  STDOUT_LOG="$TMPROOT/stdout_$1"
  STDERR_LOG="$TMPROOT/stderr_$1"
  printf '%s' "$2" | bash "$SCRIPT" > "$STDOUT_LOG" 2> "$STDERR_LOG"
  RC=$?
}

assert_exit() {
  if [ "$RC" -eq "$1" ]; then
    pass=$((pass+1)); printf '  PASS: %s (exit %s)\n' "$2" "$RC"
  else
    fail=$((fail+1)); printf '  FAIL: %s (expected exit %s, got %s)\n' "$2" "$1" "$RC"
    printf '    stderr: %s\n' "$(cat "$STDERR_LOG")"
    printf '    stdout: %s\n' "$(cat "$STDOUT_LOG")"
  fi
}

assert_stdout_contains() {
  if grep -qF "$2" "$STDOUT_LOG"; then
    pass=$((pass+1)); printf '  PASS: %s\n' "$1"
  else
    fail=$((fail+1)); printf '  FAIL: %s (stdout did not contain "%s")\n' "$1" "$2"
    printf '    stdout: %s\n' "$(cat "$STDOUT_LOG")"
  fi
}

echo "=== check-worktree-required.sh tests ==="

# W1: 通常セッション (agent_id 無し) + メイン作業ツリー編集 → block
JSON1=$(jq -nc --arg fp "$MAIN_REPO/src/foo.txt" \
  '{tool_input:{file_path:$fp}}')
run_case w1 "$JSON1"
assert_exit 0 "W1 通常セッションでメイン編集は exit 0 (JSON で block 出力)"
assert_stdout_contains "W1 WORKTREE-REQUIRED ブロック出力" "WORKTREE-REQUIRED"
assert_stdout_contains "W1 decision:block 含む" "block"

# W2 (issue#1578): subagent (agent_id) + メイン作業ツリー編集 → 素通り (exit 0、JSON 出力なし)
JSON2=$(jq -nc --arg fp "$MAIN_REPO/src/foo.txt" \
  '{agent_id:"sub-123", tool_input:{file_path:$fp}}')
run_case w2 "$JSON2"
assert_exit 0 "W2 subagent agent_id 持ちで素通り exit 0"
if [ ! -s "$STDOUT_LOG" ]; then
  pass=$((pass+1)); printf '  PASS: W2 出力なし (素通り)\n'
else
  fail=$((fail+1)); printf '  FAIL: W2 stdout に出力あり: %s\n' "$(cat "$STDOUT_LOG")"
fi

# W3 (issue#1578): subagent (agentId キャメルケース) + メイン作業ツリー編集 → 素通り
JSON3=$(jq -nc --arg fp "$MAIN_REPO/src/foo.txt" \
  '{agentId:"sub-456", tool_input:{file_path:$fp}}')
run_case w3 "$JSON3"
assert_exit 0 "W3 subagent agentId キャメルケースで素通り exit 0"
if [ ! -s "$STDOUT_LOG" ]; then
  pass=$((pass+1)); printf '  PASS: W3 出力なし (素通り)\n'
else
  fail=$((fail+1)); printf '  FAIL: W3 stdout に出力あり\n'
fi

# W4: 通常セッション + worktree 編集 → 素通り
JSON4=$(jq -nc --arg fp "$WT_REPO/foo.txt" \
  '{tool_input:{file_path:$fp}}')
run_case w4 "$JSON4"
assert_exit 0 "W4 worktree 内編集は素通り exit 0"
if [ ! -s "$STDOUT_LOG" ]; then
  pass=$((pass+1)); printf '  PASS: W4 出力なし (素通り)\n'
else
  fail=$((fail+1)); printf '  FAIL: W4 stdout に出力あり\n'
fi

# W5: file_path 無し → 素通り
JSON5='{"tool_input":{}}'
run_case w5 "$JSON5"
assert_exit 0 "W5 file_path 無しで素通り exit 0"

# W6: ~/.claude/* 配下は例外
JSON6=$(jq -nc --arg fp "$HOME/.claude/CLAUDE.md" \
  '{tool_input:{file_path:$fp}}')
run_case w6 "$JSON6"
assert_exit 0 "W6 ~/.claude/* は例外で素通り"

# W7: ~/agent-home/* 配下は例外
JSON7=$(jq -nc --arg fp "$HOME/agent-home/skills/foo/SKILL.md" \
  '{tool_input:{file_path:$fp}}')
run_case w7 "$JSON7"
assert_exit 0 "W7 ~/agent-home/* は例外で素通り"

echo ""
echo "=== result: ${pass} passed, ${fail} failed ==="
[ "$fail" -eq 0 ]
