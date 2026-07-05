#!/usr/bin/env bash
# PreToolUse(Bash) — payload/ が正本（~/agent-home・~/.claude）と乖離した状態での
# git commit を block する。乖離検知は scripts/sync-payload.mjs --check に委譲する。
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

case "$cmd" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$cwd" ] && cwd="$PWD"

# このリポジトリでなければ対象外
[ -f "$cwd/scripts/sync-payload.mjs" ] || exit 0

# 緊急口
[ "${CLAUDE_PAYLOAD_SYNC_SKIP:-}" = "1" ] && exit 0

# 新PC・clone直後の fail-safe（正本が存在しない環境では検査不能）
[ -d "$HOME/agent-home" ] || exit 0

# node が使えない場合は fail-safe で block しない
command -v node >/dev/null 2>&1 || exit 0

drift_output=$(cd "$cwd" && node scripts/sync-payload.mjs --check 2>&1) || {
  status=$?
  if [ "$status" -eq 1 ]; then
    {
      echo "[PAYLOAD-SYNC-BLOCK] payload が正本と乖離しています。node scripts/sync-payload.mjs --apply で同期してから commit してください。"
      echo "$drift_output"
    } >&2
    exit 2
  fi
  # node 実行エラー等（status が 1 以外）は fail-safe で block しない
  exit 0
}

exit 0
