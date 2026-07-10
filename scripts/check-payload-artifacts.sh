#!/usr/bin/env bash
# PreToolUse(Bash) — payload/ に配布してはいけない実行時生成物（flow-context.yml 等）が
# 残存した状態での git commit を block する。判定は sync-payload.mjs --check-artifacts に委譲する。
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
[ "${CLAUDE_PAYLOAD_ARTIFACTS_SKIP:-}" = "1" ] && exit 0

# node が使えない場合は fail-safe で block しない
command -v node >/dev/null 2>&1 || exit 0

output=$(cd "$cwd" && node scripts/sync-payload.mjs --check-artifacts 2>&1) && exit 0
status=$?

if [ "$status" -eq 1 ]; then
  {
    echo "[PAYLOAD-ARTIFACTS-BLOCK] payload/ に配布してはいけない実行時生成物が含まれています。"
    echo "$output"
  } >&2
  exit 2
fi

# node 実行エラー等（status が 1 以外）は fail-safe で block しない
exit 0
