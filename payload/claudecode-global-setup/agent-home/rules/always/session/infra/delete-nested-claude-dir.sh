#!/bin/bash
# delete-nested-claude-dir.sh
# ~/.claude/.claude が発生したら即削除する物理ガード。
#
# 背景: Claude Code 本体は cwd=$HOME/.claude で起動されると
# project-scope settings の保存先を ${cwd}/.claude/settings.local.json
# と決定し、~/.claude/.claude/settings.local.json を勝手に作る。
# 設定や CLI フラグで保存先を変える公式機能は存在しない（仕様確認済み）。
#
# 本 hook を SessionStart / Stop / PostToolUse(*) に登録することで、
# Claude Code が裏で作っても次のツール呼び出し or ターン終了時に
# 物理削除する。発生 → 自動削除 → 次回発生 → 自動削除 のループで
# 実用上「ほぼ常に存在しない」状態を維持する。
#
# 例外として cache/self-project や別目的の隔離 symlink は touch しない。
# 対象は厳密に ~/.claude/.claude のみ。

set -u

target="$HOME/.claude/.claude"

# 存在しなければ早期 exit（symlink の dangling は -e で false なので -L 併用）
if [ ! -e "$target" ] && [ ! -L "$target" ]; then
  exit 0
fi

# symlink（dangling 含む）は実体を辿らず name だけ削除
if [ -L "$target" ]; then
  rm "$target" 2>/dev/null
  exit 0
fi

# directory: 中身ごと削除（read-only 化されていれば chmod で戻す）
if [ -d "$target" ]; then
  chmod -R u+rwx "$target" 2>/dev/null
  rm -rf "$target" 2>/dev/null
  exit 0
fi

# regular file: 単純削除
if [ -f "$target" ]; then
  rm -f "$target" 2>/dev/null
  exit 0
fi

exit 0
