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

# --- livelock 防止: 同一セッション3回連続blockで自動解除 ---
session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
if [ -n "$session" ]; then
  . "$HOME/agent-home/tools/hooks/shared/marker-path.sh"
  counter="$(marker_path "$cwd" "$session" "dev-flow-agent-gate.count")"
  count=0
  [ -f "$counter" ] && count="$(cat "$counter")"
  count=$((count + 1))
  printf '%s' "$count" > "$counter"
  if [ "$count" -ge 3 ]; then
    exit 0
  fi
fi

# block
cat <<'JSON'
{
  "decision": "block",
  "reason": "[DEV-FLOW-AGENT-GATE-BLOCK] orchestrating-dev-flow の route が未確定です。~/Projects/ 配下への編集を伴うサブエージェント委任は、Skill(orchestrating-dev-flow) で route 確定（Phase 1 完了）を先に済ませてから実行してください。"
}
JSON
exit 2
