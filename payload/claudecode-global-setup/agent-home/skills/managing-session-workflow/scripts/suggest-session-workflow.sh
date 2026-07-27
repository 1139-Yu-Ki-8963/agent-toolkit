#!/usr/bin/env bash
# suggest-session-workflow.sh
# timing: SessionStart
# advisory 注入のみ（exit 0）。Skill() は呼べないため誘導メッセージを注入する
# 全セッションで発火する（スキル側でフロー要否を判定する）

set -euo pipefail

cwd="${PWD:-}"
[ -z "$cwd" ] && exit 0

# git リポジトリならプロジェクト名を含める（任意情報）
git_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || git_root=""

if [ -n "$git_root" ]; then
  project_name="$(basename "$git_root")"
  echo "[SESSION-WORKFLOW-HINT] プロジェクト検出: ${project_name}。Skill(\"managing-session-workflow\") を起動してセッションの状態確認とフロー誘導を実行してください。" >&2
else
  echo "[SESSION-WORKFLOW-HINT] Skill(\"managing-session-workflow\") を起動してセッションの状態確認とフロー誘導を実行してください。" >&2
fi

exit 0
