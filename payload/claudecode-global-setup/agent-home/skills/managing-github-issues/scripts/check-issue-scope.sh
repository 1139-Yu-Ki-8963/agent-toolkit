#!/usr/bin/env bash
# PreToolUse(Bash) hook: git add -A / git add . / git add :/ をブロック。
# 別セッションの修正コミットや無関係な変更を巻き込む事故を防ぐ。
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$cmd" ]; then exit 0; fi

# cmd を ; | && || && で分割して各サブコマンドを評価する。
# 引用符内の文字列（コミットメッセージ等）にマッチする誤検出を避けるため、
# 各サブコマンドの先頭 3 トークンのみを検査する。
matched=0
IFS=';|&' read -ra subcmds <<< "$cmd"
for sub in "${subcmds[@]}"; do
  trimmed=$(printf '%s' "$sub" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  [ -z "$trimmed" ] && continue
  read -r tok1 tok2 tok3 _ <<< "$trimmed"
  [ "$tok1" = "git" ] || continue
  [ "$tok2" = "add" ] || continue
  case "$tok3" in
    -A|-a|--all|.|:/|\*) matched=1; break ;;
  esac
done

if [ $matched -eq 1 ]; then
  ctx="[ISSUE-SCOPE] 'git add -A' / 'git add .' / 'git add :/' / 'git add *' は禁止です。

理由: 別セッションの修正コミットや無関係な変更（seeds 他データ・.playwright-mcp/ 等）を巻き込む事故が発生した実績があります（PR #125 で実害）。

代わりに必要なファイルを 1 件ずつ列挙してください:
  git add backend/app/routers/<file>.py
  git add backend/tests/test_<file>.py
  git add docs_site/機能仕様/<N>_<name>.md

ステージング後は 'git diff --cached --name-only' で範囲を確認し、無関係パスがあれば 'git restore --staged <PATH>' で除外してから commit してください。"

  jq -n --arg ctx "$ctx" '{
    "decision": "block",
    "systemMessage": "[フック発火] ISSUE-SCOPE: 一括 add をブロック",
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "additionalContext": $ctx
    }
  }'
fi
exit 0

