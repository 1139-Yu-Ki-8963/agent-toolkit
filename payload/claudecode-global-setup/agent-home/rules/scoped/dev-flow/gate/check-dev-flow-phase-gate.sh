#!/usr/bin/env bash
# check-dev-flow-phase-gate.sh
# PreToolUse(Write|Edit) で以下を block する:
#   1. .flow-progress.json への直接書き込み（update-flow-status.sh 経由のみ許可）
#   2. ~/Projects/ 配下のコードファイル編集（前提 Phase 未完了時）
set -euo pipefail

input=$(cat)

[ "${CLAUDE_HOOKS_TEST:-}" = "1" ] && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
case "$cwd" in
  */agent-home|*/agent-home/*) exit 0 ;;
esac

[ "${CLAUDE_SKILL_NAME:-}" = "creating-new-project" ] && exit 0

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file_path" ] && exit 0

case "$file_path" in
  /*) abs="$file_path" ;;
  *) abs="$cwd/$file_path" ;;
esac

# --- .flow-progress.json 直接書き換え防止 ---
case "$(basename "$abs")" in
  .flow-progress.json)
    ctx="[DEV-FLOW-PHASE-GATE-BLOCK] .flow-progress.json への直接書き込みは禁止されています。Phase 進捗は update-flow-status.sh 経由で更新してください。"
    jq -n --arg ctx "$ctx" '{"decision":"block","systemMessage":"[フック発火] FLOW-GATE: .flow-progress.json 直接編集","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
    exit 2
    ;;
esac

# --- ~/Projects/ 配下のみチェック ---
case "$abs" in
  "$HOME/Projects/"*) ;;
  *) exit 0 ;;
esac

dir=$(dirname "$abs")
# 新規ネストディレクトリへの初回 Write では $dir がまだ実在しないため、
# 実在する最初の祖先ディレクトリまで遡ってから git rev-parse する
# （worktree ルート自体は常に実在するため、中間ディレクトリが未作成でも正しく解決できる）
check_dir="$dir"
while [ ! -d "$check_dir" ] && [ "$check_dir" != "/" ] && [ "$check_dir" != "." ]; do
  check_dir=$(dirname "$check_dir")
done
project_root=$(git -C "$check_dir" rev-parse --show-toplevel 2>/dev/null || true)

if [ -z "$project_root" ]; then
  rel="${abs#$HOME/Projects/}"
  project_name="${rel%%/*}"
  project_root="$HOME/Projects/$project_name"
fi

rel_from_root="${abs#$project_root/}"

case "$rel_from_root" in
  .claude/*|CLAUDE.md|docs/*) exit 0 ;;
esac

flow_context="$project_root/.claude/rules/always/project-context/flow-values.yml"
if [ ! -f "$flow_context" ]; then
  ctx="[DEV-FLOW-PHASE-GATE-BLOCK] 実装フローが未設定です。orchestrating-dev-flow を起動してから実装してください。対象: $abs"
  jq -n --arg ctx "$ctx" '{"decision":"block","systemMessage":"[フック発火] FLOW-GATE: 実装フロー未設定","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  exit 2
fi

# --- Phase 順序検証 ---
current_phase=""
route=""
progress_file="$project_root/.flow-progress.json"

if [ -f "$progress_file" ]; then
  current_phase=$(jq -r '.current_phase // empty' "$progress_file" 2>/dev/null)
  route=$(jq -r '.route // empty' "$progress_file" 2>/dev/null)
fi

if [ -z "$current_phase" ]; then
  session="${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}"
  status_dir="${TMPDIR:-/tmp}/claude-hooks/${session}"
  status_file="${status_dir}/flow-status.json"
  if [ -f "$status_file" ]; then
    current_phase=$(jq -r '.current_phase // empty' "$status_file" 2>/dev/null)
  fi
fi

[ -z "$current_phase" ] && current_phase="0"

# Phase D / I は通過
case "$current_phase" in
  D|I) exit 0 ;;
esac

# ルート別のコード書き込み前提条件
code_prereqs=""
case "$route" in
  feature-with-full-planning)     code_prereqs="1 2 3 4 5" ;;
  feature-with-quick-delivery)    code_prereqs="1 2 5" ;;
  refactor-with-safety-guarantee) code_prereqs="1 2 5" ;;
  config-with-review-and-verify)  exit 0 ;;
  incident-with-emergency-path)   exit 0 ;;
  "")
    # route 不明: 従来の current_phase >= 6 フォールバック
    phase_num=$((current_phase + 0)) 2>/dev/null || phase_num=0
    if [ "$phase_num" -lt 6 ]; then
      ctx="[DEV-FLOW-PHASE-GATE-BLOCK] 現在 Phase ${current_phase} です。Phase 6（実装）に到達するまでコードの書き込みはできません。対象: $abs"
      jq -n --arg ctx "$ctx" '{"decision":"block","systemMessage":"[フック発火] FLOW-GATE: Phase 6 未到達","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
      exit 2
    fi
    exit 0
    ;;
esac

# phases_completed を検証
if [ -f "$progress_file" ]; then
  missing=""
  for prereq in $code_prereqs; do
    if ! jq -e --arg p "$prereq" '.phases_completed | map(tostring) | index($p)' "$progress_file" > /dev/null 2>&1; then
      missing="$missing Phase-$prereq"
    fi
  done

  if [ -n "$missing" ]; then
    ctx="[DEV-FLOW-PHASE-GATE-BLOCK] コード書き込みの前提 Phase が未完了です。不足:${missing}。ルート: ${route}。対象: ${abs}"
    jq -n --arg ctx "$ctx" '{"decision":"block","systemMessage":"[フック発火] FLOW-GATE: 前提 Phase 未完了","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
    exit 2
  fi
else
  # progress_file がない場合はフォールバック
  phase_num=$((current_phase + 0)) 2>/dev/null || phase_num=0
  if [ "$phase_num" -lt 6 ]; then
    ctx="[DEV-FLOW-PHASE-GATE-BLOCK] 現在 Phase ${current_phase} です。Phase 6（実装）に到達するまでコードの書き込みはできません。対象: $abs"
    jq -n --arg ctx "$ctx" '{"decision":"block","systemMessage":"[フック発火] FLOW-GATE: Phase 6 未到達","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
    exit 2
  fi
fi

exit 0
