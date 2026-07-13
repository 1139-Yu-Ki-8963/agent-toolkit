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
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file" ] && exit 0

# Discriminator: must contain .claude/ or agent-home/ AND a subsequent /hooks/ segment.
# The intermediate path between (.claude|agent-home) and hooks/ is optional, so
# both ~/.claude/hooks/foo.sh (direct child) and ~/.claude/plugins/x/hooks/foo.sh
# (nested) are caught.
if ! printf '%s' "$file" | grep -qE '(/\.claude/|/agent-home/)([^/]+/)*hooks/'; then
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

# Determine the suggested canonical placement based on ownership/scope heuristics.
# We cannot infer ownership precisely; suggest both quadrants by example.
hook_name=$(basename "$file" .sh)

ctx="[HOOKS-BUCKET-FORBIDDEN]
file=$file

flat hooks/ バケットへの新規ファイル作成は禁止されています。

正本: ~/agent-home/ai-management-portal/design/hooks.html
規約: ~/.claude/rules/scoped/agent-config/hooks/rule.md

配置先を 4 象限から選び直してください:

  skill × global   → ~/agent-home/skills/<skill>/scripts/${hook_name}.sh
  skill × project  → <repo>/.claude/skills/<skill>/scripts/${hook_name}.sh
  独立規約 × global → ~/.claude/rules/<scope>/<topic>/<rule>/${hook_name}.sh
  独立規約 × project → <repo>/.claude/rules/<rule>-rules/${hook_name}.sh

判定の 2 軸:
  - ownership: 特定 skill の前提強制なら skill 延長 / 単一 skill に紐付かない system メタ規約なら独立規約
  - scope: 全プロジェクトで効かせるなら global / 単一プロジェクトのみなら project

次のアクション:
  1. canonical 配置のフォルダを mkdir -p で作成
  2. Write 先パスを書き換えて再実行
  3. 配置先の rule.md 内に ## 設計判断 セクションを記載（必要性 / 代替案不採用理由 / 保守責任者 / 廃棄条件）
  4. ~/agent-home/ai-management-portal/catalog/hooks.html の HOOKS 配列に登録
  5. settings.json に新 path で hook を登録"

jq -n --arg ctx "$ctx" --arg msg "[フック発火] flat hooks/ バケット禁止: $(basename "$file")" \
  '{"systemMessage":$msg,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'

exit 2
