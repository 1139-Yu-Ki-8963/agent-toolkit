#!/usr/bin/env bash
# check-marker-antipattern.sh — PostToolUse(Write|Edit|MultiEdit)
# 新規 hook スクリプトにマーカーファイル作成パターンを検出したら advisory 注入。
# block しない（exit 0 のみ）。既存ファイルの編集は対象外。
# 規約: ~/.claude/rules/scoped/agent-config/hooks/rule.md「マーカーファイル禁止」節

set -euo pipefail

input="$(cat)"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)"
[ -z "$file_path" ] && exit 0

# 対象: .sh ファイルのみ
case "$file_path" in
  *.sh) ;;
  *) exit 0 ;;
esac

# 対象パス: rules/ または skills/*/scripts/ 配下のみ
case "$file_path" in
  */rules/*.sh|*/.claude/rules/*.sh|*/skills/*/scripts/*.sh) ;;
  *) exit 0 ;;
esac

# 既存ファイルの編集は対象外（新規作成のみ検査）
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"
if cd "$cwd" 2>/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git ls-files --error-unmatch "$file_path" >/dev/null 2>&1 && exit 0
fi

# ファイル内容を検査
[ ! -f "$file_path" ] && exit 0
content="$(cat "$file_path" 2>/dev/null || true)"
[ -z "$content" ] && exit 0

detected=""
if printf '%s' "$content" | grep -qE 'marker_path\b'; then
  detected="marker_path 呼び出し"
elif printf '%s' "$content" | grep -qE 'touch\s+"\$'; then
  detected="touch によるマーカーファイル作成"
elif printf '%s' "$content" | grep -qE 'echo\s+.*>\s*"\$.*count'; then
  detected="カウンタファイルへの書き込み"
elif printf '%s' "$content" | grep -qE 'cat\s+.*\.count'; then
  detected="カウンタファイルの読み取り"
fi

if [ -n "$detected" ]; then
  cat >&2 <<EOF
[MARKER-ANTIPATTERN] file=$file_path — 新規 hook スクリプトにマーカーファイル操作を検出: ${detected}。
マーカーファイルによる状態追跡は禁止。代替手段:
- livelock カウンタ → count_tag_in_transcript (transcript-query.sh)
- ゲートフラグ → check_skill_fired (transcript-query.sh)
- 単発完了フラグ → advisory のみ
規約: ~/.claude/rules/scoped/agent-config/hooks/rule.md「マーカーファイル禁止」節
EOF
fi

exit 0
