#!/usr/bin/env bash
# cleanup-session-markers.sh - SessionEnd hook
#
# 役割: セッション終了時に、当該 session_id 配下のマーカー集約ディレクトリを掃除する。
# 仕様: ~/.claude/rules/always/placement/file-guard/rule.md
#
# 対象:
#   - 揮発（必須）: ${TMPDIR:-/tmp}/claude-hooks/${session}
#   - worktree 内（cwd 判定して worktree なら）: ${worktree_root}/.claude/markers/${session}
#
# session ID 取得優先順位:
#   1. CLAUDE_SESSION_ID 環境変数（旧称・互換用）
#   2. CLAUDE_CODE_SESSION_ID 環境変数（harness が実際にセットする変数名）
#   3. stdin JSON の session_id フィールド（上記どちらも空の場合のフォールバック）
#
# fail-open: 失敗してもセッション終了をブロックしない。常に exit 0。

set +e

input=""
if [ ! -t 0 ]; then
  input="$(cat 2>/dev/null || true)"
fi

session="${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
if [ -z "$session" ]; then
  session="$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi

[ -z "$session" ] && exit 0

tmp_dir="${TMPDIR:-/tmp}/claude-hooks/${session}"
if [ -d "$tmp_dir" ]; then
  rm -rf -- "$tmp_dir" 2>/dev/null || true
fi

cwd="$(printf '%s' "$input" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
[ -z "$cwd" ] && cwd="$PWD"

if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$repo_root" ] && [ -f "${repo_root}/.git" ]; then
    # cwd は worktree。当該セッションの worktree 内マーカーを掃除
    wt_marker="${repo_root}/.claude/markers/${session}"
    [ -d "$wt_marker" ] && rm -rf -- "$wt_marker" 2>/dev/null || true
  fi
fi

# Playwright MCP 集約ディレクトリ: 2 日以上経過したファイルを削除（ディレクトリ自体は残置）
mcp_playwright_dir="$HOME/agent-home/tools/MCP/playwright"
if [ -d "$mcp_playwright_dir" ]; then
  find "$mcp_playwright_dir" -mindepth 1 -mtime +2 -delete 2>/dev/null || true
fi

exit 0
