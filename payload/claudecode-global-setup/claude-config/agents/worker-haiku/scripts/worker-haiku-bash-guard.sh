#!/usr/bin/env bash
# PreToolUse(Bash) hook.
# worker-haiku サブエージェントのファイル変更コマンドを exit 2 で block する。
# 背景: worker-haiku は実行専用（tools: Bash, Read）だが、Bash 経由の
#       ファイル作成・編集（echo > file, touch, mkdir 等）はツール制限では
#       防げない。プロンプトの禁止事項だけでは haiku の遵守が不安定なことが
#       実機検証で確認されたため、hook で機械強制する。
# 判定: 入力 JSON の agent_type が "worker-haiku" の場合のみ検査。
#       それ以外（メイン・他エージェント・フィールド不在）は素通り。
# 例外: git コマンドで始まるセグメントは許可（git 定型操作は haiku の担当。
#       git commit 等が内部でファイルを変更するのは設計上許容）。
# fail-safe: jq 不在・コマンド抽出失敗は exit 0 で素通り。
set -u

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)

agent_type=$(printf '%s' "$input" | jq -r '.agent_type // empty' 2>/dev/null)
[ "$agent_type" = "worker-haiku" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

block() {
  {
    echo "[HAIKU-FILE-GUARD-BLOCK] worker-haiku はファイル変更コマンドを実行できない（検出: $1）。"
    echo "ファイルの作成・編集・削除は worker-sonnet に委任すること。"
    echo "worker-haiku に渡してよいのはテスト・ビルド・lint 実行、git 定型操作、既存スクリプトの起動のみ。"
  } >&2
  exit 2
}

# --- 検査 1: リダイレクトによるファイル書き込み ---
# 2>&1 等の fd 複製と /dev/null 宛てを除去した後に > が残れば block
scrubbed=$(printf '%s' "$cmd" | sed -E 's/[0-9]*>&[0-9]+//g; s/[0-9]*>>?[[:space:]]*\/dev\/null//g')
if printf '%s' "$scrubbed" | grep -q '>'; then
  block "リダイレクト"
fi

# --- 検査 2: 変更系コマンド ---
# && / || / ; / | でセグメント分割し、git で始まるセグメントは除外して検査
segments=$(printf '%s' "$cmd" | awk '{ gsub(/&&|\|\||;|\|/, "\n"); print }' | sed -E 's/^[[:space:]]+//')
filtered=$(printf '%s\n' "$segments" | grep -v -E '^git([[:space:]]|$)' || true)

if printf '%s\n' "$filtered" | grep -Eq '(^|[[:space:]])(tee|touch|mkdir|mv|cp|rm|rmdir|truncate|ln|chmod|chown|dd|install)([[:space:]]|$)'; then
  block "変更系コマンド"
fi
if printf '%s\n' "$filtered" | grep -Eq '(^|[[:space:]])(sed|perl)[[:space:]][^\n]*-i'; then
  block "in-place 編集"
fi

exit 0
