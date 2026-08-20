#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/../../../.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

session="workflow-test"
input=$(jq -nc --arg session "$session" --arg prompt "新しいタスクを開始する" \
  '{session_id:$session,prompt:$prompt}')
output=$(printf '%s' "$input" | TMPDIR="$test_tmp" AGENT_HOME_ROOT="$repo_root" \
  "$here/check-session-workflow-prompt.sh")

jq -e '.systemMessage
  and .hookSpecificOutput.hookEventName == "UserPromptSubmit"
  and .hookSpecificOutput.additionalContext' <<<"$output" >/dev/null
context=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
for required in \
  "毎ターン再評価" "goal:" "purpose:" "completionCriteria:" "constraints:" \
  "userCorrections:" "inputs:" "publication:" "get_goal" "create_goal" "update_goal" \
  "AskUserQuestion" "request_user_input" "SKILL.md" "spawn_agent" "2 段階確認" \
  "公開確認まで" "ローカル検証まで" "文字起こしのみ"; do
  printf '%s' "$context" | grep -q "$required"
done

state="$test_tmp/session-workflow-context/${session}.json"
jq -e '.schemaVersion == 1 and .contextSupplied == true
  and .requestTypeHint == "新規"
  and .workflowExecutionStatus == "not-recorded"
  and .handoffContractKeys == [
    "goal", "purpose", "completionCriteria", "constraints",
    "userCorrections", "inputs", "publication"
  ]
  and (.promptSha256 | length == 64) and (.skillSha256 | length == 64)' "$state" >/dev/null

printf '%s' "$input" | TMPDIR="$test_tmp" AGENT_HOME_ROOT="$repo_root" \
  "$here/check-session-workflow-gate.sh"

turn_two=$(jq -nc --arg session "$session" --arg prompt "追加でテストも行う" \
  '{session_id:$session,prompt:$prompt}')
if printf '%s' "$turn_two" | TMPDIR="$test_tmp" AGENT_HOME_ROOT="$repo_root" \
  "$here/check-session-workflow-gate.sh" >/dev/null 2>&1; then
  echo "stale turn state unexpectedly passed" >&2
  exit 1
fi
stale_stop=$(printf '%s' "$turn_two" | TMPDIR="$test_tmp" AGENT_HOME_ROOT="$repo_root" \
  "$here/check-session-workflow-stop.sh")
printf '%s' "$stale_stop" | jq -e '.decision == "block"' >/dev/null
printf '%s' "$turn_two" | TMPDIR="$test_tmp" AGENT_HOME_ROOT="$repo_root" \
  "$here/check-session-workflow-prompt.sh" >/dev/null
printf '%s' "$turn_two" | TMPDIR="$test_tmp" AGENT_HOME_ROOT="$repo_root" \
  "$here/check-session-workflow-gate.sh"

correction_prompt="前の条件を訂正し、公開まで進める"
correction=$(jq -nc --arg session "$session" --arg prompt "$correction_prompt" \
  '{session_id:$session,prompt:$prompt}')
printf '%s' "$correction" | TMPDIR="$test_tmp" AGENT_HOME_ROOT="$repo_root" \
  "$here/check-session-workflow-prompt.sh" >/dev/null
expected_sha=$(printf '%s' "$correction_prompt" | shasum -a 256 | awk '{print $1}')
jq -e --arg sha "$expected_sha" \
  '.requestTypeHint == "訂正" and .promptSha256 == $sha
    and (.handoffContractKeys | length == 7)' "$state" >/dev/null
printf '%s' "$correction" | TMPDIR="$test_tmp" AGENT_HOME_ROOT="$repo_root" \
  "$here/check-session-workflow-gate.sh"
hash_only_input=$(jq -nc --arg session "$session" --arg sha "$expected_sha" \
  '{session_id:$session,current_prompt_sha256:$sha}')
printf '%s' "$hash_only_input" | TMPDIR="$test_tmp" AGENT_HOME_ROOT="$repo_root" \
  "$here/check-session-workflow-gate.sh"
printf '%s' "$correction" | TMPDIR="$test_tmp" AGENT_HOME_ROOT="$repo_root" \
  "$here/check-session-workflow-stop.sh" >/dev/null

# A correction handoff preserves the original text, normalized replacement, and
# regenerated target instead of merely classifying the turn as "訂正".
validator="$repo_root/skills/orchestrating-dev-flow/scripts/validate-handoff-coverage.mjs"
jq -nc --arg original "$correction_prompt" '{
  handoff:{
    goal:"公開確認まで",
    purpose:"session workflowを改善する",
    completionCriteria:["公開後確認"],
    constraints:["専用worktree"],
    userCorrections:[{
      sourceId:"correction-publish",
      original:$original,
      normalized:"最終到達状態へagent-toolkit公開後確認を追加する",
      target:"completionCriteria and publication"
    }],
    inputs:[],
    publication:{required:true,target:"agent-toolkit",verification:"remote refetch"}
  }
}' >"$test_tmp/correction-handoff.json"
node "$validator" schema "$test_tmp/correction-handoff.json" >/dev/null
jq -e --arg original "$correction_prompt" \
  '.handoff.userCorrections[0].original == $original
    and .handoff.userCorrections[0].normalized == "最終到達状態へagent-toolkit公開後確認を追加する"
    and .handoff.userCorrections[0].target == "completionCriteria and publication"
    and .handoff.completionCriteria == ["公開後確認"]
    and .handoff.publication.required == true' \
  "$test_tmp/correction-handoff.json" >/dev/null

transcript="$test_tmp/transcript.jsonl"
jq -nc --arg prompt "$correction_prompt" \
  '{type:"user",message:{role:"user",content:$prompt}}' >"$transcript"
transcript_input=$(jq -nc --arg session "$session" --arg transcript "$transcript" \
  '{session_id:$session,transcript_path:$transcript}')
printf '%s' "$transcript_input" | TMPDIR="$test_tmp" AGENT_HOME_ROOT="$repo_root" \
  "$here/check-session-workflow-gate.sh"
if printf '%s' "{\"session_id\":\"$session\"}" | TMPDIR="$test_tmp" \
  AGENT_HOME_ROOT="$repo_root" "$here/check-session-workflow-gate.sh" >/dev/null 2>&1; then
  echo "missing current prompt hash unexpectedly passed" >&2
  exit 1
fi

transcribing="$repo_root/skills/transcribing-images/SKILL.md"
for required in "actionable: true" "findings:" "expectedChange:" "verification:" "2 段階"; do
  if [ "$required" = "2 段階" ]; then
    grep -q "$required" "$repo_root/skills/managing-session-workflow/SKILL.md"
  else
    grep -q "$required" "$transcribing"
  fi
done

# Actionable image findings cannot enter implementation until both scope
# confirmations have been recorded in the common handoff.
jq -nc '{
  handoff:{
    goal:"公開確認まで",
    purpose:"画像指摘を反映する",
    completionCriteria:["指摘解消"],
    constraints:[],
    userCorrections:[],
    inputs:[{
      type:"image",
      actionable:true,
      scopeConfirmation:{
        investigationAndImplementation:"proceed",
        goalScope:"publication"
      },
      findings:[{
        id:"image-gate",
        source:"screen.png",
        observation:"gateが欠落"
      }],
      expectedChange:["gateを追加"],
      verification:["回帰テスト"]
    }],
    publication:{required:true,target:"agent-toolkit",verification:"remote refetch"}
  },
  coverage:[{
    sourceId:"image-gate",
    source:"image",
    target:"workflow gate",
    implementation:"gateを追加",
    verification:"回帰テスト",
    status:"planned"
  }]
}' >"$test_tmp/image-handoff.json"
node "$validator" schema "$test_tmp/image-handoff.json" >/dev/null
node "$validator" implementation "$test_tmp/image-handoff.json" >/dev/null
jq 'del(.handoff.inputs[0].scopeConfirmation.goalScope)' \
  "$test_tmp/image-handoff.json" >"$test_tmp/image-missing-second-confirmation.json"
if node "$validator" schema "$test_tmp/image-missing-second-confirmation.json" >/dev/null 2>&1; then
  echo "actionable image without second confirmation unexpectedly passed" >&2
  exit 1
fi
jq '.handoff.inputs[0].scopeConfirmation = {
  investigationAndImplementation:"transcription-only", goalScope:null
}' "$test_tmp/image-handoff.json" >"$test_tmp/image-transcription-only.json"
if node "$validator" implementation "$test_tmp/image-transcription-only.json" >/dev/null 2>&1; then
  echo "transcription-only image unexpectedly reached implementation handoff" >&2
  exit 1
fi

rm -f "$state"
mkdir -p "$test_tmp/fake-home/sessions/.skill-log"
printf '%s\n' '{"skill":"managing-session-workflow","source":"codex-session-start-bootstrap"}' \
  >"$test_tmp/fake-home/sessions/.skill-log/${session}.jsonl"
if printf '%s' "$input" | TMPDIR="$test_tmp" AGENT_HOME_ROOT="$test_tmp/fake-home" \
  SESSION_WORKFLOW_CONTEXT_FILE="$repo_root/skills/managing-session-workflow/SKILL.md" \
  "$here/check-session-workflow-gate.sh" >/dev/null 2>&1; then
  echo "fake skill log unexpectedly passed" >&2
  exit 1
fi

echo "PASS session-workflow-gate"
