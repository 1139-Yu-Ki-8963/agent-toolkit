#!/usr/bin/env bash
# git commit / git push 直前に author name と email を検証し、
# 白リスト (1139-Yu-Ki-8963 / 63326271+1139-Yu-Ki-8963@users.noreply.github.com) 以外は exit 2 で block する。
# ~/.claude/rules/always/naming/commit-branch/rule.md（コミット・ブランチ命名規約）の一部として動作する。

set -u

ALLOW_NAME='^1139-Yu-Ki-8963$'
ALLOW_EMAIL='^63326271\+1139-Yu-Ki-8963@users\.noreply\.github\.com$'

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"
hook_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$hook_cwd" ] && hook_cwd="$PWD"

resolve_git_ctx_dir "$cmd" "$CMD_CTX_GIT_COMMIT_RE" "$hook_cwd"
COMMIT_TARGET_DIR="$RGCD_CTX_DIR"
HAS_COMMIT=$([ -n "$RGCD_MATCHED_SEG" ] && echo y || echo n)
resolve_git_ctx_dir "$cmd" "$CMD_CTX_GIT_PUSH_RE" "$hook_cwd"
PUSH_TARGET_DIR="$RGCD_CTX_DIR"
HAS_PUSH=$([ -n "$RGCD_MATCHED_SEG" ] && echo y || echo n)

emit_block() {
  local label="$1" ctx="$2"
  jq -n --arg label "$label" --arg ctx "$ctx" \
    '{"systemMessage": ("[フック発火] " + $label),"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

if [ "$HAS_COMMIT" = "y" ]; then
  # -c user.email=... / -c user.name=... ワンショット指定の値を抽出
  explicit_email=$(printf '%s' "$cmd" | sed -nE "s/.*-c[[:space:]]+user\\.email=['\"]?([^ '\"]+)['\"]?.*/\\1/p" | head -1)
  explicit_name=$(printf '%s' "$cmd" | sed -nE "s/.*-c[[:space:]]+user\\.name=['\"]?([^ '\"]+)['\"]?.*/\\1/p" | head -1)

  if [ -n "$explicit_email" ] && ! printf '%s' "$explicit_email" | grep -qE "$ALLOW_EMAIL"; then
    emit_block "GIT-AUTHOR-BLOCK: 禁止 email を明示指定" \
      "[GIT-AUTHOR-BLOCK] -c user.email='$explicit_email' は白リスト ($ALLOW_EMAIL) に不一致。対処: 63326271+1139-Yu-Ki-8963@users.noreply.github.com 以外は使用禁止。~/.claude/rules/always/naming/commit-branch/rule.md"
  fi
  if [ -n "$explicit_name" ] && ! printf '%s' "$explicit_name" | grep -qE "$ALLOW_NAME"; then
    emit_block "GIT-AUTHOR-BLOCK: 禁止 name を明示指定" \
      "[GIT-AUTHOR-BLOCK] -c user.name='$explicit_name' は白リスト ($ALLOW_NAME) に不一致。対処: 1139-Yu-Ki-8963 以外は使用禁止。~/.claude/rules/always/naming/commit-branch/rule.md"
  fi

  # 明示指定が無い場合は effective ident を検査
  if [ -z "$explicit_email" ] || [ -z "$explicit_name" ]; then
    # env -u で GIT_AUTHOR_* / GIT_COMMITTER_* を除外してから git var を呼ぶことで、
    # 親プロセスから継承された空文字列 env による誤検知を防ぐ。
    eff_ident=$(env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL git -C "$COMMIT_TARGET_DIR" var GIT_AUTHOR_IDENT 2>/dev/null || true)
    eff_name=$(printf '%s' "$eff_ident" | sed -nE 's/^(.*) <[^>]+> .*/\1/p')
    eff_email=$(printf '%s' "$eff_ident" | sed -nE 's/.*<([^>]+)>.*/\1/p')
    if [ -z "$explicit_name" ] && [ -n "$eff_name" ] && ! printf '%s' "$eff_name" | grep -qE "$ALLOW_NAME"; then
      emit_block "GIT-AUTHOR-BLOCK: 実効 name 不一致" \
        "[GIT-AUTHOR-BLOCK] 実効 author name '$eff_name' は白リスト ($ALLOW_NAME) に不一致。対処: ~/.gitconfig の user.name を 1139-Yu-Ki-8963 に直す or 他経路 (env / local config) を除去。~/.claude/rules/always/naming/commit-branch/rule.md"
    fi
    if [ -z "$explicit_email" ] && [ -n "$eff_email" ] && ! printf '%s' "$eff_email" | grep -qE "$ALLOW_EMAIL"; then
      emit_block "GIT-AUTHOR-BLOCK: 実効 email 不一致" \
        "[GIT-AUTHOR-BLOCK] 実効 author email '$eff_email' は白リスト ($ALLOW_EMAIL) に不一致。対処: ~/.gitconfig の user.email を 63326271+1139-Yu-Ki-8963@users.noreply.github.com に直す or 他経路 (env / local config) を除去。~/.claude/rules/always/naming/commit-branch/rule.md"
    fi
    if [ -z "$eff_email" ]; then
      emit_block "GIT-AUTHOR-BLOCK: author email が空" \
        "[GIT-AUTHOR-BLOCK] author email が空。対処: git config --global user.email 63326271+1139-Yu-Ki-8963@users.noreply.github.com を設定する。~/.claude/rules/always/naming/commit-branch/rule.md"
    fi
  fi
fi

if [ "$HAS_PUSH" = "y" ]; then
  # 統合先（origin/HEAD = 通常 origin/main）とのマージベース以降だけ検査する。
  # tracking branch (@{u}) ベースだと rebase で取り込んだ upstream コミットまで
  # 「新規 push 範囲」として誤検出するため。
  integ=$(git -C "$PUSH_TARGET_DIR" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@' || echo "origin/main")
  base=$(git -C "$PUSH_TARGET_DIR" merge-base HEAD "$integ" 2>/dev/null || git -C "$PUSH_TARGET_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo "$integ")
  range="${base}..HEAD"
  # awk -v は値内の \+ \. を消費し正規表現を壊す（リテラル + を含む email を誤判定する）。
  # スクリプト他所と同じ grep -qE で name/email を個別検査する。
  bad=$(git -C "$PUSH_TARGET_DIR" log --format='%H|%an|%ae|%s' "$range" 2>/dev/null \
        | while IFS='|' read -r _h _n _e _s; do
            if ! printf '%s' "$_n" | grep -qE "$ALLOW_NAME" || ! printf '%s' "$_e" | grep -qE "$ALLOW_EMAIL"; then
              printf '%s|%s|%s|%s\n' "$_h" "$_n" "$_e" "$_s"
            fi
          done \
        | head -5 || true)
  if [ -n "$bad" ]; then
    ctx=$(printf '[GIT-AUTHOR-PUSH-BLOCK] push 範囲 (%s) に白リスト外の author を含むコミットを検出:\n%s\n白リスト: name=%s email=%s\n対処: git rebase <親> --exec "git commit --amend --reset-author --no-edit" で書き換えてから再 push する。~/.claude/rules/always/naming/commit-branch/rule.md' "$range" "$bad" "$ALLOW_NAME" "$ALLOW_EMAIL")
    jq -n --arg ctx "$ctx" '{"systemMessage":"[フック発火] GIT-AUTHOR-PUSH-BLOCK: push を中断","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
    printf '%s\n' "$ctx" >&2
    exit 2
  fi
fi

exit 0
