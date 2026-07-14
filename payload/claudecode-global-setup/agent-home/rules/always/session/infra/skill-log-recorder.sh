#!/usr/bin/env bash
# skill-log-recorder.sh
# PreToolUse(Skill) でスキル発火ログを ~/agent-home/sessions/.skill-log に追記する。
# parallel-dev-worktree 発火時は実装セッションマーカーを書き込む。
# 外部化前のインラインコマンドと完全等価。
set -u

. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"

[ -n "${CLAUDE_HOOK_SUMMARY_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_FLOW_REPORT_RUNNING:-}" ] && exit 0
input=$(cat)
session=$(printf '%s' "$input" | jq -r '.session_id // empty')
skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty')
[ -z "$session" ] || [ -z "$skill" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -z "$cwd" ] && cwd="$PWD"
dir="$HOME/agent-home/sessions/.skill-log"
mkdir -p "$dir"
jq -nc --arg ts "$(date -u +%FT%TZ)" --arg skill "$skill" '{ts:$ts, skill:$skill}' >> "$dir/$session.jsonl"
proj=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
[ -n "$proj" ] && [ "$skill" = "parallel-dev-worktree" ] && echo "$proj" > "$(marker_path "$cwd" "$session" impl-session)"
exit 0
