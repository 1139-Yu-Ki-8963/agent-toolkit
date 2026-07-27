#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/config/codex"
registry="$test_tmp/registry.json"
cat >"$registry" <<'JSON'
{
  "commands": {
    "session-test": {
      "sourceEvent": "SessionStart",
      "matcher": "*",
      "command": "true"
    },
    "prompt-test": {
      "sourceEvent": "UserPromptSubmit",
      "matcher": "*",
      "command": "true"
    },
    "pretool-test": {
      "sourceEvent": "PreToolUse",
      "matcher": "Bash",
      "command": "jq -r '.current_prompt_sha256 // empty' > \"$CAPTURE_FILE\""
    },
    "stop-test": {
      "sourceEvent": "Stop",
      "matcher": "*",
      "command": "jq -r '.current_prompt_sha256 // empty' > \"$CAPTURE_FILE\""
    },
    "plan-record-test": {
      "sourceEvent": "PostToolUse",
      "matcher": "TaskCreate",
      "command": "bash \"$RECORD_SCRIPT\""
    }
  }
}
JSON

printf '%s' '{"session_id":"adapter-test","cwd":"/tmp"}' |
  AGENT_HOME_ROOT="$test_tmp" CODEX_HOOK_REGISTRY="$registry" \
  "$here/hook-command-adapter.sh" SessionStart session-test >/dev/null

if [ -e "$test_tmp/sessions/.skill-log/adapter-test.jsonl" ]; then
  echo "fake bootstrap skill log was generated" >&2
  exit 1
fi
if rg -n 'codex-session-start-bootstrap|skill_log=' "$here/hook-command-adapter.sh" >/dev/null; then
  echo "fake bootstrap implementation remains" >&2
  exit 1
fi

prompt="Codex turn hash"
printf '%s' "$(jq -nc --arg prompt "$prompt" \
  '{session_id:"adapter-test",cwd:"/tmp",prompt:$prompt}')" |
  TMPDIR="$test_tmp" AGENT_HOME_ROOT="$test_tmp" CODEX_HOOK_REGISTRY="$registry" \
  "$here/hook-command-adapter.sh" UserPromptSubmit prompt-test >/dev/null

capture="$test_tmp/captured-sha"
printf '%s' '{"session_id":"adapter-test","cwd":"/tmp","tool_input":{}}' |
  TMPDIR="$test_tmp" AGENT_HOME_ROOT="$test_tmp" CODEX_HOOK_REGISTRY="$registry" \
  CAPTURE_FILE="$capture" "$here/hook-command-adapter.sh" PreToolUse pretool-test >/dev/null
expected_sha=$(printf '%s' "$prompt" | shasum -a 256 | awk '{print $1}')
test "$(cat "$capture")" = "$expected_sha"

stop_capture="$test_tmp/captured-stop-sha"
printf '%s' '{"session_id":"adapter-test","cwd":"/tmp"}' |
  TMPDIR="$test_tmp" AGENT_HOME_ROOT="$test_tmp" CODEX_HOOK_REGISTRY="$registry" \
  CAPTURE_FILE="$stop_capture" "$here/hook-command-adapter.sh" Stop stop-test >/dev/null
test "$(cat "$stop_capture")" = "$expected_sha"

# Stop consumes the turn state. A later event without UserPromptSubmit must not
# receive the completed turn's hash.
post_stop_capture="$test_tmp/captured-post-stop-sha"
printf '%s' '{"session_id":"adapter-test","cwd":"/tmp","tool_input":{}}' |
  TMPDIR="$test_tmp" AGENT_HOME_ROOT="$test_tmp" CODEX_HOOK_REGISTRY="$registry" \
  CAPTURE_FILE="$post_stop_capture" "$here/hook-command-adapter.sh" PreToolUse pretool-test >/dev/null
test ! -s "$post_stop_capture"

# A prompt event without a prompt fails closed and clears an existing hash.
printf '%s' "$(jq -nc --arg prompt "stale prompt" \
  '{session_id:"adapter-test",cwd:"/tmp",prompt:$prompt}')" |
  TMPDIR="$test_tmp" AGENT_HOME_ROOT="$test_tmp" CODEX_HOOK_REGISTRY="$registry" \
  "$here/hook-command-adapter.sh" UserPromptSubmit prompt-test >/dev/null
printf '%s' '{"session_id":"adapter-test","cwd":"/tmp"}' |
  TMPDIR="$test_tmp" AGENT_HOME_ROOT="$test_tmp" CODEX_HOOK_REGISTRY="$registry" \
  "$here/hook-command-adapter.sh" UserPromptSubmit prompt-test >/dev/null
missing_prompt_capture="$test_tmp/captured-missing-prompt-sha"
printf '%s' '{"session_id":"adapter-test","cwd":"/tmp","tool_input":{}}' |
  TMPDIR="$test_tmp" AGENT_HOME_ROOT="$test_tmp" CODEX_HOOK_REGISTRY="$registry" \
  CAPTURE_FILE="$missing_prompt_capture" "$here/hook-command-adapter.sh" PreToolUse pretool-test >/dev/null
test ! -s "$missing_prompt_capture"

# SessionStart with a reused id also clears a stale turn state.
printf '%s' "$(jq -nc --arg prompt "prior session prompt" \
  '{session_id:"adapter-test",cwd:"/tmp",prompt:$prompt}')" |
  TMPDIR="$test_tmp" AGENT_HOME_ROOT="$test_tmp" CODEX_HOOK_REGISTRY="$registry" \
  "$here/hook-command-adapter.sh" UserPromptSubmit prompt-test >/dev/null
printf '%s' '{"session_id":"adapter-test","cwd":"/tmp"}' |
  TMPDIR="$test_tmp" AGENT_HOME_ROOT="$test_tmp" CODEX_HOOK_REGISTRY="$registry" \
  "$here/hook-command-adapter.sh" SessionStart session-test >/dev/null
reused_session_capture="$test_tmp/captured-reused-session-sha"
printf '%s' '{"session_id":"adapter-test","cwd":"/tmp","tool_input":{}}' |
  TMPDIR="$test_tmp" AGENT_HOME_ROOT="$test_tmp" CODEX_HOOK_REGISTRY="$registry" \
  CAPTURE_FILE="$reused_session_capture" "$here/hook-command-adapter.sh" PreToolUse pretool-test >/dev/null
test ! -s "$reused_session_capture"

# Codex maps Claude TaskCreate to update_plan. The adapter must preserve the
# multi-item plan payload so record-step-tasks can emit one tag per active item.
repo_root=$(cd "$here/../.." && pwd)
record_script="$repo_root/rules/always/gate/phase-step-task/record-step-tasks.sh"
check_phase_script="$repo_root/rules/always/gate/phase-step-task/check-phase-entry-tasks.sh"
plan_input=$(jq -nc '{
  session_id:"adapter-plan-test",
  cwd:"/tmp",
  tool_name:"update_plan",
  tool_input:{plan:[
    {step:"Phase 4 Step 4-1: 仕様を確定する",status:"in_progress"},
    {step:"Phase 4 Step 4-2: 実装を検証する",status:"pending"},
    {step:"Phase 4 Step 4-3: 完了済み作業",status:"completed"}
  ]}
}')
plan_output=$(printf '%s' "$plan_input" |
  TMPDIR="$test_tmp" AGENT_HOME_ROOT="$test_tmp" CODEX_HOOK_REGISTRY="$registry" \
  RECORD_SCRIPT="$record_script" \
  "$here/hook-command-adapter.sh" PostToolUse plan-record-test)
plan_context=$(printf '%s' "$plan_output" | jq -r '.hookSpecificOutput.additionalContext')
printf '%s' "$plan_context" | grep -q 'STEP-TASK-RECORDED:4:1'
printf '%s' "$plan_context" | grep -q 'STEP-TASK-RECORDED:4:2'
if printf '%s' "$plan_context" | grep -q 'STEP-TASK-RECORDED:4:3'; then
  echo "completed Codex plan item was recorded again" >&2
  exit 1
fi

# Feed the adapter-produced tags into the transcript and prove the phase-entry
# gate is released for the two required steps.
plan_transcript="$test_tmp/adapter-plan-transcript.jsonl"
printf '%s\n' "$plan_context" >"$plan_transcript"
phase_input=$(jq -nc --arg transcript "$plan_transcript" '{
  session_id:"adapter-plan-test",
  cwd:"/tmp",
  transcript_path:$transcript,
  tool_input:{command:"bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 4 \"実装\" 0 2 \"開始\""}
}')
phase_output=$(printf '%s' "$phase_input" | bash "$check_phase_script")
printf '%s' "$phase_output" | grep -q 'PHASE-ENTERED:4'

if rg -n '/Users/.+\\.superset' "$here/hook-command-adapter.sh" >/dev/null; then
  echo "machine-specific SUPERSET_HOME_DIR default remains" >&2
  exit 1
fi

echo "PASS hook-command-adapter"
