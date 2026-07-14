#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit) hook:
#   A) ~/.claude/CLAUDE.md への直接書き込みを警告 → [CLAUDE-MD-WRITE-WARN]（block しない）
#   B) ファイル内容に "CLAUDE.md §N / の第N章 / chapter N" パターンを block → [CLAUDE-MD-REF-BLOCK]
# 仕様: ~/.claude/rules/scoped/agent-config/claude-md/rule.md
# 設計判断: 同ディレクトリの design-notes.txt に記載

set +e

. "$HOME/agent-home/tools/hooks/shared/marker-path.sh" 2>/dev/null

input=""
if [ ! -t 0 ]; then
  input="$(cat 2>/dev/null || true)"
fi
[ -z "$input" ] && exit 0

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
case "$tool_name" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

# ── 検査A: CLAUDE.md 直接書き込み（警告のみ・block しない） ────────────────
# permissions.ask がユーザー承認ゲートを担うため、hook は警告に留める。
# ユーザーが「CLAUDE.md を編集して」と明示した場合は permissions.ask で承認→通過する。
claude_md="${HOME}/.claude/CLAUDE.md"
if [ -n "$file" ] && [ "$file" = "$claude_md" ]; then
  ctx="[CLAUDE-MD-WRITE-WARN]
file=$file

~/.claude/CLAUDE.md への書き込みです。ユーザーの明示的な指示がない場合は中止してください。

追記しようとした内容が rule / skill / hook に配置すべきものであれば、
配置判定規約（CONFIG-PLACEMENT）の決定木に従い適切な層に配置してください:
  ~/.claude/rules/scoped/agent-config/placement/rule.md"

  jq -n --arg ctx "$ctx" \
    '{"systemMessage":"[フック発火] CLAUDE.md 書き込み検知（permissions.ask で承認確認）","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  exit 0
fi

# ── セッション・カウンター（再帰防止） ──────────────────────────────────────
session="${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
[ -z "$session" ] && session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
session="${session:-nosession}"

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

if command -v marker_path >/dev/null 2>&1; then
  counter="$(marker_path "$cwd" "$session" claude-md-ref-block.count)"
else
  counter_dir="${TMPDIR:-/tmp}/claude-hooks/${session}"
  mkdir -p "$counter_dir" 2>/dev/null || true
  counter="${counter_dir}/claude-md-ref-block.count"
fi

hits=0
[ -f "$counter" ] && hits="$(cat "$counter" 2>/dev/null || echo 0)"
if [ "$hits" -ge 3 ] 2>/dev/null; then
  exit 0
fi

# ── 検査B: ファントム §N 参照 ──────────────────────────────────────────────
content="$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)"
new_str="$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty' 2>/dev/null)"
multi_str="$(printf '%s' "$input" | jq -r '.tool_input.edits[]?.new_string // empty' 2>/dev/null | tr '\n' ' ')"
all_content="${content}${new_str}${multi_str}"

[ -z "$all_content" ] && exit 0

if printf '%s' "$all_content" | grep -qE 'CLAUDE\.md[[:space:]]*(§|の第)[[:digit:]]|CLAUDE\.md[[:space:]]*chapter[[:space:]]*[[:digit:]]'; then
  hits=$((hits + 1))
  printf '%s' "$hits" > "$counter" 2>/dev/null || true

  if [ "$hits" -ge 3 ]; then
    exit 0
  fi

  ctx="[CLAUDE-MD-REF-BLOCK] CLAUDE.md への §N 参照を検出（file=${file:-content内}）。CLAUDE.md に章番号は存在しない。規約: ~/.claude/rules/scoped/agent-config/claude-md/rule.md"

  jq -n --arg ctx "$ctx" \
    '{"systemMessage":"[フック発火] CLAUDE.md ファントム §N 参照禁止","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  exit 2
fi

exit 0
