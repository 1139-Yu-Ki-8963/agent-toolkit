#!/usr/bin/env bash
# PostToolUse(Write|Edit|MultiEdit) — managed ディレクトリへの書き込みを検知し、
# managing-agent-configs スキルの該当種別での実行を advisory で促す。
set -euo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file_path" ] && exit 0

asset_type=""
case "$file_path" in
  */skills/*/SKILL.md)              asset_type="skills" ;;
  */.claude/rules/*/rule.md)        asset_type="rules" ;;
  */routines/*/ルーティン設計書.md)  asset_type="routines" ;;
  */tools/hooks/*.sh)               asset_type="hooks" ;;
esac
[ -z "$asset_type" ] && exit 0

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$script_dir/lib/marker-path.sh"

needed_marker="$(marker_path "$cwd" "$session" "managing-agent-configs-${asset_type}-needed")"
touch "$needed_marker"
passed_marker="$(marker_path "$cwd" "$session" "managing-agent-configs-${asset_type}-test-passed")"
rm -f "$passed_marker" 2>/dev/null || true

jq -n --arg type "$asset_type" '{
  hookSpecificOutput: {
    additionalContext: ("[MANAGING-REVIEW-REQUIRED] managed ディレクトリのファイルが編集されました。Skill(\"managing-agent-configs\") を種別 " + $type + " で実行してレビュー・テストを完了させてください。テスト未完了のままコミットすると block されます。")
  }
}'
exit 0
