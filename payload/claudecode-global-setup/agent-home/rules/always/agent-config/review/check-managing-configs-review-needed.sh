#!/usr/bin/env bash
# PostToolUse(Write|Edit|MultiEdit) — managed ディレクトリへの書き込みを検知し、
# managing-agent-configs スキルの該当種別での実行を advisory で促す。
set -euo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file_path" ] && exit 0

# T2: fail-open 自己申告。PostToolUse はブロック能力がないため、lib 不在時は
# additionalContext で自己申告した上で exit 0 する（マーカー処理はスキップ）。
# managed_asset_type() が lib 内にあるため、種別判定自体も lib 依存。
MARKER_LIB="${MANAGING_MARKER_LIB:-$HOME/.claude/rules/scoped/agent-config/hooks/shared/transcript-query.sh}"
if [ ! -f "$MARKER_LIB" ]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: "[MANAGING-GATE-DISABLED] マーカー処理をスキップしました（transcript-query.sh が見つかりません）。managed ファイルの可能性がある場合は Skill(\"managing-agent-configs\") を該当種別で実行してください。"
    }
  }'
  exit 0
fi
. "$MARKER_LIB"

asset_type="$(managed_asset_type "$file_path")"
[ -z "$asset_type" ] && exit 0

advisory_suppressed=0
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
if [ -n "$session" ]; then
  log_file="$HOME/agent-home/sessions/.skill-log/${session}.jsonl"
  if [ -f "$log_file" ] && grep -q "\"skill\":\"managing-agent-configs\"" "$log_file" 2>/dev/null; then
    advisory_suppressed=1
  fi
fi

[ "$advisory_suppressed" = "1" ] && exit 0

jq -n --arg type "$asset_type" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("[MANAGING-REVIEW-REQUIRED] managed ディレクトリのファイルが編集されました。Skill(\"managing-agent-configs\") を種別 " + $type + " で実行してレビュー・テストを完了させてください。")
  }
}'
exit 0
