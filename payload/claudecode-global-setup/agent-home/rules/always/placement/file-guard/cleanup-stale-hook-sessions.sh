#!/bin/bash
# cleanup-stale-hook-sessions.sh
# Claude Code の `posix_spawn '/bin/sh' ENOENT` を防ぐ stale cwd 掃除。
# 真因は Node.js の child_process.spawn が cwd オプションに渡された
# ディレクトリが存在しないと ENOENT を返すが、エラーメッセージは
# 起動ファイル（/bin/sh）を指してしまうという既知挙動。
# SessionStart hook から fire-and-forget で起動される（前景処理は 100ms 以内目標）。

set -u

# Fail-open: 何が起きても新セッションをブロックしない
trap 'exit 0' ERR

LOCK="/tmp/cleanup-stale-hook-sessions.lock"
mkdir "$LOCK" 2>/dev/null || exit 0  # 二重起動防止

cleanup() {
  rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT

# ---- 1. Superset app-state.json の panes[*].cwd を null 化 ----
APPSTATE="$HOME/.superset/app-state.json"
if [ -f "$APPSTATE" ] && command -v jq >/dev/null 2>&1; then
  stale_paths=$(jq -r '.tabsState.panes | to_entries[] | select(.value.cwd != null) | .value.cwd' "$APPSTATE" 2>/dev/null \
    | sort -u | while read -r p; do [ -n "$p" ] && [ ! -d "$p" ] && echo "$p"; done)

  if [ -n "$stale_paths" ]; then
    ts=$(date +%Y%m%d-%H%M%S)
    cp "$APPSTATE" "$APPSTATE.bak.$ts" 2>/dev/null
    tmp=$(mktemp)
    jq --argjson stale "$(printf '%s\n' "$stale_paths" | jq -R . | jq -s .)" '
      .tabsState.panes |= with_entries(
        if (.value.cwd != null and (.value.cwd as $c | $stale | index($c)))
        then .value.cwd = null | .value.cwdConfirmed = false
        else . end
      )' "$APPSTATE" > "$tmp" 2>/dev/null && mv "$tmp" "$APPSTATE" || rm -f "$tmp"
  fi
fi

# ---- 2. subagent jsonl のうち末尾 cwd が消えているものを .stale 化 ----
# 30 日以内に変更された jsonl のみ対象（古いものは触らない）
find "$HOME/.claude/projects" -name '*.jsonl' -mtime -30 2>/dev/null | while read -r f; do
  c=$(tail -1 "$f" 2>/dev/null | jq -r '.cwd // empty' 2>/dev/null)
  if [ -n "$c" ] && [ ! -d "$c" ]; then
    mv "$f" "$f.stale" 2>/dev/null
  fi
done

# ---- 3. /tmp/claude-hooks/ の orphan セッション掃除（NO-ROOT-MARKER）----
# 7 日超アクセスが無いセッションディレクトリを削除。SessionEnd が動かなかった
# 場合の二重防御。ルール詳細: ~/.claude/rules/always/placement/file-guard/rule.md
hooks_tmp="${TMPDIR:-/tmp}/claude-hooks"
if [ -d "$hooks_tmp" ]; then
  find "$hooks_tmp" -mindepth 1 -maxdepth 1 -type d -mtime +7 \
    -exec rm -rf {} + 2>/dev/null || true
fi

exit 0
