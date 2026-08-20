#!/usr/bin/env bash
# PreToolUse(ExitPlanMode) hook.
# eliciting-plan-tacit-knowledge スキルの発火数（セッションの skill-log 該当行数）が
# 消費数（transcript 内の PASS タグ実発火行数。下書き Write・ExitPlanMode 両ゲート合算）を
# 超えていなければ ExitPlanMode を [PLAN-TACIT-KNOWLEDGE-GATE-BLOCK] exit 2 で block する。
# 通過時は PASS タグ入り additionalContext を注入し、それが transcript に記録されることで
# 発火 1 回の消費を表す（マーカーファイル禁止規約準拠。状態ファイルは一切作らない）。
# タグ出現数は「(fired=N consumed=M)」の展開済み数値付きでカウントし、
# スキル文書や本スクリプト自体を Read した際の未展開文字列を誤カウントしない。
# 再帰防止: transcript 内の自ゲート block 実発火 3 回で自動解除（セッション内恒久）。
# 正本: ~/agent-home/skills/eliciting-plan-tacit-knowledge/SKILL.md「## 機械強制」節
set -u

[ "${CLAUDE_HOOKS_TEST:-}" = "1" ] && exit 0
[ -n "${CLAUDE_HOOK_SUMMARY_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_FLOW_REPORT_RUNNING:-}" ] && exit 0

input=$(cat)

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$tool" != "ExitPlanMode" ] && exit 0

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0
tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

count_expanded_tag() {
  # $1: transcript path, $2: タグ slug（-BLOCK / -PASS まで含む）
  local t="${1:-}" tag="${2:-}" c
  if [ -z "$t" ] || [ ! -f "$t" ]; then echo 0; return; fi
  c="$(grep -cE "\[${tag}\]\(fired=[0-9]+ consumed=[0-9]+\)" "$t" 2>/dev/null || true)"
  case "$c" in ''|*[!0-9]*) c=0 ;; esac
  echo "$c"
}

blocks="$(count_expanded_tag "$tp" "PLAN-TACIT-KNOWLEDGE-GATE-BLOCK")"
[ "$blocks" -ge 3 ] && exit 0

log_file="$HOME/agent-home/sessions/.skill-log/${session}.jsonl"
fire_count=0
if [ -f "$log_file" ]; then
  fire_count="$(grep -c '"skill":"eliciting-plan-tacit-knowledge"' "$log_file" 2>/dev/null || true)"
fi
case "$fire_count" in ''|*[!0-9]*) fire_count=0 ;; esac

write_pass="$(count_expanded_tag "$tp" "PLAN-DRAFT-WRITE-GATE-PASS")"
exit_pass="$(count_expanded_tag "$tp" "PLAN-TACIT-KNOWLEDGE-GATE-PASS")"
consumed=$((write_pass + exit_pass))

if [ "$fire_count" -gt "$consumed" ]; then
  ctx="[PLAN-TACIT-KNOWLEDGE-GATE-PASS](fired=${fire_count} consumed=${consumed}) 計画暗黙知ゲート（ExitPlanMode）通過。この通過で発火 1 回を消費した。"
  jq -n --arg ctx "$ctx" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  exit 0
fi

ctx="[PLAN-TACIT-KNOWLEDGE-GATE-BLOCK](fired=${fire_count} consumed=${consumed}) eliciting-plan-tacit-knowledge 未実行。実行後に再度 ExitPlanMode を呼べ。"
jq -n --arg ctx "$ctx" '{"systemMessage":"[フック発火] 計画暗黙知ゲート: 未通過につき block","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
printf '%s\n' "$ctx" >&2
exit 2
