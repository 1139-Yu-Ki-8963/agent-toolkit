#!/usr/bin/env bash
set -euo pipefail

# check-flow-progress.sh
# git push 時に flow-status.json の存在をチェック。advisory のみ（exit 0）。

input="$(cat)"
command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"

# git push 以外はスキップ
case "$command" in
  *"git push"*) ;;
  *) exit 0 ;;
esac

# ブランチ削除 push（Phase 10 Step 10-3 の正規操作）は、進捗ファイルの正規削除後に
# 実行されるためチェック対象外（[FLOW-PROGRESS-MISSING] の既知の誤検知を防ぐ）
case "$command" in
  *"--delete"*|*" -d "*) exit 0 ;;
esac

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

. "$HOME/.claude/rules/scoped/agent-config/hooks/shared/transcript-query.sh"
session="${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}"
status_file="$(marker_path "$cwd" "$session" "flow-status.json")"
# update-flow-status.sh の sandbox フォールバック先も確認する
sandbox_fallback_file="/tmp/claude/claude-hooks/${session}/flow-status.json"

if [ ! -f "$status_file" ] && [ ! -f "$sandbox_fallback_file" ]; then
  cat <<'JSON'
{"systemMessage":"[フック発火] フロー: flow-status.json 未検出","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[FLOW-PROGRESS-MISSING] フロー進捗ファイル（flow-status.json）が見つかりません。orchestrating-dev-flow を経由せずに push しようとしている可能性があります。"}}
JSON
fi

exit 0
