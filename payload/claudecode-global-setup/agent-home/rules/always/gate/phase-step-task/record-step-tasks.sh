#!/usr/bin/env bash
# record-step-tasks.sh - PostToolUse(TaskCreate) hook
#
# 役割: TaskCreate の subject を検査し、step 粒度規約（Phase <N> Step <N>-<M>: <内容>）に
#       合致するものだけを phase 別カウンタに加算する。フロー実行中（flow-status.json 存在）に
#       形式違反 subject を検出した場合は [STEP-TASK-FORMAT] を advisory 注入する（block なし）。
# 仕様: ~/.claude/rules/always/gate/phase-step-task/rule.md
set -u

input="$(cat)"
subject=$(printf '%s' "$input" | jq -r '.tool_input.subject // empty' 2>/dev/null)
[ -z "$subject" ] && exit 0

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

. "$HOME/.claude/rules/scoped/agent-config/hooks/shared/transcript-query.sh"

# 形式: Phase <N> Step <N>-<M>: <内容>（N は数値または D/I、M は数値、内容は非空）
if printf '%s' "$subject" | LC_ALL=C grep -qE '^Phase ([0-9]+|[DI]) Step ([0-9]+|[DI])-[0-9]+: .{3,}'; then
  phase=$(printf '%s' "$subject" | sed -E 's/^Phase ([0-9]+|[DI]) .*/\1/')
  step_prefix=$(printf '%s' "$subject" | sed -E 's/^Phase ([0-9]+|[DI]) Step ([0-9]+|[DI])-[0-9]+:.*/\2/')
  if [ "$phase" = "$step_prefix" ]; then
    jq -n --arg phase "$phase" '{
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: ("[STEP-TASK-RECORDED:" + $phase + "]")
      }
    }'
    exit 0
  fi
fi

# 形式違反: フロー実行中（flow-status.json 存在）のみ advisory 注入
status_dir="${TMPDIR:-/tmp}/claude-hooks/${session}"
status_file="${status_dir}/flow-status.json"
[ ! -f "$status_file" ] && exit 0

jq -n --arg subject "$subject" '{
  systemMessage: "[フック発火] phase 突入タスクゲート: subject 形式違反を検出",
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("[STEP-TASK-FORMAT] TaskCreate の subject「" + $subject + "」が step 粒度規約（Phase <N> Step <N>-<M>: <作業内容>、番号一致必須）に違反。このタスクはカウントされず phase 突入時に block される。~/.claude/rules/always/gate/phase-step-task/rule.md を参照。")
  }
}'
exit 0
