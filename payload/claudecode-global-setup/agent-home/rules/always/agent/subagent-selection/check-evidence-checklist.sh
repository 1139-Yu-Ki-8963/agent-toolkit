#!/usr/bin/env bash
# PreToolUse(Agent) hook.
# 調査・レビュー系の Agent 委任で、prompt 内にチェックリストがなければ exit 2 で block。
# 例外: worker-haiku / routine-worker / Explore / researcher / claude-code-guide /
#       [CHECKLIST-EXEMPT] 明示 / テスト環境
# 2026-07-05: Explore / researcher / claude-code-guide を例外に追加。
#   過去 14 日の実測で block 44 件超のほぼ全てが Explore / researcher への
#   過剰適用だった（読み取り検索・外部仕様参照はローカル事実の裏取りという
#   チェックリストの前提が当てはまらない）。ローカル調査の正式受け皿は
#   investigator / brain / report-reviewer で、そちらには従来どおり適用する。
# 再帰防止: 同一セッション 3 回連続で自動解除。
set -u

# --- テスト・再帰ガード ---
[ "${CLAUDE_HOOKS_TEST:-}" = "1" ] && exit 0
[ -n "${CLAUDE_HOOK_SUMMARY_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_FLOW_REPORT_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_AUTOCOMMIT_RUNNING:-}" ] && exit 0

input=$(cat)

# --- ツール判定: Agent 以外は対象外 ---
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$tool" != "Agent" ] && exit 0

# --- サブエージェント内からの呼出は対象外 ---
agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -n "$agent_id" ] && exit 0

# --- prompt 取得 ---
prompt=$(printf '%s' "$input" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
[ -z "$prompt" ] && exit 0

# --- 例外: worker-haiku / routine-worker ---
subagent_type=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
case "$subagent_type" in
  worker-haiku|worker-sonnet|routine-worker|portal-keeper|environment-officer|watchdog|cron-owner|statusline-setup|Explore|researcher|claude-code-guide)
    exit 0
    ;;
esac

# --- 例外: [CHECKLIST-EXEMPT] が prompt に含まれる ---
if printf '%s' "$prompt" | head -c 500 | grep -q '\[CHECKLIST-EXEMPT\]'; then
  exit 0
fi

# --- 調査・レビュー系かどうかを判定 ---
is_investigation=0
if printf '%s' "$prompt" | grep -qE '(調査|レビュー|分析|確認|検証|evaluate|review|investigate|analyze|audit|inspect|assess)'; then
  is_investigation=1
fi
# 調査を正式責務とするエージェントは常に調査系
case "$subagent_type" in
  investigator|brain|report-reviewer)
    is_investigation=1
    ;;
esac

# 調査系でなければ通す
[ "$is_investigation" -eq 0 ] && exit 0

# --- チェックリストの存在確認 ---
if printf '%s' "$prompt" | grep -q '## 調査チェックリスト'; then
  exit 0
fi

# --- 再帰防止カウンタ ---
. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
counter="$(marker_path "$cwd" "$session" investigation-checklist.count)"
hits=0
[ -f "$counter" ] && hits=$(cat "$counter" 2>/dev/null || echo 0)
hits=$((hits + 1))
printf '%d' "$hits" > "$counter"

if [ "$hits" -ge 4 ]; then
  exit 0
fi

# --- block ---
ctx="[CHECKLIST-MISSING] 調査・レビュー系の Agent 委任にチェックリストがありません。Skill(subagent-investigation-checklist) を実行してチェックリストを作成し、prompt に埋め込んでください。正本: ~/.claude/rules/always/agent/subagent-selection/rule.md"
jq -n --arg ctx "$ctx" '{"systemMessage":"[フック発火] チェックリスト未作成: 調査委任にチェックリストが必要","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
printf '%s\n' "$ctx" >&2
exit 2
