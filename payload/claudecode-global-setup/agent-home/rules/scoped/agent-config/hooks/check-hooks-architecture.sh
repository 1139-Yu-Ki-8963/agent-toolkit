#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit) hook: block creation of new hook scripts
# under flat hooks/ buckets, per ~/.claude/rules/scoped/agent-config/hooks/rule.md
# (full design at ~/agent-home/ai-management-portal/design/hooks.html).
#
# Forbidden paths (new file creation only — existing edits are allowed as legacy):
#   ~/agent-home/tools/hooks/
#   ~/.claude/hooks/
#   ~/.claude/**/hooks/      (plugin marketplaces, etc.)
#   <repo>/.claude/hooks/
#   <repo>/.claude/**/hooks/
#
# Discriminator: a path is forbidden iff it contains BOTH
#   (a) a "/.claude/" OR "/agent-home/" segment
#   (b) a "/hooks/" segment after (a)
# This excludes React's frontend/src/hooks/, .husky/, .git/hooks/, node_modules/**/hooks/
# because those paths do not pass condition (a).
#
# Exits with code 2 on violation to actually block the Write/Edit.

set -euo pipefail

input="$(cat)"
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -z "$file" ] && exit 0

# Discriminator: must contain .claude/ or agent-home/ AND a subsequent /hooks/ segment.
# The intermediate path between (.claude|agent-home) and hooks/ is optional, so
# both ~/.claude/hooks/foo.sh (direct child) and ~/.claude/plugins/x/hooks/foo.sh
# (nested) are caught.
if ! printf '%s' "$file" | grep -qE '(/\.claude/|/agent-home/)([^/]+/)*hooks/'; then
  exit 0
fi

# 正規のルール配置構造 rules/<scope>/<topic>/hooks/ は禁止対象から除外
if printf '%s' "$file" | grep -qE '/rules/[^/]+/[^/]+/hooks/'; then
  exit 0
fi

# Exclude vendored / plugin-managed paths from the block (they are out of Claude's scope).
case "$file" in
  */node_modules/*) exit 0 ;;
  */.git/hooks/*) exit 0 ;;
esac

# Allow edits to existing files. Only block new file creation.
# A "new" file is one that does not exist on disk yet.
[ -e "$file" ] && exit 0

ctx="[HOOKS-BUCKET-FORBIDDEN] file=${file} — flat hooks/ バケットへの新規ファイル作成は禁止。4象限の配置先を選び直すこと。規約: ~/.claude/rules/scoped/agent-config/hooks/rule.md"

jq -n --arg ctx "$ctx" --arg msg "[フック発火] flat hooks/ バケット禁止: $(basename "$file")" \
  '{"systemMessage":$msg,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'

exit 2
