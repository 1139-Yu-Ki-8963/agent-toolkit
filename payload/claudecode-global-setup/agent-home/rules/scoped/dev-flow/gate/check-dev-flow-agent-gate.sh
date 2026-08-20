#!/usr/bin/env bash
set -euo pipefail

# check-dev-flow-agent-gate.sh — PreToolUse(Agent)
# ~/Projects/ 配下での編集可能サブエージェント起動時に
# .flow-progress.json の route 確定を要求する。
# route が空なら exit 2 で block。
# .flow-progress.json 不在（orchestrating-dev-flow 未導入）は通過。

input="$(cat)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

# ~/Projects/ 配下でなければ対象外
case "$cwd" in
  "$HOME/Projects/"*) ;;
  *) exit 0 ;;
esac

# subagent_type がRead-only系なら対象外
subagent_type="$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)"
case "$subagent_type" in
  worker-haiku|investigator|Explore|researcher|report-reviewer|claude-code-guide|statusline-setup|Plan) exit 0 ;;
esac

# gitルートの .flow-progress.json を確認
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$root" ] && exit 0

progress="$root/.flow-progress.json"
[ ! -f "$progress" ] && exit 0

# route が確定済みか確認
route="$(jq -r '.route // empty' "$progress" 2>/dev/null)"
[ -n "$route" ] && exit 0

# --- livelock 自動解除 ---
. "$HOME/.claude/rules/scoped/agent-config/hooks/shared/transcript-query.sh"
tp="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
should_auto_release "$tp" "DEV-FLOW-AGENT-GATE-BLOCK" 3 && exit 0

# block
cat <<'JSON'
{
  "decision": "block",
  "reason": "[DEV-FLOW-AGENT-GATE-BLOCK] orchestrating-dev-flow の route が未確定です。~/Projects/ 配下への編集を伴うサブエージェント委任は、Skill(orchestrating-dev-flow) で route 確定（Phase 1 完了）を先に済ませてから実行してください。"
}
JSON
exit 2
