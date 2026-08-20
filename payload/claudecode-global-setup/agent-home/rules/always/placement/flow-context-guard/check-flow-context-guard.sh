#!/usr/bin/env bash
# check-flow-context-guard.sh — PreToolUse(Bash)
# git commit 時に .claude/rules/always/project-context/flow-values.yml の不在を検知する。
# ~/Projects/ 配下の git リポジトリのみ対象。advisory のみ（exit 0）。block しない。
# check-dev-flow-phase-gate.sh（Write/Edit 時に block）を補完し、
# .claude/ 配下のみを編集するリポジトリ（コードゲートの対象外）でも commit 時に気付けるようにする。
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

case "$cmd" in
  *git*commit*) ;;
  *) exit 0 ;;
esac

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

# ~/Projects/ 配下のみ対象
case "$cwd" in
  "$HOME/Projects/"*) ;;
  *) exit 0 ;;
esac

repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$repo_root" ] && exit 0

flow_context="$repo_root/.claude/rules/always/project-context/flow-values.yml"
[ -f "$flow_context" ] && exit 0

cat <<'JSON'
{"systemMessage":"[フック発火] FLOW-CONTEXT-GUARD: flow-values.yml 未配置","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[FLOW-CONTEXT-GUARD] .claude/rules/always/project-context/flow-values.yml が未配置です。orchestrating-dev-flow の Phase ゲートで今後の編集がブロックされる可能性があります。Skill(creating-new-project) の実行、またはアプリケーションコードを持たないリポジトリ（.claude/skills 等のみを管理）の場合はデフォルト内容での手動作成を検討してください。"}}
JSON

exit 0
