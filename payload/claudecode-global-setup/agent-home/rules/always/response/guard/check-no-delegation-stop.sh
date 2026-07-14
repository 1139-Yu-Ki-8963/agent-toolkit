#!/usr/bin/env bash
# Stop hook. 最終応答に「CLI 以外操作のユーザー依頼」を検出したら decision:block で書き直しを強制。
# 検出ロジックは lib/no-delegation-detect.sh（単一ソース）に委譲する。
# fail-open: check が無い/エラー時は exit 0（自己ブロック事故を防ぐ）。block は rc==1 のときのみ。

. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"

[ -n "$CLAUDE_HOOK_NO_DELEGATION_RUNNING" ] && exit 0
[ -n "$CLAUDE_HOOK_SUMMARY_RUNNING" ] && exit 0
[ -n "$CLAUDE_HOOK_DICT_RUNNING" ] && exit 0
[ -n "$CLAUDE_HOOK_AUTOCOMMIT_RUNNING" ] && exit 0
[ -n "$CLAUDE_HOOK_FLOW_REPORT_RUNNING" ] && exit 0

input=$(cat)
stop_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
[ "$stop_active" = "true" ] && exit 0

pmode=$(printf '%s' "$input" | jq -r '.permission_mode // empty')
if [ -z "$pmode" ]; then
  _tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
  [ -n "$_tp" ] && [ -f "$_tp" ] && pmode=$(tail -c 10000 "$_tp" 2>/dev/null | grep -o '"permissionMode":"[^"]*"' | tail -1 | cut -d'"' -f4 || true)
fi
[ "$pmode" = "plan" ] && exit 0

tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
{ [ -z "$tp" ] || [ ! -f "$tp" ]; } && exit 0

last=$({ tac "$tp" 2>/dev/null || tail -r "$tp" 2>/dev/null; } | jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null | head -1)
[ -z "$last" ] && exit 0

CHECK="$HOME/.claude/rules/always/response/guard/shared/no-delegation-detect.sh"
[ -x "$CHECK" ] || exit 0

printf '%s' "$last" | "$CHECK" >/dev/null 2>&1
rc=$?
# 0=clean / 2=usage error → fail-open。block は検出（rc==1）のときのみ。
[ "$rc" -eq 1 ] || exit 0

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
counter_file="$(marker_path "$cwd" "$session" no-delegation-stop.count)"
hits=0
[ -f "$counter_file" ] && hits=$(cat "$counter_file" 2>/dev/null || echo 0)
hits=$((hits + 1))
printf '%d' "$hits" > "$counter_file"

if [ "$hits" -ge 3 ]; then
  exit 0
fi

ctx='[NO-DELEGATION] 最終応答にユーザー操作依頼を検出。~/.claude/rules/always/response/guard/rule.md を参照。'
jq -n --arg ctx "$ctx" '{"decision":"block","systemMessage":$ctx}'
exit 0
