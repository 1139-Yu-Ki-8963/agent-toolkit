#!/usr/bin/env bash
# check-worktree-required.sh
# PreToolUse(Write|Edit|MultiEdit|NotebookEdit) でメイン作業ツリーへの直接編集を block する。
# 外部化前のインラインコマンドと完全等価（jq 引数・case 分岐・printf 出力を一字一句保持）。
set -euo pipefail

input=$(cat)
# サブエージェントも含め全エージェントに worktree 外編集ブロックを適用する。
# 旧: サブエージェントを素通りさせ check-orchestrator-cwd-write.sh で判定していたが、
# 当該 Hook が存在しないためサブエージェントが無検査だった（バグ修正）。
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[ -z "$file" ] && exit 0
[ -f "/tmp/.allow-main-edit" ] && { rm -f "/tmp/.allow-main-edit"; exit 0; }
case "$file" in
  /*) abs="$file";;
  *) abs="$PWD/$file";;
esac
case "$abs" in
  "$HOME/.claude/"*) exit 0;;
  "$HOME/agent-home/"*) exit 0;;
esac
dir=$(dirname "$abs")
[ ! -d "$dir" ] && exit 0
repo=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
[ -z "$repo" ] && exit 0
[ -f "$repo/.git" ] && exit 0
ctx=$(printf '[WORKTREE-REQUIRED] メイン作業ツリー編集を検出: %s。~/agent-home/skills/parallel-dev-worktree/SKILL.md に従い parallel-dev-worktree スキルで worktree を切ること。例外マーカー /tmp/.allow-main-edit は人間専用（ターミナルから手動 touch・ワンショット消費）。エージェントによる touch は permissions.deny で自動拒否されるため試行しないこと。例外パス: ~/.claude/*, ~/agent-home/* main統合時にmain作業ツリーの.claude/skills・.claude/hooks等のCLI保護パスへ書き込みが発生する場合はdangerouslyDisableSandbox:trueと対話セッションでの承認が必須（Auto Mode不可、サブエージェント経由でも回避不可）。詳細はSKILL.mdのGotchasを参照。' "$abs")
jq -n --arg ctx "$ctx" '{"decision":"block","systemMessage":"[フック発火] WORKTREE-REQUIRED: main 直編集をブロック","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
