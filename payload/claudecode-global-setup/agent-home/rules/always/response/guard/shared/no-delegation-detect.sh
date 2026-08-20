#!/usr/bin/env bash
# Detects "CLI / 内蔵ツール以外の操作をユーザーへ依頼する" patterns.
# Usage: lib/no-delegation-detect.sh <file>   OR   echo "text" | lib/no-delegation-detect.sh
# Stdout: matching lines. Exit: 0=clean, 1=detected, 2=usage error (file unreadable).
# 依頼形（〜してください/してもらう/お願い）に限定。語の出現だけでは検出しない。
set -u

PATTERN='実行してください|実行して下さい|打ってください|打って下さい|コピペ|貼り付け|お手元で|手元で[^。]*(実行|試|確認|打|叩)|自分で(実行|やって|叩いて)|ターミナルで[^。]*(実行|確認|打|叩)|`! |(Dashboard|ダッシュボード|管理画面|コンソール|設定画面|ブラウザ|web ?UI)[^。]*(設定|編集|変更|入力|追加|作成|登録|有効化|無効化|オン|オフ|切り替え|切替)[^。]*(してください|して下さい|してもら|お願い)|(ログイン|サインイン|認証|ログオン|OAuth|web[[:space:]]*認証|ブラウザ認証)[^。]*(してください|して下さい|してもら|お願い)|URL[^。]*(開いて|踏んで|アクセスして)|gh auth login|npm login|docker login|gcloud auth login|aws configure|ssh-keygen|vercel login|supabase login|render login|heroku login'

if [ "$#" -ge 1 ]; then
  FILE="$1"
  [ -r "$FILE" ] || exit 2
  matches=$(grep -nE "$PATTERN" "$FILE" 2>/dev/null || true)
else
  matches=$(grep -nE "$PATTERN" 2>/dev/null || true)
fi

[ -z "$matches" ] && exit 0
printf '%s\n' "$matches"
exit 1
