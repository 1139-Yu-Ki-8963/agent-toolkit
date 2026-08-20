#!/usr/bin/env bash
# marker-path.sh - hook 用マーカーパス解決ヘルパー
#
# 仕様: ~/.claude/rules/always/placement/file-guard/rule.md
#
# 使い方:
#   . "$HOME/agent-home/tools/hooks/shared/marker-path.sh"
#   cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
#   [ -z "$cwd" ] && cwd="$PWD"
#   counter="$(marker_path "$cwd" "$session" pr-progress-gate.count)"
#
# 書き出し先決定ロジック:
#   - cwd が worktree（.git がファイル）→ ${worktree_root}/.claude/markers/${session}/<name>
#   - それ以外（メインツリー、git 管理外、cwd 不明）→ /tmp/claude-hooks/${session}/<name>
#
# 親ディレクトリは mkdir -p で自動生成する。
# main-branch への持ち込み禁止は (1) .gitignore で `.claude/markers/` 除外、
# (2) cwd 判定で main-tree は /tmp フォールバック、(3) 任意の pre-commit guard、
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
    dir="/tmp/claude-hooks/${session}"
  fi
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s/%s' "$dir" "$name"
}

# managed_asset_type - パス（相対/絶対どちらでも）を受け取り managing-agent-configs の
# 種別名（skills/rules/routines/hooks）を echo する。非該当は空文字を echo する。
#
# 監視パスの正本はここ。~/.claude/rules/always/agent-config/review/rule.md の
# 対応表と乖離した場合は本関数を正とする。
#
# `*` が `/` にもマッチする sh case の性質を利用し、絶対パス対応のため
# `パターン|*/パターン` の両建てで記述する（意図した挙動）。
managed_asset_type() {
  local f="$1"
  case "$f" in
    payload/*|*/payload/*)
      printf '' ;;
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
    rules/*/rule.md|*/rules/*/rule.md)
      printf 'rules' ;;
    rules/*/*.sh|*/rules/*/*.sh)
      printf 'rules' ;;
    routines/*/ルーティン設計書.md|*/routines/*/ルーティン設計書.md)
      printf 'routines' ;;
    tools/hooks/*.sh|*/tools/hooks/*.sh)
      printf 'hooks' ;;
    *)
      printf '' ;;
  esac
}

# escape_log_append - 緊急回避コマンド使用 / fail-closed 発火を永続 append-only ログに
# 記録する。marker_path の揮発カウンタ（セッション/worktree スコープの一時ファイル）とは
# 別物。各 hook はこの関数経由でのみ追記する（直書き禁止・フォーマット変更はここに集約）。
#
# 引数: session hook_name event(skip|fail-closed) tag [detail]
escape_log_append() {
  local session="${1:-default}" hook_name="${2:-unknown}" event="${3:-unknown}"
  local tag="${4:-}" detail="${5:-}"
  local dir="$HOME/agent-home/sessions/.escape-log"
  mkdir -p "$dir" 2>/dev/null || true
  jq -nc --arg ts "$(date -u +%FT%TZ)" --arg hook "$hook_name" --arg event "$event" \
    --arg tag "$tag" --arg detail "$detail" \
    '{ts:$ts,hook:$hook,event:$event,tag:$tag,detail:$detail}' \
    >> "$dir/${session}.jsonl" 2>/dev/null || true
}

# --- cmd-context: git系コマンドの実行コンテキスト解決 -----------------------
# 背景: hookスクリプトがgit/gh等のCLIをラップする際、コマンド文字列に
#   -C <dir> や cd <dir> && の形式で明示的にコンテキストが上書きされているのに、
#   hookプロセス自身のcwdに依存して動作してしまうバグが複数のhookで見つかった
#   （check-approved-sha-on-merge.sh, check-git-author-allowlist.sh,
#   dispatch-pre-bash-checks.sh）。本セクションはこの解決ロジックを一箇所に集約し、
#   marker-path.shを既にsourceしている/する各hookから共通利用する。

# split_cmd_segments <cmd> — &&/||/;/|/& で分割し1行1セグメントで出力
split_cmd_segments() {
  printf '%s' "$1" | awk '{
    gsub(/\r?\n/, ";");
    gsub(/&&/, "\n"); gsub(/\|\|/, "\n");
    gsub(/;/, "\n"); gsub(/\|/, "\n"); gsub(/&/, "\n");
    print
  }'
}

# git commit / git push を検出する共通正規表現（セグメント単位でのマッチを想定）
CMD_CTX_GIT_COMMIT_RE='^[[:space:]]*(command[[:space:]]+)?git([[:space:]]+(-C|-c)[[:space:]]*[^[:space:]]+|[[:space:]]+--?[[:alnum:]=/._-]+)*[[:space:]]+commit([[:space:]]|$)'
CMD_CTX_GIT_PUSH_RE='^[[:space:]]*(command[[:space:]]+)?git([[:space:]]+(-C|-c)[[:space:]]*[^[:space:]]+|[[:space:]]+--?[[:alnum:]=/._-]+)*[[:space:]]+push([[:space:]]|$)'

# _rgcd_expand_tilde <token> — 先頭が "~" / "~/..." のトークンのみ $HOME に展開して echo する。
# sed/$(...) 経由ではシェルのチルダ展開が起きないため、cd/-C 抽出直後に明示的に補う。
# "~user" 形式（他ユーザーのホーム）は非対応（hookの用途上不要）。
_rgcd_expand_tilde() {
  case "$1" in
    "~")    printf '%s' "$HOME" ;;
    "~/"*)  printf '%s' "$HOME${1#\~}" ;;
    *)      printf '%s' "$1" ;;
  esac
}

# resolve_git_ctx_dir <cmd> <target_regex> <hook_cwd>
# セグメントを順に走査し、target_regex にマッチする最初のセグメントを見つけるまでの
# 「cd <dir> &&」前置を蓄積し、マッチセグメント自身の「-C <dir>」があればそちらを優先する。
# 優先順位: -C明示 > cd前置 > 既定hook_cwd。
# 結果はグローバル変数 RGCD_MATCHED_SEG（マッチセグメント。空ならマッチなし）と
# RGCD_CTX_DIR（解決済み実効ディレクトリ。マッチなしでも hook_cwd を返す）に格納する。
resolve_git_ctx_dir() {
  local cmd="$1" pattern="$2" hook_cwd="$3"
  local seg cd_acc="" dir
  RGCD_MATCHED_SEG=""
  RGCD_CTX_DIR="$hook_cwd"
  while IFS= read -r seg; do
    dir=$(printf '%s' "$seg" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^[:space:]]+)[[:space:]]*$/\1/p')
    dir=$(_rgcd_expand_tilde "$dir")
    if [ -n "$dir" ]; then
      case "$dir" in
        /*) cd_acc="$dir" ;;
        *)  cd_acc="${cd_acc:+$cd_acc/}$dir" ;;
      esac
      continue
    fi
    if printf '%s' "$seg" | grep -qE "$pattern"; then
      RGCD_MATCHED_SEG="$seg"
      break
    fi
  done < <(split_cmd_segments "$cmd")

  if [ -n "$cd_acc" ]; then
    case "$cd_acc" in
      /*) RGCD_CTX_DIR="$cd_acc" ;;
      *)  RGCD_CTX_DIR="${hook_cwd}/${cd_acc}" ;;
    esac
  fi
  if [ -n "$RGCD_MATCHED_SEG" ]; then
    local c_dir
    c_dir=$(printf '%s' "$RGCD_MATCHED_SEG" | sed -nE 's/.*-C[[:space:]]*([^[:space:]]+).*/\1/p')
    c_dir=$(_rgcd_expand_tilde "$c_dir")
    [ -n "$c_dir" ] && RGCD_CTX_DIR="$c_dir"
  fi
  return 0
}
