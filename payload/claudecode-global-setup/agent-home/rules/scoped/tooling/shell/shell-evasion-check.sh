#!/usr/bin/env bash
# PostToolUse(Write|Edit|MultiEdit) hook: detect attempts to bypass the
# "scripts must be .sh" rule by embedding long shell logic in Makefile,
# package.json scripts, justfile, or Taskfile.
#
# Heuristics (net-new only — pre-existing violations in HEAD are ignored):
#   - Lines with 3+ "&&" chains
#   - Lines longer than 200 characters
# For package.json, scripts.* values are parsed with jq instead of raw lines.
#
# Does NOT exit 2 — warning only. Next turn must refactor into a .sh (with
# ADR via ask-permission flow) or simplify the logic.

set -euo pipefail

input="$(cat)"
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file" ] && exit 0
[ ! -f "$file" ] && exit 0

base=$(basename "$file")
case "$base" in
  Makefile|makefile|GNUmakefile|package.json|justfile|Justfile|Taskfile.yaml|Taskfile.yml) ;;
  *) exit 0 ;;
esac

# Skip vendored copies
case "$file" in
  */node_modules/*) exit 0 ;;
esac

count_long_lines() {
  awk 'length > 200 {n++} END {print n+0}' <<<"$1"
}
count_chain_lines() {
  printf '%s\n' "$1" | grep -cE '&&[^&]+&&[^&]+&&' 2>/dev/null || true
}
count_long_scripts() {
  jq -r '.scripts // {} | to_entries[] | select((.value | type) == "string" and (.value | length) > 200) | .key' <<<"$1" 2>/dev/null | grep -c . 2>/dev/null || true
}
count_chain_scripts() {
  jq -r '.scripts // {} | to_entries[] | select((.value | type) == "string" and (.value | test("&&[^&]+&&[^&]+&&"))) | .key' <<<"$1" 2>/dev/null | grep -c . 2>/dev/null || true
}

current=$(cat "$file" 2>/dev/null || true)

# Net-new comparison against HEAD if file is tracked
prev=""
file_dir=$(dirname "$file")
repo_root=$(cd "$file_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$repo_root" ]; then
  rel_path="${file#$repo_root/}"
  prev=$(git -C "$repo_root" show "HEAD:$rel_path" 2>/dev/null || true)
fi

issues=""

if [ "$base" = "package.json" ]; then
  cur_long=$(count_long_scripts "$current")
  cur_chain=$(count_chain_scripts "$current")
  if [ -n "$prev" ]; then
    prev_long=$(count_long_scripts "$prev")
    prev_chain=$(count_chain_scripts "$prev")
  else
    prev_long=0; prev_chain=0
  fi
  net_long=$(( cur_long - prev_long ))
  net_chain=$(( cur_chain - prev_chain ))
  [ "$net_long" -gt 0 ] && issues+="- scripts に長大シェル文字列 (>200 文字) が新規追加: ${net_long} 件
"
  [ "$net_chain" -gt 0 ] && issues+="- scripts に 3 連以上の && チェインが新規追加: ${net_chain} 件
"
else
  cur_long=$(count_long_lines "$current")
  cur_chain=$(count_chain_lines "$current")
  if [ -n "$prev" ]; then
    prev_long=$(count_long_lines "$prev")
    prev_chain=$(count_chain_lines "$prev")
  else
    prev_long=0; prev_chain=0
  fi
  net_long=$(( cur_long - prev_long ))
  net_chain=$(( cur_chain - prev_chain ))
  [ "$net_long" -gt 0 ] && issues+="- 200 文字超の行が新規追加: ${net_long} 行
"
  [ "$net_chain" -gt 0 ] && issues+="- 3 連以上の && チェインが新規追加: ${net_chain} 行
"
fi

[ -z "$issues" ] && exit 0

ctx="[SHELL-EVASION-DETECTED]
file=$file

検出:
${issues}
~/.claude/rules/scoped/tooling/shell/rule.md は、シェルスクリプト禁止 (.sh 以外) を回避する目的で Makefile / package.json scripts / justfile / Taskfile に長大シェルを埋め込む行為を禁止しています。

対応の選択肢:
1. 該当ロジックを独立した .sh ファイルへ切り出す (permissions.ask 経由でユーザー承認 + ADR 必須)
2. ロジック自体を簡素化する (複数 && を別ターゲット / 別 script エントリに分割)

既存資産を編集しただけで誤検出した可能性があるなら、git diff HEAD -- '${file}' で差分を確認し、本ターンの追加が本当に閾値を超えているか自分で再判定してください。net-new 0 で誤発火している場合は本警告を無視して構いません。"

jq -n --arg ctx "$ctx" --arg msg "[フック発火] シェル脱法検出: $base" \
  '{"systemMessage":$msg,"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$ctx}}'
exit 0
