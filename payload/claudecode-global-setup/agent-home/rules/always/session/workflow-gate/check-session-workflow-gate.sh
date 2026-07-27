#!/usr/bin/env bash
# check-session-workflow-gate.sh
# PreToolUse hook（matcher は settings.json 側で Write|Edit|MultiEdit|NotebookEdit|Bash|Read|Grep|Glob|Agent|Workflow|WebFetch|WebSearch|Artifact に拡張済み）
# 当該ターンの workflow 全文供給記録が不正なら実作業を block する
#
# 設計判断:
# - 必要性: Skill 名ログは当該ターンで本文を実行可能な状態にした証拠にならない。
#   UserPromptSubmit の全文供給 checksum を照合して実作業前に再評価を強制する
# - 代替案を採用しなかった理由: skill-log 名一致では偽 bootstrap を区別できない
# - 保守責任者: 人手（ユーザー）
# - 廃棄条件: ランタイムがターン単位の Skill 本文供給と実行証明を標準提供した時
# 仕様: 同ディレクトリの rule.md を参照

set -euo pipefail

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

valid=false
if [ -n "$current_prompt_sha" ] && [ -f "$context_file" ] && [ -f "$state_file" ]; then
  required_state=true
  for key in goal purpose completionCriteria constraints userCorrections inputs publication; do
    grep -q "$key" "$context_file" || required_state=false
  done
  skill_sha=$(shasum -a 256 "$context_file" | awk '{print $1}')
  if [ "$required_state" = true ] && jq -e \
    --arg session "$session" \
    --arg skillSha "$skill_sha" \
    --arg promptSha "$current_prompt_sha" \
    '.schemaVersion == 1
      and .sessionId == $session
      and .skillSha256 == $skillSha
      and .promptSha256 == $promptSha
      and .contextSupplied == true
      and .workflowExecutionStatus == "not-recorded"
      and (.requestTypeHint | IN("新規", "追加", "訂正", "置換", "質問"))
      and .handoffContractKeys == [
        "goal", "purpose", "completionCriteria", "constraints",
        "userCorrections", "inputs", "publication"
      ]
      and (.suppliedAt | type == "string" and length > 0)' \
    "$state_file" >/dev/null 2>&1; then
    valid=true
  fi
fi

[ "$valid" = true ] && exit 0

cat >&2 <<'MSG'
[SESSION-WORKFLOW-BLOCK] 当該ターンの managing-session-workflow 全文コンテキスト供給を確認できません。Skill 名だけのログや偽 bootstrap 記録では通過しません。 詳細: ~/.claude/rules/always/session/workflow-gate/rule.md
MSG
exit 2
