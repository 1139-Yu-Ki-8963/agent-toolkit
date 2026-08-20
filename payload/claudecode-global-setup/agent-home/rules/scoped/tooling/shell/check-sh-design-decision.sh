#!/usr/bin/env bash
# PostToolUse(Write|Edit|MultiEdit) hook: warn when a new .sh script is created
# without a corresponding 設計判断 section in its parent rule.md / SKILL.md.
#
# Rationale: ~/.claude/rules/scoped/tooling/shell/rule.md requires every newly-authored .sh file
# to ship with a 設計判断 section describing the necessity and why Bash direct
# invocation or existing Makefile / package.json scripts cannot substitute.
#
# Does NOT exit 2 — warning only. Next turn must author the 設計判断 or revert.

set -euo pipefail

input="$(cat)"
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file" ] && exit 0
[ ! -f "$file" ] && exit 0

# Filter: .sh files only
case "${file##*.}" in
  sh) ;;
  *) exit 0 ;;
esac

# Skip infrastructure / vendor paths
case "$file" in
  */node_modules/*) exit 0 ;;
  */.husky/*) exit 0 ;;
  "$HOME/agent-home/tools/hooks/"*) exit 0 ;;
  "$HOME/.claude/hooks/"*) exit 0 ;;
  */skills/*/scripts/*) exit 0 ;;
esac

# Determine git repo root; skip if file already tracked (edit of existing .sh
# is exempt — the requirement is for newly-authored scripts).
file_dir=$(dirname "$file")
repo_root=$(cd "$file_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$repo_root" ]; then
  if git -C "$repo_root" ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
    exit 0
  fi
fi

basename_no_ext=$(basename "$file" .sh)

# Search for 設計判断 section in parent rule.md / SKILL.md.
# The hook's parent document depends on its placement:
#   rules 配下の <hook>.sh → 同居 rule.md（旧 *-rules/ と新 <scope>/<topic>/<name>/ の両形式を包含）
#   skills/<name>/scripts/<name>.sh → ../../SKILL.md
canon_docs=()

# Pattern: hook と同じディレクトリに rule.md が同居していればそれが正本
parent_dir=$(dirname "$file")
if [ -f "$parent_dir/rule.md" ]; then
  canon_docs+=( "$parent_dir/rule.md" )
fi

# Pattern: skills/<skill>/scripts/<hook>.sh → SKILL.md two levels up
if [[ "$parent_dir" == */scripts ]]; then
  skill_dir=$(dirname "$parent_dir")
  canon_docs+=( "$skill_dir/SKILL.md" )
fi

# Also check legacy ADR directories for backward compat
adr_dirs=()
[ -n "$repo_root" ] && adr_dirs+=( "$repo_root/docs/adr" "$repo_root/.claude/adr" )
adr_dirs+=( "$HOME/.claude/adr" "$HOME/agent-home/adr" )

# Check canon docs for ## 設計判断 section mentioning the basename
# bash 3.2 互換: 空配列 + set -u で unbound variable が起きるため "${arr[@]+"${arr[@]}"}" を使う
for doc in "${canon_docs[@]+"${canon_docs[@]}"}"; do
  [ -f "$doc" ] || continue
  if grep -q '## 設計判断' "$doc" 2>/dev/null && grep -q "$basename_no_ext" "$doc" 2>/dev/null; then
    exit 0
  fi
done

# Legacy fallback: check ADR directories
for dir in "${adr_dirs[@]}"; do
  [ -d "$dir" ] || continue
  if grep -rl --include='*.md' -e "$basename_no_ext" "$dir" 2>/dev/null | head -1 >/dev/null; then
    exit 0
  fi
done

ctx="[DESIGN-DECISION-REQUIRED]
file=$file
basename=${basename_no_ext}.sh

新規シェルスクリプトを作成しました。~/.claude/rules/scoped/tooling/shell/rule.md に従い、対応する設計判断を記録してください。

必要な手順:
1. 配置先の正本ドキュメント（rule.md / SKILL.md）内に ## 設計判断 セクションを記載
2. セクション内に次の 4 項目を含める:
   - 必要性: なぜスクリプト化が必要か（繰り返し利用 / トークン節約 / 複雑な分岐 / hook 連携 など）
   - 代替案を採用しなかった理由: Bash ツール直叩き・既存 Makefile 拡張・package.json scripts 追加で代替できない理由
   - 保守責任者: 誰が更新するか（人手 / routine）
   - 廃棄条件: いつ削除してよいか
3. ## 設計判断 セクション内に文字列 '${basename_no_ext}' を含めること。本 hook はこの文字列の存在で検出します。

設計判断が書けない（必要性を説明できない）場合は本スクリプトを削除し、Bash ツールで直接実行する形に戻してください。"

jq -n --arg ctx "$ctx" --arg msg "[フック発火] 設計判断必須: 新規 .sh 検出" \
  '{"systemMessage":$msg,"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$ctx}}'
exit 0
