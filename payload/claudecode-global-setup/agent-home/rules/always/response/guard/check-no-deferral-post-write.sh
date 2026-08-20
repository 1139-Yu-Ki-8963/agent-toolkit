#!/usr/bin/env bash
# PostToolUse(Write|Edit|MultiEdit) hook.
# When a markdown/text file looks like a PR/issue body fixture, scan it for
# deferral phrases and inject [NO-DEFERRAL] additionalContext.
# Does NOT exit 2 — just warns Claude so the next turn rewrites the file.

set -euo pipefail

input="$(cat)"
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file" ] && exit 0
[ ! -f "$file" ] && exit 0

case "${file##*.}" in
  md|mdx|txt) ;;
  *) exit 0 ;;
esac

# Heuristic: looks like a PR/issue body if either
#   (a) 1st line is "Closes #N" / "Fixes #N" / "Resolves #N" / "該当なし"
#   (b) contains both "## 概要" and "## なぜこの実装か" headings
head1=$(head -1 "$file" 2>/dev/null || true)
if printf '%s' "$head1" | grep -qiE '^(closes|fixes|resolves)[[:space:]]*#[0-9]+|^該当なし[[:space:]]*$'; then
  :
elif grep -qE '^## 概要' "$file" 2>/dev/null && grep -qE '^## なぜこの実装か' "$file" 2>/dev/null; then
  :
else
  exit 0
fi

CHECK="$HOME/.claude/rules/always/response/guard/shared/no-deferral-detect.sh"
matches=$("$CHECK" "$file" 2>/dev/null || true)
[ -z "$matches" ] && exit 0

# 通知のみ。停止判断は PreToolUse(Bash) hook の exit 2 関所が担う。
# 同一ファイル再 Edit でも STALE 格上げはしない（PR #455 と同方針）。
ctx="[NO-DEFERRAL] file=$file に先送り表現を検出。~/.claude/rules/always/response/guard/rule.md を参照。"

jq -n --arg ctx "$ctx" '{"systemMessage":"[no-deferral] 先送り表現を検出","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$ctx}}'
exit 0
