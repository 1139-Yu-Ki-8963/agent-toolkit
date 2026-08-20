#!/usr/bin/env bash
# PostToolUse(Write|Edit|MultiEdit) hook.
# PR/issue body 風の md ファイルに「画面編集推奨・web 認証誘導・手元実行依頼」を
# 検出したら [NO-DELEGATION] additionalContext を注入する（exit 2 はしない・通知のみ）。
# ファイルゲートは check-no-deferral-post-write.sh と同型（規約 md / SKILL.md は対象外）。
set -euo pipefail

input="$(cat)"
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file" ] && exit 0
[ ! -f "$file" ] && exit 0

case "${file##*.}" in
  md|mdx|txt) ;;
  *) exit 0 ;;
esac

# PR/issue body 判定（check-no-deferral-post-write.sh と同じヒューリスティック）
head1=$(head -1 "$file" 2>/dev/null || true)
if printf '%s' "$head1" | grep -qiE '^(closes|fixes|resolves)[[:space:]]*#[0-9]+|^該当なし[[:space:]]*$'; then
  :
elif grep -qE '^## 概要' "$file" 2>/dev/null && grep -qE '^## なぜこの実装か' "$file" 2>/dev/null; then
  :
else
  exit 0
fi

CHECK="$HOME/.claude/rules/always/response/guard/shared/no-delegation-detect.sh"
[ -x "$CHECK" ] || exit 0
matches=$("$CHECK" "$file" 2>/dev/null || true)
[ -z "$matches" ] && exit 0

ctx="[NO-DELEGATION] file=$file に依頼文を検出。~/.claude/rules/always/response/guard/rule.md を参照。"

jq -n --arg ctx "$ctx" '{"systemMessage":"[no-delegation] 本文にユーザー操作依頼を検出","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$ctx}}'
exit 0
