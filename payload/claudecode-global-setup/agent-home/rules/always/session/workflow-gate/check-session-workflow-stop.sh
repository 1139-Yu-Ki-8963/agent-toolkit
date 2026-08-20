#!/usr/bin/env bash
# check-session-workflow-stop.sh
# timing: Stop
# 当該ターンの workflow 全文供給がないまま応答を終えようとしたら書き直しを強制する
# 仕様: 同ディレクトリの rule.md を参照

set -uo pipefail

input="$(cat)"
[ -z "$input" ] && exit 0

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0

agent_home_root="${AGENT_HOME_ROOT:-$HOME/agent-home}"
context_file="${SESSION_WORKFLOW_CONTEXT_FILE:-$agent_home_root/skills/managing-session-workflow/SKILL.md}"
state_file="${TMPDIR:-/tmp}/session-workflow-context/${session}.json"

current_prompt_sha=""
current_prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || true)
if [ -n "$current_prompt" ]; then
  current_prompt_sha=$(printf '%s' "$current_prompt" | shasum -a 256 | awk '{print $1}')
fi
if [ -z "$current_prompt_sha" ]; then
  current_prompt_sha=$(printf '%s' "$input" | jq -r '.current_prompt_sha256 // empty' 2>/dev/null || true)
fi
if [ -z "$current_prompt_sha" ]; then
  transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    latest_user=$(jq -rs '
      [.[] | select(.type == "user" or .message.role == "user")
        | (.message.content // .content // empty)
        | if type == "array"
          then map(if type == "object" then (.text // empty) else . end) | join("")
          else . end]
      | last // empty
    ' "$transcript" 2>/dev/null || true)
    [ -n "$latest_user" ] &&
      current_prompt_sha=$(printf '%s' "$latest_user" | shasum -a 256 | awk '{print $1}')
  fi
fi

if [ -n "$current_prompt_sha" ] && [ -f "$context_file" ] && [ -f "$state_file" ]; then
  required_state=true
  for key in goal purpose completionCriteria constraints userCorrections inputs publication; do
    grep -q "$key" "$context_file" || required_state=false
  done
  skill_sha=$(shasum -a 256 "$context_file" | awk '{print $1}')
  if [ "$required_state" = true ] && jq -e \
    --arg session "$session" --arg skillSha "$skill_sha" --arg promptSha "$current_prompt_sha" \
    '.schemaVersion == 1 and .sessionId == $session and .skillSha256 == $skillSha
      and .promptSha256 == $promptSha and .contextSupplied == true
      and .workflowExecutionStatus == "not-recorded"
      and (.requestTypeHint | IN("新規", "追加", "訂正", "置換", "質問"))
      and .handoffContractKeys == [
        "goal", "purpose", "completionCriteria", "constraints",
        "userCorrections", "inputs", "publication"
      ]' \
    "$state_file" >/dev/null 2>&1; then
    exit 0
  fi
fi

cat <<'JSON'
{"decision":"block","reason":"[SESSION-WORKFLOW-STOP-BLOCK] 当該ターンの managing-session-workflow 全文コンテキスト供給を確認できないまま応答を終了しようとしています。UserPromptSubmit の供給記録と現ターン hash を確認してください。 詳細: ~/.claude/rules/always/session/workflow-gate/rule.md"}
JSON
exit 0
