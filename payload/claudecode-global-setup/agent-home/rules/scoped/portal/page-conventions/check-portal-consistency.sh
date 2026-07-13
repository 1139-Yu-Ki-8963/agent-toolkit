#!/bin/sh
# PostToolUse(Write|Edit|MultiEdit) hook。
# ai-management-portal のページファミリー・表記・並び順規約（同ディレクトリ rule.md 正本）への
# 違反を検知し、advisory（block なし・exit 0）で additionalContext を注入する。
#
# 対象: agent-home/ai-management-portal/{data/manifest.js, claude/*.html, design/*.html, catalog/*.html, index.html}
# 判定本体: check-portal-consistency.mjs（node）。並び順・リンク先系統・tooling.html の表記完全一致のみを機械チェックする。
# 表記ゆれ（日本語⇔英語の文脈判断）は rule.md のレビュー観点表で人間/Claude が判断する。

input="$(cat)"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

case "$file_path" in
  */ai-management-portal/data/manifest.js|*/ai-management-portal/claude/*.html|*/ai-management-portal/design/*.html|*/ai-management-portal/catalog/*.html|*/ai-management-portal/index.html) ;;
  *) exit 0 ;;
esac

script_dir="$(cd "$(dirname "$0")" && pwd)"
checker="$script_dir/check-portal-consistency.mjs"
[ -f "$checker" ] || exit 0

result="$(node "$checker" 2>&1)"
status=$?

if [ "$status" -ne 0 ]; then
  escaped="$(printf '%s' "$result" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' '|' | sed 's/|/\\n/g')"
  printf '{"systemMessage":"[フック発火] ポータルページ規約違反を検知しました","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[PORTAL-CONSISTENCY-WARN] ai-management-portal のページファミリー・並び順規約（~/.claude/rules/scoped/portal/page-conventions/rule.md）に違反する可能性があります。以下を確認し修正してください:\\n%s"}}' "$escaped"
fi

exit 0
