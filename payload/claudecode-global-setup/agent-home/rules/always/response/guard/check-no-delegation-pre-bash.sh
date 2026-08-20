#!/usr/bin/env bash
# PreToolUse(Bash) hook.
# 対話必須コマンド（gh auth login 等）の発行を exit 2 で先回り block する。
# permissions.deny との二重防御。token ベース代替へ誘導する。
set -u

input="$(cat)"
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

ICMD='gh auth login|npm login|docker login|gcloud auth login|aws configure|ssh-keygen|vercel login|supabase login|render login|heroku login'

printf '%s' "$cmd" | grep -qE "$ICMD" || exit 0

ctx="[NO-DELEGATION-BLOCK] 対話必須コマンドを検出: $(printf '%s' "$cmd" | grep -oE "$ICMD" | head -1). ~/.claude/rules/always/response/guard/rule.md を参照。"

jq -n --arg ctx "$ctx" '{"systemMessage":"[no-delegation] 対話必須コマンドを検出","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
exit 2
