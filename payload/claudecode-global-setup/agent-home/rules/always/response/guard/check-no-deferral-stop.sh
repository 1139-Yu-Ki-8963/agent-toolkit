#!/usr/bin/env bash
# Stop hook: scan the final assistant text for deferral phrases. Block the turn
# if found by emitting decision:block. Self-disables after 2 consecutive hits
# in the same session to avoid livelock.

set -euo pipefail

. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"

[ -n "${CLAUDE_HOOK_NO_DEFERRAL_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_SUMMARY_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_DICT_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_AUTOCOMMIT_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_FLOW_REPORT_RUNNING:-}" ] && exit 0

input="$(cat)"
stop_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$stop_active" = "true" ] && exit 0

pmode=$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null)
[ -z "$pmode" ] && {
  _tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  [ -n "$_tp" ] && [ -f "$_tp" ] && \
    pmode=$(tail -c 10000 "$_tp" 2>/dev/null \
      | grep -o '"permissionMode":"[^"]*"' | tail -1 | cut -d'"' -f4 || true)
}
[ "$pmode" = "plan" ] && exit 0

tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$tp" ] && exit 0
[ ! -f "$tp" ] && exit 0

last=$( { tail -r "$tp" 2>/dev/null | jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null | head -1; } || true )
[ -z "$last" ] && exit 0

PATTERN='別[[:space:]]*(PR|issue|プルリク|チケット)[[:space:]]*(で|を|に)?[[:space:]]*(対応|起票|分割|切り出|作成|作る|実装)|別途[[:space:]]*(PR|issue|チケット)|次の[[:space:]]*PR|新規[[:space:]]*issue[[:space:]]*を?[[:space:]]*(起票|作成|起こ)|残(課題|作業|タスク)|将来[[:space:]]*課題|今後の?[[:space:]]*(課題|対応)|後日[[:space:]]*対応|Phase[[:space:]]*[2-9][[:space:]]*以降|次回[[:space:]]*(対応|実装|セッション)'

printf '%s' "$last" | grep -qE "$PATTERN" || exit 0

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
counter_file="$(marker_path "$cwd" "$session" no-deferral-stop.count)"
hits=0
[ -f "$counter_file" ] && hits=$(cat "$counter_file" 2>/dev/null || echo 0)
hits=$((hits + 1))
printf '%d' "$hits" > "$counter_file"

if [ "$hits" -ge 3 ]; then
  # Livelock guard: third+ consecutive detection in same session — let it through.
  # Claude must report status to user manually per .claude/rules/no-deferral-rules.md.
  exit 0
fi

ctx='[NO-DEFERRAL-RESPONSE] 最終応答に先送り表現を検出。~/.claude/rules/always/response/guard/rule.md を参照。'
jq -n --arg ctx "$ctx" '{"decision":"block","systemMessage":$ctx}'
exit 0
