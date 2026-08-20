#!/usr/bin/env bash
# record-step-tasks.sh - PostToolUse(TaskCreate / Codex update_plan) hook
#
# 役割: Claude TaskCreate の subject または Codex update_plan の active item を検査し、
#       step 粒度規約（Phase <N> Step <N>-<M>: <内容>）に合致するものだけを transcript の
#       phase 別タグとして記録する。フロー実行中（flow-status.json 存在）に形式違反を検出した場合は
#       [STEP-TASK-FORMAT] を advisory 注入する（block なし）。
# 仕様: ~/.claude/rules/always/gate/phase-step-task/rule.md
set -u

input="$(cat)"
subject=$(printf '%s' "$input" | jq -r '.tool_input.subject // empty' 2>/dev/null)
plan_subjects=$(printf '%s' "$input" | jq -r '
  .tool_input.plan[]?
  | select(.status == "pending" or .status == "in_progress")
  | .step // empty
' 2>/dev/null)
[ -z "$subject" ] && [ -z "$plan_subjects" ] && exit 0

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

. "$HOME/.claude/rules/scoped/agent-config/hooks/shared/transcript-query.sh"

subjects="$subject"
[ -z "$subjects" ] && subjects="$plan_subjects"
tags=""
invalid_subjects=""

# 形式: Phase <N> Step <N>-<M>: <内容>（N は数値または D/I、M は数値、内容は非空）
while IFS= read -r current_subject; do
  [ -z "$current_subject" ] && continue
  if printf '%s' "$current_subject" | LC_ALL=C grep -qE '^Phase ([0-9]+|[DI]) Step ([0-9]+|[DI])-[0-9]+: .{3,}'; then
    phase=$(printf '%s' "$current_subject" | sed -E 's/^Phase ([0-9]+|[DI]) .*/\1/')
    step_prefix=$(printf '%s' "$current_subject" | sed -E 's/^Phase ([0-9]+|[DI]) Step ([0-9]+|[DI])-[0-9]+:.*/\2/')
    step_num=$(printf '%s' "$current_subject" | sed -E 's/^Phase ([0-9]+|[DI]) Step ([0-9]+|[DI])-([0-9]+):.*/\3/')
    if [ "$phase" = "$step_prefix" ]; then
      tags="${tags}[STEP-TASK-RECORDED:${phase}:${step_num}]
"
      continue
    fi
  fi
  invalid_subjects="${invalid_subjects}${current_subject}
"
done <<EOF
$subjects
EOF

if [ -n "$tags" ]; then
  context="${tags%$'\n'}"
  if [ -n "$invalid_subjects" ]; then
    context="${context}
[STEP-TASK-FORMAT] 一部の update_plan step が規約違反のため記録対象外。"
  fi
  jq -n --arg context "$context" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $context
    }
  }'
  exit 0
fi

# 形式違反: フロー実行中（flow-status.json 存在）のみ advisory 注入
status_file="$(marker_path "$cwd" "$session" "flow-status.json")"
[ ! -f "$status_file" ] && exit 0

jq -n --arg subject "${invalid_subjects%$'\n'}" '{
  systemMessage: "[フック発火] phase 突入タスクゲート: subject 形式違反を検出",
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("[STEP-TASK-FORMAT] TaskCreate / update_plan の項目「" + $subject + "」が step 粒度規約（Phase <N> Step <N>-<M>: <作業内容>、番号一致必須）に違反。このタスクは記録されず phase 突入時に block される。~/.claude/rules/always/gate/phase-step-task/rule.md を参照。")
  }
}'
exit 0
