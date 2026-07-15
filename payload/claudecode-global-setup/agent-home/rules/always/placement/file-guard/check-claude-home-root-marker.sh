#!/usr/bin/env bash
# check-claude-home-root-marker.sh - PreToolUse(Bash) hook
#
# 役割: `touch "$HOME/.claude/.<word>"` や `> "$HOME/.claude/.<word>"` のように
#       ルート直下のドットファイルを生成しようとするコマンドを exit 2 でブロックする。
# 仕様: ~/.claude/rules/always/placement/file-guard/rule.md
#
# 例外（block しない）:
#   - ${TMPDIR:-/tmp}/claude-hooks/** へのアクセス
#   - <repo>/.claude/markers/** へのアクセス
#   - $HOME/.claude/cache/** へのアクセス
#   - /tmp/.allow-* へのアクセス
#   - $HOME/.claude/.last-cleanup、$HOME/.claude/.last-update-result.json
#   - $HOME/.claude/.gitignore、$HOME/.claude/.gcs-sha
#
# 自動解除: 同一セッション 3 回連続 block で自動解除（livelock 防止）。

set +e

. "$HOME/.claude/rules/scoped/agent-config/hooks/shared/transcript-query.sh"

input=""
if [ ! -t 0 ]; then
  input="$(cat 2>/dev/null || true)"
fi

cmd="$(printf '%s' "$input" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/^"command"[[:space:]]*:[[:space:]]*"//; s/"$//')"
[ -z "$cmd" ] && exit 0

# 検出パターン: $HOME/.claude/.<word>... を touch / > / printf 等で作成しようとする
candidates="$(printf '%s\n' "$cmd" | grep -oE "(${HOME}|\\\$HOME|~|\${HOME})/\.claude/\.[A-Za-z0-9_-]+[A-Za-z0-9_.-]*" 2>/dev/null)"

[ -z "$candidates" ] && exit 0

# 例外判定
violation=""
while IFS= read -r path; do
  [ -z "$path" ] && continue
  basename_path="${path##*/.claude/}"

  case "$basename_path" in
    .last-cleanup|.last-update-result.json|.gitignore|.gcs-sha)
      continue
      ;;
    .auto-ship-active-*|.flow-select-required-*|.flow-select-enforce-*|.allow-direct-edit|.allow-main-edit|.allow-playwright-main)
      # parallel-dev-worktree / auto-ship / flow-selector で既に明文化済みの hook 互換マーカー。
      # 今後 markers/ 配下へ移行するまでの一時例外。
      continue
      ;;
  esac

  case "$path" in
    */cache/*)
      continue
      ;;
  esac

  violation="$path"
  break
done <<EOF
$candidates
EOF

[ -z "$violation" ] && exit 0

# livelock 自動解除
tp="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
should_auto_release "$tp" "CLAUDE-HOME-ROOT-MARKER-BLOCK" 3 && exit 0

cat >&2 <<MSG
[CLAUDE-HOME-ROOT-MARKER-BLOCK] ~/.claude/ ルート直下への新規ドットファイル書き込みは禁止されています。
  検出パス: ${violation}
  正しい書き出し先:
    - hook の状態マーカー: \${TMPDIR:-/tmp}/claude-hooks/\${session}/<name>
                            または \${worktree_root}/.claude/markers/\${session}/<name>
    - ワンショット例外: /tmp/.allow-<name>
  ルール詳細: ~/.claude/rules/always/placement/file-guard/rule.md
MSG

exit 2
