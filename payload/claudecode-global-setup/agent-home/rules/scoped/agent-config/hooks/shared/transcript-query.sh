#!/usr/bin/env bash
# transcript-query.sh — transcript / skill-log を走査する共有ヘルパー
# マーカーファイルの代替として、transcript 内のタグ出現回数や
# skill-log 内のスキル発火記録を参照する関数を提供する。
# 規約: ~/.claude/rules/scoped/agent-config/hooks/rule.md「マーカーファイル禁止」節

# transcript 内の注入タグ出現回数を返す
# 用途: livelock カウンタの代替(N回 block 後の自動解除)
# 使用例: count=$(count_tag_in_transcript "$tp" "NO-DEFERRAL-RESPONSE")
count_tag_in_transcript() {
  local tp="$1" tag="$2"
  [ -z "$tp" ] || [ ! -f "$tp" ] && echo 0 && return
  grep -c "\[$tag\]" "$tp" 2>/dev/null || true
}

# skill-log JSONL にスキル発火記録があるか判定する
# 用途: レビューゲート(*.pass マーカー)の代替
# 使用例: if check_skill_fired "$session" "reviewing-against-rules"; then ...
check_skill_fired() {
  local session="$1" skill="$2"
  local log="$HOME/agent-home/sessions/.skill-log/${session}.jsonl"
  [ -f "$log" ] && grep -q "\"skill\":\"$skill\"" "$log" 2>/dev/null
}

# livelock 自動解除の判定
# transcript 内の block タグ出現回数が閾値以上なら true（return 0）を返す。
# 各 hook の冒頭で呼び、true なら exit 0 で自動解除する。
# 使用例: should_auto_release "$tp" "NO-DEFERRAL-RESPONSE" 3 && exit 0
should_auto_release() {
  local tp="$1" tag="$2" threshold="$3"
  [ -z "$tp" ] || [ ! -f "$tp" ] && return 1
  local count
  count=$(grep -c "\[$tag\]" "$tp" 2>/dev/null || true)
  [ "$count" -ge "$threshold" ]
}

# === 旧マーカーファイル用ライブラリから移動した共有ユーティリティ ===

# marker_path — hook マーカーファイルのパス解決（廃止予定）
# 新規利用禁止。既存の skills/ 配下 hook が transcript 走査へ移行するまでの互換用。
_marker_worktree_root() {
  local cwd="$1"
  [ -z "$cwd" ] && return 1
  [ ! -d "$cwd" ] && return 1
  local root
  root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -z "$root" ] && return 1
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

# managed_asset_type - パスを受け取り managing-agent-configs の種別名を echo する
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

# escape_log_append - 緊急回避/fail-closed を永続ログに追記する
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

# split_cmd_segments <cmd> — &&/||/;/|/& で分割し1行1セグメントで出力
split_cmd_segments() {
  printf '%s' "$1" | awk '{
    gsub(/\r?\n/, ";");
    gsub(/&&/, "\n"); gsub(/\|\|/, "\n");
    gsub(/;/, "\n"); gsub(/\|/, "\n"); gsub(/&/, "\n");
    print
  }'
}

CMD_CTX_GIT_COMMIT_RE='^[[:space:]]*(command[[:space:]]+)?git([[:space:]]+(-C|-c)[[:space:]]*[^[:space:]]+|[[:space:]]+--?[[:alnum:]=/._-]+)*[[:space:]]+commit([[:space:]]|$)'
CMD_CTX_GIT_PUSH_RE='^[[:space:]]*(command[[:space:]]+)?git([[:space:]]+(-C|-c)[[:space:]]*[^[:space:]]+|[[:space:]]+--?[[:alnum:]=/._-]+)*[[:space:]]+push([[:space:]]|$)'

_rgcd_expand_tilde() {
  case "$1" in
    "~")    printf '%s' "$HOME" ;;
    "~/"*)  printf '%s' "$HOME${1#\~}" ;;
    *)      printf '%s' "$1" ;;
  esac
}

# resolve_git_ctx_dir <cmd> <target_regex> <hook_cwd>
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
