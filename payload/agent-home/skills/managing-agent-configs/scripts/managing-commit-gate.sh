#!/usr/bin/env bash
# PreToolUse(Bash) — managed ファイルを含む git commit を、
# managing-agent-configs スキルの該当種別のテスト完了マーカーがない場合に block する。
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

case "$cmd" in
  "git commit"*) ;;
  *) exit 0 ;;
esac

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0

staged=$(cd "$cwd" && git diff --cached --name-only 2>/dev/null) || exit 0
[ -z "$staged" ] && exit 0

. "$HOME/agent-home/tools/hooks/lib/marker-path.sh"

types_needed=""
while IFS= read -r f; do
  case "$f" in
    skills/*/SKILL.md)
      echo "$types_needed" | grep -q "skills" || types_needed="${types_needed}skills "
      ;;
    .claude/rules/*/rule.md)
      echo "$types_needed" | grep -q "rules" || types_needed="${types_needed}rules "
      ;;
    .claude/rules/*/prh.yml)
      echo "$types_needed" | grep -q "rules" || types_needed="${types_needed}rules "
      ;;
    rules/*/prh.yml)
      echo "$types_needed" | grep -q "rules" || types_needed="${types_needed}rules "
      ;;
    routines/*/ルーティン設計書.md)
      echo "$types_needed" | grep -q "routines" || types_needed="${types_needed}routines "
      ;;
    tools/hooks/*.sh)
      echo "$types_needed" | grep -q "hooks" || types_needed="${types_needed}hooks "
      ;;
  esac
done <<< "$staged"

[ -z "$types_needed" ] && exit 0

missing=""
for asset_type in $types_needed; do
  passed_marker="$(marker_path "$cwd" "$session" "managing-agent-configs-${asset_type}-test-passed")"
  if [ ! -f "$passed_marker" ]; then
    missing="${missing}${asset_type} "
  fi
done

missing=$(echo "$missing" | xargs)
[ -z "$missing" ] && exit 0

jq -n --arg types "$missing" '{
  hookSpecificOutput: {
    additionalContext: ("[MANAGING-COMMIT-BLOCK] managed ファイルのテストが未完了です（種別: " + $types + "）。\n\n対応する種別で Skill(\"managing-agent-configs\") を実行し、テストまで完了させてください。テスト PASS 時にマーカーが書き出され、コミットが許可されます。")
  }
}'
exit 2
