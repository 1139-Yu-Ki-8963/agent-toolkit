#!/usr/bin/env bash
# marker-path.sh - hook 用マーカーパス解決ヘルパー
#
# 仕様: ~/.claude/rules/always/placement/file-guard/rule.md
#
# 使い方:
#   . "$HOME/agent-home/tools/hooks/lib/marker-path.sh"
#   cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
#   [ -z "$cwd" ] && cwd="$PWD"
#   counter="$(marker_path "$cwd" "$session" pr-progress-gate.count)"
#
# 書き出し先決定ロジック:
#   - cwd が worktree（.git がファイル）→ ${worktree_root}/.claude/markers/${session}/<name>
#   - それ以外（メインツリー、git 管理外、cwd 不明）→ ${TMPDIR:-/tmp}/claude-hooks/${session}/<name>
#
# 親ディレクトリは mkdir -p で自動生成する。
# main ブランチへの持ち込み禁止は (1) .gitignore で `.claude/markers/` 除外、
# (2) cwd 判定で main ツリーは /tmp フォールバック、(3) 任意の pre-commit guard、
# の三重保証で実現される。

# cwd が worktree なら worktree ルートを echo する。worktree でなければ非ゼロを返す。
_marker_worktree_root() {
  local cwd="$1"
  [ -z "$cwd" ] && return 1
  [ ! -d "$cwd" ] && return 1
  local root
  root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -z "$root" ] && return 1
  # worktree は .git がファイル、メインツリーは .git がディレクトリ
  [ -f "${root}/.git" ] || return 1
  printf '%s' "$root"
}

marker_path() {
  local cwd="${1:-$PWD}"
  local session="${2:-default}"
  local name="${3:-marker}"
  local wt dir
  if wt="$(_marker_worktree_root "$cwd")"; then
    dir="${wt}/.claude/markers/${session}"
  else
    dir="${TMPDIR:-/tmp}/claude-hooks/${session}"
  fi
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s/%s' "$dir" "$name"
}

# managed_asset_type - パス（相対/絶対どちらでも）を受け取り managing-agent-configs の
# 種別名（skills/rules/routines/hooks）を echo する。非該当は空文字を echo する。
#
# 監視パスの正本はここ。~/.claude/rules/always/gate/managing-review-gate/rule.md の
# 対応表と乖離した場合は本関数を正とする。
#
# `*` が `/` にもマッチする sh case の性質を利用し、絶対パス対応のため
# `パターン|*/パターン` の両建てで記述する（意図した挙動）。
managed_asset_type() {
  local f="$1"
  case "$f" in
    skills/*/SKILL.md|*/skills/*/SKILL.md)
      printf 'skills' ;;
    skills/*/scripts/*.sh|*/skills/*/scripts/*.sh)
      printf 'skills' ;;
    skills/*/references/*|*/skills/*/references/*)
      printf 'skills' ;;
    .claude/rules/*/rule.md|*/.claude/rules/*/rule.md)
      printf 'rules' ;;
    .claude/rules/*/*.sh|*/.claude/rules/*/*.sh)
      printf 'rules' ;;
    .claude/rules/*/prh.yml|*/.claude/rules/*/prh.yml)
      printf 'rules' ;;
    rules/*/prh.yml|*/rules/*/prh.yml)
      printf 'rules' ;;
    routines/*/ルーティン設計書.md|*/routines/*/ルーティン設計書.md)
      printf 'routines' ;;
    tools/hooks/*.sh|*/tools/hooks/*.sh)
      printf 'hooks' ;;
    *)
      printf '' ;;
  esac
}
