#!/usr/bin/env bash
set -u

HOOK="$(dirname "$0")/check-identifier-naming.sh"
pass=0 fail=0

run_test() {
  local name="$1" input="$2" expect_exit="$3"
  actual_exit=0
  output=$(echo "$input" | bash "$HOOK" 2>&1) || actual_exit=$?
  if [ "$actual_exit" -eq "$expect_exit" ]; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name (expected exit $expect_exit, got $actual_exit)"
    echo "  output: $output"
    fail=$((fail + 1))
  fi
}

# T1: 禁止動詞 nuke- → block (exit 2)
run_test "nuke-prefix-block" \
  '{"tool_name":"Write","tool_input":{"file_path":"/Users/<user>/.claude/rules/always/session/infra/nuke-something.sh","content":"#!/bin/bash\nexit 0"},"tool_result":{"was_created":"true"}}' \
  2

# T2: 禁止動詞 scrub- → block (exit 2)
run_test "scrub-prefix-block" \
  '{"tool_name":"Write","tool_input":{"file_path":"/Users/<user>/.claude/rules/always/placement/file-guard/scrub-old-files.sh","content":"#!/bin/bash"},"tool_result":{"was_created":"true"}}' \
  2

# T3: 単独 main → block (exit 2)
run_test "standalone-main-block" \
  '{"tool_name":"Write","tool_input":{"file_path":"/Users/<user>/.claude/rules/always/agent/subagent-selection/check-main-work.sh","content":"#!/bin/bash"},"tool_result":{"was_created":"true"}}' \
  2

# T4: main-agent → pass (exit 0)
run_test "main-agent-allowed" \
  '{"tool_name":"Write","tool_input":{"file_path":"/Users/<user>/.claude/rules/always/agent/subagent-selection/check-main-agent-direct-work.sh","content":"#!/bin/bash"},"tool_result":{"was_created":"true"}}' \
  0

# T5: 正常な命名 → pass (exit 0)
run_test "normal-name-pass" \
  '{"tool_name":"Write","tool_input":{"file_path":"/Users/<user>/.claude/rules/always/naming/common-principles/check-identifier-naming.sh","content":"#!/bin/bash"},"tool_result":{"was_created":"true"}}' \
  0

# T6: 対象外パス → pass (exit 0)
run_test "non-target-path-pass" \
  '{"tool_name":"Write","tool_input":{"file_path":"/Users/<user>/Projects/some-project/scripts/nuke-db.sh","content":"#!/bin/bash"},"tool_result":{"was_created":"true"}}' \
  0

# T7: .sh 以外 → pass (exit 0)
run_test "non-sh-pass" \
  '{"tool_name":"Write","tool_input":{"file_path":"/Users/<user>/.claude/rules/always/naming/common-principles/rule.md","content":"# test"},"tool_result":{"was_created":"true"}}' \
  0

# T8: Edit (not Write) → pass (exit 0)
run_test "edit-not-write-pass" \
  '{"tool_name":"Edit","tool_input":{"file_path":"/Users/<user>/.claude/rules/always/session/infra/nuke-something.sh"},"tool_result":{}}' \
  0

echo ""
echo "Results: $pass PASS, $fail FAIL"
[ "$fail" -eq 0 ] && exit 0 || exit 1
