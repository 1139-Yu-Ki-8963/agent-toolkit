#!/usr/bin/env bash
# PostToolUse(Write|Edit|MultiEdit) — managed ディレクトリへの書き込みを検知し、
# managing-agent-configs スキルの該当種別での実行を advisory で促す。
set -euo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file_path" ] && exit 0

asset_type=""
case "$file_path" in
  */skills/*/SKILL.md)                    asset_type="skills" ;;
  */.claude/rules/*/rule.md)              asset_type="rules" ;;
  */.claude/rules/*/prh.yml)              asset_type="rules" ;;
  */routines/*/ルーティン設計書.md)        asset_type="routines" ;;
  */tools/hooks/*.sh)                     asset_type="hooks" ;;
esac
[ -z "$asset_type" ] && exit 0

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
if [ -n "$session" ]; then
  log_file="$HOME/agent-home/sessions/.skill-log/${session}.jsonl"
  if [ -f "$log_file" ] && grep -q "\"skill\":\"managing-agent-configs\"" "$log_file" 2>/dev/null; then
    exit 0
  fi
fi

if [ -n "$session" ]; then
  . "$HOME/agent-home/tools/hooks/lib/marker-path.sh"
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
  [ -z "$cwd" ] && cwd="$PWD"
  needed_marker="$(marker_path "$cwd" "$session" "managing-agent-configs-${asset_type}-needed")"
  touch "$needed_marker"
  passed_marker="$(marker_path "$cwd" "$session" "managing-agent-configs-${asset_type}-test-passed")"
  rm -f "$passed_marker" 2>/dev/null || true
fi

jq -n --arg type "$asset_type" '{
  hookSpecificOutput: {
    additionalContext: ("[MANAGING-REVIEW-REQUIRED] managed ディレクトリのファイルが編集されました。Skill(\"managing-agent-configs\") を種別 " + $type + " で実行してレビュー・テストを完了させてください。テスト未完了のままコミットすると block されます。")
  }
}'
exit 0
