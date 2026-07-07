#!/usr/bin/env bash
# PreToolUse(Bash) — payload/ が正本（~/agent-home・~/.claude）と乖離した状態での
# git commit を block する。乖離検知は scripts/sync-payload.mjs --check に委譲する。
# staged に payload/ 配下のファイルがある場合は、その payload/<name> prefix に対応する
# mapping だけを --only で検査する（無関係な mapping の乖離に巻き込まれない）。
# staged に payload/ 配下がなければ従来どおり全 mapping を検査する。
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

# 検査スコープの決定: staged の payload/<name> prefix ごとに --only 検査。
# staged に payload/ 配下がなければ空 prefix 1 件（= 全 mapping 検査）とする。
staged=$(git -C "$cwd" diff --cached --name-only 2>/dev/null || true)
prefixes=$(printf '%s\n' "$staged" | grep '^payload/' | cut -d/ -f1-2 | sort -u || true)

run_check() {
  # $1: --only に渡す prefix（空なら全体検査）
  local drift_output status
  if [ -n "$1" ]; then
    drift_output=$(cd "$cwd" && node scripts/sync-payload.mjs --check --only "$1" 2>&1) && return 0
  else
    drift_output=$(cd "$cwd" && node scripts/sync-payload.mjs --check 2>&1) && return 0
  fi
  status=$?
  if [ "$status" -eq 1 ]; then
    {
      echo "[PAYLOAD-SYNC-BLOCK] payload が正本と乖離しています。node scripts/sync-payload.mjs --apply${1:+ --only $1} で同期してから commit してください。"
      echo "$drift_output"
    } >&2
    exit 2
  fi
  # node 実行エラー等（status が 1 以外）は fail-safe で block しない
  return 0
}

if [ -n "$prefixes" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] && run_check "$p"
  done <<EOF
$prefixes
EOF
else
  run_check ""
fi

exit 0
