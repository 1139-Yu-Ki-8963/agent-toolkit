#!/usr/bin/env bash
# PreToolUse(Write) hook.
# 計画ファイル（~/.claude/plans/*.md）への最初の永続化（disk上に未存在の状態でのWrite）を、
# eliciting-plan-tacit-knowledge スキルの未消費の発火（消費カウンタを超える発火行数）が無ければ block する。
# 通過時に消費カウンタ（check-plan-tacit-knowledge-gate.sh と共有）を現在の発火数へ更新するため、
# 1 計画サイクルで「下書き前に 1 回・ExitPlanMode 承認前に 1 回」の計 2 回の発火が強制される。
# メインセッションのみ対象（agent_id が非空＝サブエージェントは対象外）。
# 正本: ~/agent-home/skills/eliciting-plan-tacit-knowledge/SKILL.md「## 機械強制」節
# 再帰防止: 同一セッション3回連続で自動解除（正規通過で連続カウントはリセット。解除時は無出力で exit 0）。
set -u

[ "${CLAUDE_HOOKS_TEST:-}" = "1" ] && exit 0
[ -n "${CLAUDE_HOOK_SUMMARY_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_FLOW_REPORT_RUNNING:-}" ] && exit 0

input=$(cat)

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$tool" != "Write" ] && exit 0

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
case "$file_path" in
  */.claude/plans/*.md) ;;
  *) exit 0 ;;
esac

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -n "$agent_id" ] && exit 0

[ -f "$file_path" ] && exit 0

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

. "$HOME/.claude/rules/scoped/agent-config/hooks/shared/transcript-query.sh"

consumed_marker="$(marker_path "$cwd" "$session" plan-tacit-knowledge-gate.consumed-count)"
consumed=0
if [ -f "$consumed_marker" ]; then
  raw="$(cat "$consumed_marker" 2>/dev/null || true)"
  case "$raw" in
    ''|*[!0-9]*) consumed=0 ;;
    *) consumed="$raw" ;;
  esac
fi

log_file="$HOME/agent-home/sessions/.skill-log/${session}.jsonl"
fire_count=0
if [ -f "$log_file" ]; then
  fire_count="$(jq -r 'select(.skill=="eliciting-plan-tacit-knowledge") | .ts' "$log_file" 2>/dev/null | grep -c . || true)"
fi
case "$fire_count" in ''|*[!0-9]*) fire_count=0 ;; esac

if [ "$fire_count" -gt "$consumed" ]; then
  printf '%d' "$fire_count" > "$consumed_marker"
  rm -f "$(marker_path "$cwd" "$session" plan-draft-write-gate.count)"
  exit 0
fi

counter="$(marker_path "$cwd" "$session" plan-draft-write-gate.count)"
hits=0
if [ -f "$counter" ]; then
  raw="$(cat "$counter" 2>/dev/null || true)"
  case "$raw" in
    ''|*[!0-9]*) hits=0 ;;
    *) hits="$raw" ;;
  esac
fi
hits=$((hits + 1))
printf '%d' "$hits" > "$counter"
if [ "$hits" -ge 3 ]; then
  exit 0
fi

ctx="[PLAN-DRAFT-WRITE-GATE-BLOCK] 計画ファイル未存在。会話テキストで eliciting-plan-tacit-knowledge を先に実行せよ。"
jq -n --arg ctx "$ctx" '{"systemMessage":"[フック発火] 計画下書きゲート: 未通過につき block","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
printf '%s\n' "$ctx" >&2
exit 2
