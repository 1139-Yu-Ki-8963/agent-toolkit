#!/usr/bin/env bash
# check-playwright-filename.test.sh - check-playwright-filename.sh の動作検証
#
# 観点 3 つ:
#   block      - 違反系（CWD 相対 / 許可外絶対パス）が exit 2 で block されること
#   allow      - 正常系（$CLAUDE_JOB_DIR/tmp/, tools/MCP/playwright/, docs/）が exit 0 で通ること
#   regression - filename 引数が無い呼び出し（browser_navigate 相当）が exit 0 で通ること
#
# 使い方:
#   bash ~/.claude/rules/always/placement/file-guard/check-playwright-filename.test.sh

set -u

HOOK="$(dirname "$0")/check-playwright-filename.sh"
PASS=0
FAIL=0

run_case() {
  local label="$1"
  local expected_exit="$2"
  local input_json="$3"

  printf '%s' "$input_json" | bash "$HOOK" >/dev/null 2>&1
  local actual=$?

  if [ "$actual" = "$expected_exit" ]; then
    PASS=$((PASS + 1))
    printf "  PASS  %s  (exit=%d)\n" "$label" "$actual"
  else
    FAIL=$((FAIL + 1))
    printf "  FAIL  %s  (expected=%d actual=%d)\n" "$label" "$expected_exit" "$actual"
  fi
}

run_case_env() {
  local label="$1"
  local expected_exit="$2"
  local env_assignment="$3"
  local input_json="$4"

  printf '%s' "$input_json" | env "$env_assignment" bash "$HOOK" >/dev/null 2>&1
  local actual=$?

  if [ "$actual" = "$expected_exit" ]; then
    PASS=$((PASS + 1))
    printf "  PASS  %s  (exit=%d)\n" "$label" "$actual"
  else
    FAIL=$((FAIL + 1))
    printf "  FAIL  %s  (expected=%d actual=%d)\n" "$label" "$expected_exit" "$actual"
  fi
}

echo "[block] 違反系は exit 2"
run_case "相対パス foo.png"              2 '{"tool_input":{"filename":"foo.png"}}'
run_case "相対パス screenshots/foo.png"  2 '{"tool_input":{"filename":"screenshots/foo.png"}}'
run_case "許可外絶対パス /tmp/foo.png"   2 '{"tool_input":{"filename":"/tmp/foo.png"}}'
run_case "許可外絶対パス /Users/<user>/agent-home/foo.png" 2 '{"tool_input":{"filename":"/Users/<user>/agent-home/foo.png"}}'
run_case "旧パス .playwright-mcp/ は block" 2 '{"tool_input":{"filename":"/Users/<user>/Projects/repo/.playwright-mcp/foo.png"}}'

echo "[allow] 正常系は exit 0"
run_case "\$HOME/.claude/jobs/<job>/tmp/" 0 "{\"tool_input\":{\"filename\":\"$HOME/.claude/jobs/abc123/tmp/foo.png\"}}"
run_case "tools/MCP/playwright/"          0 "{\"tool_input\":{\"filename\":\"$HOME/agent-home/tools/MCP/playwright/foo.png\"}}"
run_case "<repo>/docs/<feature>/"         0 '{"tool_input":{"filename":"/Users/<user>/Projects/repo/docs/login/screenshots/foo.png"}}'
run_case_env "CLAUDE_JOB_DIR 環境変数経由（許可）" 0 'CLAUDE_JOB_DIR=/var/lib/job' '{"tool_input":{"filename":"/var/lib/job/tmp/foo.png"}}'
run_case_env "CLAUDE_JOB_DIR 設定済みでも対象外パスは block" 2 'CLAUDE_JOB_DIR=/var/lib/job' '{"tool_input":{"filename":"/var/lib/other/foo.png"}}'

echo "[regression] filename 引数なしは exit 0"
run_case "filename キー欠落"               0 '{"tool_input":{"url":"https://example.com"}}'
run_case "tool_input 自体が空"             0 '{}'
run_case "空入力"                          0 ''

echo
printf "結果: PASS=%d FAIL=%d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
