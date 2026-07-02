#!/usr/bin/env bash
# managing-agent-configs の hook スクリプトが共有するマーカー配置ヘルパー。
# worktree（.git がファイル）なら worktree 内 .claude/markers/<session>/ に、
# それ以外は ${TMPDIR:-/tmp}/claude-hooks/<session>/ に配置する。

marker_path() {
  local cwd="$1" session="$2" name="$3"
  local dir=""

  if [ -f "$cwd/.git" ]; then
    local wt_root
    wt_root=$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
    [ -n "$wt_root" ] && dir="$wt_root/.claude/markers/$session"
  fi

  [ -z "$dir" ] && dir="${TMPDIR:-/tmp}/claude-hooks/$session"

  mkdir -p "$dir"
  printf '%s/%s' "$dir" "$name"
}
