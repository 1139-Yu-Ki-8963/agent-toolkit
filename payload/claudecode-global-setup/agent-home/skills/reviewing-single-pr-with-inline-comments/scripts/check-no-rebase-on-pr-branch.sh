#!/usr/bin/env bash
# PR worktree での git rebase を block し、git merge を使うよう誘導する。
# rebase はコミット SHA を書き換えるため force push が必要になる。
# force push は deny ルールで禁止されているため詰まる。

set -u

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# git rebase でなければスキップ
printf '%s' "$cmd" | grep -qE '^git[[:space:]]+rebase[[:space:]]' || exit 0

# --abort / --continue / --skip は進行中操作なのでスキップ
printf '%s' "$cmd" | grep -qE '^git[[:space:]]+rebase[[:space:]]+(--abort|--continue|--skip)' && exit 0

# cwd を取得
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

# PR worktree コンテキスト判定
# 1. cwd が *-pr-[0-9]* パターン（例: <project>-pr-829）
# 2. または .claude/worktrees/ 配下
is_pr_worktree=n
case "$cwd" in
  *-pr-[0-9]*) is_pr_worktree=y ;;
  */.claude/worktrees/*) is_pr_worktree=y ;;
esac

[ "$is_pr_worktree" = "n" ] && exit 0

jq -n '{
  "decision": "block",
  "systemMessage": "[REBASE-BLOCKED] PR ブランチでの rebase を中断しました",
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "[REBASE-BLOCKED] PR ブランチで `git rebase` を実行しようとしました。rebase はコミット SHA を書き換えるため force push が必要になります（force push は deny ルールで禁止）。\n\nmain の最新を取り込む場合は代わりに以下を実行してください:\n  git fetch origin main\n  git merge origin/$BASE_BRANCH --no-edit\n  git push origin HEAD:<branch>\n\n通常 push で済みます。fixing-review-findings スキルの Phase 2 を参照してください。"
  }
}'
exit 2
