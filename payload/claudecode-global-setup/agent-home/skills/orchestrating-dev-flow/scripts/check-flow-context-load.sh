#!/usr/bin/env bash
set -euo pipefail

# check-flow-context-load.sh
# Phase 3 以降で flow-values.yml 読み込みマーカーの存在をチェック。
# advisory のみ（exit 0）。flow-values.yml がないプロジェクトでも動く。

input="$(cat)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

# flow-values.yml 自体が存在しなければスキップ
fc="$cwd/.claude/rules/always/project-context/flow-values.yml"
[ ! -f "$fc" ] && exit 0

# マーカーチェック
. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"
session="${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}"
marker="$(marker_path "$cwd" "$session" "flow-context-loaded")"

if [ ! -f "$marker" ]; then
  cat <<'JSON'
{"systemMessage":"[フック発火] フロー: flow-values.yml 読み込みマーカー未検出","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[FLOW-CONTEXT-MISSING] flow-values.yml が存在しますが Phase 3 の読み込みマーカーがありません。Phase 3 でコンテキスト読み込みが完了しているか確認すること。"}}
JSON
fi

exit 0
