#!/usr/bin/env bash
set -euo pipefail

# update-flow-status.sh — ステータスラインに Phase/Step 進捗を反映する
#
# Usage:
#   update-flow-status.sh <phase_num> "<phase_name>" <current_step> <total_steps> "<step_name>"
#   update-flow-status.sh --init <route>
#
# --init: .flow-progress.json を初期化する（Phase 2 Step 2-5 で 1 回だけ呼ぶ）
#
# 通常モード:
#   1. flow-status.json を書き出す（ステータスライン用）
#   2. .flow-progress.json が存在すれば Phase 順序検証 + 進捗更新

# --- Route definitions ---
route_sequence() {
  case "$1" in
    feature-with-full-planning)    echo "1 2 3 4 5 6 7 8" ;;
    feature-with-quick-delivery)   echo "1 2 5 6 7 8" ;;
    config-with-review-and-verify) echo "1 2 D 7 8" ;;
    refactor-with-safety-guarantee) echo "1 2 5 7 8" ;;
    incident-with-emergency-path)  echo "1 2 I" ;;
    *) echo "" ;;
  esac
}

find_progress_file() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  [ -n "$root" ] && echo "$root/.flow-progress.json" || echo ""
}

# --- Init mode ---
if [ "${1:-}" = "--init" ]; then
  route="${2:?route required for --init}"
  seq=$(route_sequence "$route")
  if [ -z "$seq" ]; then
    echo "ERROR: unknown route: $route" >&2
    exit 1
  fi
  progress_file="$(find_progress_file)"
  [ -z "$progress_file" ] && { echo "ERROR: not in a git repository" >&2; exit 1; }

  cat > "$progress_file" <<JSON
{"route":"${route}","current_phase":"2","phases_completed":["1"]}
JSON
  exit 0
fi

# --- Normal mode ---
phase_num="${1:?phase_num required}"
phase_name="${2:?phase_name required}"
current_step="${3:?current_step required}"
total_steps="${4:?total_steps required}"
step_name="${5:?step_name required}"

. "$HOME/.claude/rules/scoped/agent-config/hooks/shared/transcript-query.sh"
cwd="${PWD}"
session="${CLAUDE_SESSION_ID:-${SESSION_ID:-}}"

# セッション ID 未設定時（サブエージェントの Bash 等）: worktree markers 内の
# 最新セッションディレクトリを引き継ぎ、"unknown" 名義での書き出し先分裂を緩和する。
if [ -z "$session" ]; then
  if wt="$(_marker_worktree_root "$cwd")" && [ -d "${wt}/.claude/markers" ]; then
    session="$(ls -1t "${wt}/.claude/markers" 2>/dev/null | head -1)"
  fi
  [ -z "$session" ] && session="unknown"
fi

status_file="$(marker_path "$cwd" "$session" "flow-status.json")"

# sandbox 有効の Bash は /tmp/claude-hooks へ書き込めない（filesystem 許可は
# /tmp/claude・$TMPDIR 等のみ）。marker_path が /tmp/claude-hooks へフォールバック
# した場合は sandbox 許可パス /tmp/claude/claude-hooks/<session>/ に振り替える。
# statusline.py はこのパスも読み取り候補に含む。
case "$status_file" in
  /tmp/claude-hooks/*|/private/tmp/claude-hooks/*)
    fallback_dir="/tmp/claude/claude-hooks/${session}"
    mkdir -p "$fallback_dir"
    status_file="${fallback_dir}/flow-status.json"
    ;;
esac

cat > "$status_file" <<JSON
{"current_phase":"${phase_num}","phase_name":"${phase_name}","current_step":${current_step},"total_steps":${total_steps},"step_name":"${step_name}"}
JSON

# --- Phase sequence validation ---
progress_file="$(find_progress_file)"
[ -z "$progress_file" ] && exit 0
[ ! -f "$progress_file" ] && exit 0

route=$(jq -r '.route // empty' "$progress_file" 2>/dev/null)
[ -z "$route" ] && exit 0

stored_phase=$(jq -r '.current_phase // empty' "$progress_file" 2>/dev/null)

# Same phase — no validation needed
[ "$phase_num" = "$stored_phase" ] && exit 0

# Phase changed — mark previous phase as complete
tmp="${progress_file}.tmp"
jq --arg p "$stored_phase" \
  'if (.phases_completed | map(tostring) | index($p)) then . else .phases_completed += [$p] end' \
  "$progress_file" > "$tmp" && mv "$tmp" "$progress_file"

# Get required sequence
required_order=$(route_sequence "$route")
[ -z "$required_order" ] && exit 0

# Find prerequisites for the new phase
prerequisites=""
for p in $required_order; do
  [ "$p" = "$phase_num" ] && break
  prerequisites="$prerequisites $p"
done

# Validate prerequisites
missing=""
for prereq in $prerequisites; do
  if ! jq -e --arg p "$prereq" '.phases_completed | map(tostring) | index($p)' "$progress_file" > /dev/null 2>&1; then
    missing="$missing $prereq"
  fi
done

if [ -n "$missing" ]; then
  echo "ERROR: Phase $phase_num を開始するには以下の Phase が完了している必要があります:$missing" >&2
  echo "現在の phases_completed: $(jq -r '.phases_completed | join(", ")' "$progress_file" 2>/dev/null)" >&2
  echo "ルート: $route" >&2
  exit 1
fi

# Update current_phase
jq --arg p "$phase_num" '.current_phase = $p' "$progress_file" > "$tmp" && mv "$tmp" "$progress_file"

exit 0
