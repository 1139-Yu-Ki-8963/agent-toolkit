#!/usr/bin/env bash
# check-session-workflow-prompt.sh
# timing: UserPromptSubmit
# managing-session-workflow の実行可能な全文コンテキストを毎ターン注入する
# 仕様: 同ディレクトリの rule.md を参照

set -euo pipefail

input="$(cat)"
[ -z "$input" ] && exit 0

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
[ -n "$prompt" ] || exit 0

agent_home_root="${AGENT_HOME_ROOT:-$HOME/agent-home}"
context_file="${SESSION_WORKFLOW_CONTEXT_FILE:-$agent_home_root/skills/managing-session-workflow/SKILL.md}"
[ -f "$context_file" ] || exit 0

required_keys="goal purpose completionCriteria constraints userCorrections inputs publication"
for key in $required_keys; do
  grep -q "$key" "$context_file" || exit 0
done

prompt_sha=$(printf '%s' "$prompt" | shasum -a 256 | awk '{print $1}')
skill_sha=$(shasum -a 256 "$context_file" | awk '{print $1}')
case "$prompt" in
  *訂正*|*修正して*|*違う*|*ではなく*) request_type_hint="訂正" ;;
  *置換*|*差し替え*|*入れ替え*) request_type_hint="置換" ;;
  *追加*|*加えて*|*も対応*) request_type_hint="追加" ;;
  *\?*|*？*|*教えて*|*確認*) request_type_hint="質問" ;;
  *) request_type_hint="新規" ;;
esac
state_dir="${TMPDIR:-/tmp}/session-workflow-context"
state_file="$state_dir/${session}.json"
mkdir -p "$state_dir"
jq -n \
  --arg sessionId "$session" \
  --arg promptSha256 "$prompt_sha" \
  --arg skillSha256 "$skill_sha" \
  --arg requestTypeHint "$request_type_hint" \
  --arg suppliedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    schemaVersion: 1,
    sessionId: $sessionId,
    promptSha256: $promptSha256,
    skillSha256: $skillSha256,
    requestTypeHint: $requestTypeHint,
    handoffContractKeys: [
      "goal",
      "purpose",
      "completionCriteria",
      "constraints",
      "userCorrections",
      "inputs",
      "publication"
    ],
    workflowExecutionStatus: "not-recorded",
    suppliedAt: $suppliedAt,
    contextSupplied: true
  }' >"$state_file"

jq -n --rawfile workflow "$context_file" '{
  systemMessage: "[フック発火] SESSION-WORKFLOW: 毎ターン本文供給",
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: (
      "[SESSION-WORKFLOW-CONTEXT] 以下は当該ターンで実行する managing-session-workflow の全文コンテキスト。"
      + "これはコンテキスト供給であり、Skill 実行完了記録ではない。\n\n"
      + $workflow
    )
  }
}'
exit 0
