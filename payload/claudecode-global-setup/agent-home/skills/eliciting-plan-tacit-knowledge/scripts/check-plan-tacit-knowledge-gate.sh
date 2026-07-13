#!/usr/bin/env bash
# PreToolUse(ExitPlanMode) hook.
# eliciting-plan-tacit-knowledge スキルの発火回数（セッションのスキルログの該当行数）が
# 消費カウンタ（前回ゲート通過までに消費した発火数）を超えていなければ ExitPlanMode を block する。
# 通過時に消費カウンタを現在の発火数へ更新する（check-plan-draft-write-gate.sh と共有）。
# タイムスタンプ比較ではなく発火行数の単調増加で判定する（未来日時 ts の混入で消費機構が無効化されない）。
# 正本: ~/agent-home/skills/eliciting-plan-tacit-knowledge/SKILL.md「## 機械強制」節
# 再帰防止: 同一セッション3回連続で自動解除（正規通過で連続カウントはリセット。解除時は消費カウンタを現在値へ更新して exit 0）。
set -u

[ "${CLAUDE_HOOKS_TEST:-}" = "1" ] && exit 0
[ -n "${CLAUDE_HOOK_SUMMARY_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_FLOW_REPORT_RUNNING:-}" ] && exit 0

input=$(cat)

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$tool" != "ExitPlanMode" ] && exit 0

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"

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
  rm -f "$(marker_path "$cwd" "$session" plan-tacit-knowledge-gate.count)"
  exit 0
fi

counter="$(marker_path "$cwd" "$session" plan-tacit-knowledge-gate.count)"
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
  printf '%d' "$fire_count" > "$consumed_marker"
  exit 0
fi

ctx="[PLAN-TACIT-KNOWLEDGE-GATE-BLOCK] eliciting-plan-tacit-knowledge 未実行。実行後に再度 ExitPlanMode を呼べ。"
jq -n --arg ctx "$ctx" '{"systemMessage":"[フック発火] 計画暗黙知ゲート: 未通過につき block","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
printf '%s\n' "$ctx" >&2
exit 2
