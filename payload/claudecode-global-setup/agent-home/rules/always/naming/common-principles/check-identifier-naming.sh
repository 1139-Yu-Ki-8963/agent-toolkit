#!/usr/bin/env bash
# check-identifier-naming.sh — PostToolUse(Write) hook
# 新規 .sh ファイル作成時の命名規約チェック。
# 対象パス: ~/.claude/rules/** / ~/agent-home/skills/*/scripts/** / ~/agent-home/tools/**
# block: 禁止動詞（nuke-/scrub-/kill-）・単独 main → [IDENTIFIER-NAMING-BLOCK] exit 2
# advisory: ファイル名 slug と注入タグの派生不一致 → [IDENTIFIER-NAMING] exit 0
set -u

input="$(cat)"
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$tool_name" = "Write" ] || exit 0

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file_path" ] && exit 0

# .sh ファイルのみ
case "$file_path" in *.sh) ;; *) exit 0 ;; esac

# 対象パス判定
case "$file_path" in
  */.claude/rules/*) ;;
  */agent-home/skills/*/scripts/*) ;;
  */agent-home/tools/*) ;;
  *) exit 0 ;;
esac

# 既存ファイルの編集は対象外（新規作成のみ）
was_created=$(printf '%s' "$input" | jq -r '.tool_result.was_created // empty' 2>/dev/null)
if [ "$was_created" != "true" ]; then
  # PostToolUse では was_created がない場合がある。git で判定
  if cd "$(dirname "$file_path")" 2>/dev/null; then
    git_status=$(git status --porcelain -- "$(basename "$file_path")" 2>/dev/null)
    case "$git_status" in
      "??"*) ;; # untracked = 新規
      *) exit 0 ;; # tracked = 既存
    esac
  fi
fi

basename=$(basename "$file_path" .sh)

# Block: 禁止動詞
case "$basename" in
  nuke-*|scrub-*|kill-*)
    ctx="[IDENTIFIER-NAMING-BLOCK] ファイル名 ${basename} に禁止動詞（nuke/scrub/kill）が使用されています。~/.claude/rules/always/naming/common-principles/naming-values.txt の「識別子形式表」節の許可動詞リストを参照してください。"
    jq -n --arg ctx "$ctx" \
      '{"decision":"block","reason":"禁止動詞","systemMessage":"[フック発火] 命名チェック","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$ctx}}'
    exit 2
    ;;
esac

# Block: 単独 main（main-agent/main-tree/main-branch は許可）
if echo "$basename" | grep -qE '(^|-)main(-|$)'; then
  if ! echo "$basename" | grep -qE '(main-agent|main-tree|main-branch|agent-main|tree-main|branch-main)'; then
    ctx="[IDENTIFIER-NAMING-BLOCK] ファイル名 ${basename} に単独 main が含まれています。main-agent / main-tree / main-branch のいずれかに具体化してください。~/.claude/rules/always/naming/common-principles/naming-values.txt の「多義語表」を参照。"
    jq -n --arg ctx "$ctx" \
      '{"decision":"block","reason":"単独main","systemMessage":"[フック発火] 命名チェック","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$ctx}}'
    exit 2
  fi
fi

# Advisory: 派生一致チェック（ファイル内容のタグとファイル名 slug の一致）
content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
if [ -n "$content" ]; then
  tags=$(echo "$content" | grep -oE '\[[A-Z][A-Z0-9-]+(-BLOCK|-SKIP)?\]' | sort -u)
  if [ -n "$tags" ]; then
    # ファイル名からslugを抽出（先頭の動詞を除去）
    slug=$(echo "$basename" | sed -E 's/^(check|cleanup|delete|dispatch|record|validate|notify)-//')
    slug_upper=$(echo "$slug" | tr 'a-z-' 'A-Z-')
    mismatch=""
    while IFS= read -r tag; do
      tag_inner=$(echo "$tag" | tr -d '[]' | sed -E 's/-(BLOCK|SKIP)$//')
      if [ "$tag_inner" != "$slug_upper" ]; then
        mismatch="$mismatch $tag"
      fi
    done <<< "$tags"
    if [ -n "$mismatch" ]; then
      ctx="[IDENTIFIER-NAMING] ファイル名 ${basename} のslug(${slug_upper})と注入タグ(${mismatch})が派生一致していません。~/.claude/rules/always/naming/common-principles/rule.md 原則6（派生一致）を確認してください。"
      jq -n --arg ctx "$ctx" \
        '{"systemMessage":"[フック発火] 命名チェック（advisory）","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$ctx}}'
    fi
  fi
fi

exit 0
