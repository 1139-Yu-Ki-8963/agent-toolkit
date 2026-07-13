#!/usr/bin/env bash
# PreToolUse(Bash) hook for `gh pr|issue create|comment`.
# Reads stdin JSON, extracts the PR/issue body (from --body-file or --body),
# and blocks the command (exit 2 + additionalContext) if no-deferral-check finds matches.

set -euo pipefail

input="$(cat)"
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

case "$cmd" in
  "gh pr create"*|"gh issue create"*|"gh issue comment"*|"gh pr comment"*) ;;
  *) exit 0 ;;
esac

tmp=$(mktemp /tmp/no-deferral-bash-XXXXXX.md)
trap 'rm -f "$tmp"' EXIT

# Prefer --body-file <PATH>; fall back to --body "..."
bodyfile=$(printf '%s' "$cmd" | perl -ne 'print $1 if /--body-file[[:space:]]+(\S+)/')
if [ -n "$bodyfile" ] && [ -f "$bodyfile" ]; then
  cat "$bodyfile" > "$tmp"
else
  printf '%s' "$cmd" | perl -0777 -e '$_=do{local $/;<STDIN>}; if(/--body[[:space:]]+"((?:[^"\\]|\\.)*)"/s){print $1}' > "$tmp"
fi

[ -s "$tmp" ] || exit 0

CHECK="$HOME/.claude/rules/always/response/guard/shared/no-deferral-detect.sh"
matches=$("$CHECK" "$tmp" 2>/dev/null || true)
[ -z "$matches" ] && exit 0

# 常に [NO-DEFERRAL-BLOCK] で exit 2（block）。
# STALE 格上げは PR #455 と同方針で撤去（Claude の自発停止を誘発するため）。
ctx="[NO-DEFERRAL-BLOCK] PR/issue 本文に先送り表現を検出。~/.claude/rules/always/response/guard/rule.md を参照。"

jq -n --arg ctx "$ctx" '{"systemMessage":"[no-deferral] PR/issue 本文に先送り表現を検出","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
exit 2
