#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit|Bash) hook.
# メインエージェント（Claude 本体）の直接作業を検出し exit 2 で block する。
# サブエージェント・Read 系・グローバル設定管理は例外として通す（例外は「block しない」
# だけであり、委任原則「判断と反映の分離」（rule.md）の免除ではない）。
# Bash コマンド実行時は rules-bash-runner.sh 経由で間接的にも呼び出される。
# 再帰防止: 同一セッション 3 回連続で自動解除。
set -u

# --- テスト・再帰ガード ---
[ "${CLAUDE_HOOKS_TEST:-}" = "1" ] && exit 0
[ -n "${CLAUDE_HOOK_NO_DELEGATION_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_SUMMARY_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_AUTOCOMMIT_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_FLOW_REPORT_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_DICT_RUNNING:-}" ] && exit 0

input=$(cat)

# --- サブエージェントは対象外 ---
agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -n "$agent_id" ] && exit 0

# --- ツール判定 ---
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)

# Read 系・Agent・AskUserQuestion は常に許可
case "$tool" in
  Read|Grep|Glob|Agent|AskUserQuestion|TaskCreate|TaskUpdate|TaskGet|TaskList|TaskOutput|TaskStop|Skill|ToolSearch|WebFetch|WebSearch|SendUserFile|EnterPlanMode|ExitPlanMode|ScheduleWakeup|Monitor|PushNotification)
    exit 0
    ;;
esac

# --- 例外パス判定 ---
case "$tool" in
  Write|Edit|MultiEdit|NotebookEdit)
    file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    case "$file_path" in
      */.claude/rules/*|*/.claude/agents/*|*/.claude/settings*|*/.claude/CLAUDE.md|*/.claude/plans/*.md) exit 0 ;;
      */agent-home/*) exit 0 ;;
      /tmp/*|*/tmp/*) exit 0 ;;
    esac
    # 例外に該当しない Write/Edit → block へ進む
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -z "$cmd" ] && exit 0
    _chkseg() {
      case "$1" in
        cd\ *|cd) return 0 ;;
        "git status"*|"git log"*|"git diff"*|"git branch"*|"git show"*|"git remote"*|"git tag"*|"git stash list"*|"git worktree list"*|"git rev-parse"*|"git config --get"*|"git ls-files"*) return 0 ;;
        ls*|cat*|head*|tail*|find*|grep*|rg*|wc*|file*|which*|type*|echo*|printf*|jq*|date*|pwd*|id*|whoami*|uname*|sw_vers*|env*|printenv*) return 0 ;;
        "gh pr list"*|"gh pr view"*|"gh pr diff"*|"gh pr checks"*|"gh issue list"*|"gh issue view"*|"gh api"*|"gh repo view"*) return 0 ;;
        mkdir*|chmod*) return 0 ;;
        *"/tmp/"*) return 0 ;;
        *"/.claude/rules/"*|*"/.claude/agents/"*|*"/.claude/settings"*|*"/agent-home/"*) return 0 ;;
        *) return 1 ;;
      esac
    }
    _all_ok=true
    if printf '%s' "$cmd" | grep -qE '&&|;'; then
      _bflag="${TMPDIR:-/tmp}/.main-chk-block.$$"
      rm -f "$_bflag"
      printf '%s' "$cmd" | awk 'BEGIN{RS="[&][&]|;"} {gsub(/^[[:space:]]+|[[:space:]]+$/,""); if(length>0) print}' | while IFS= read -r _s; do
        _chkseg "$_s" || { touch "$_bflag"; break; }
      done
      [ -f "$_bflag" ] && { rm -f "$_bflag"; _all_ok=false; }
    else
      _chkseg "$cmd" || _all_ok=false
    fi
    "$_all_ok" && exit 0
    case "$cmd" in
      "git status"*|"git log"*|"git diff"*|"git branch"*|"git show"*|"git remote"*|"git tag"*|"git stash list"*|"git worktree list"*|"git rev-parse"*|"git config --get"*|"git ls-files"*) exit 0 ;;
      ls*|cat*|head*|tail*|find*|grep*|rg*|wc*|file*|which*|type*|echo*|printf*|jq*|date*|pwd*|id*|whoami*|uname*|sw_vers*|env*|printenv*) exit 0 ;;
      "gh pr list"*|"gh pr view"*|"gh pr diff"*|"gh pr checks"*|"gh issue list"*|"gh issue view"*|"gh api"*|"gh repo view"*) exit 0 ;;
      mkdir*|chmod*) exit 0 ;;
      *"/tmp/"*) exit 0 ;;
      *"/.claude/rules/"*|*"/.claude/agents/"*|*"/.claude/settings"*|*"/agent-home/"*) exit 0 ;;
    esac
    # 例外に該当しない Bash → block へ進む
    ;;
  *)
    # MCP ツール等のその他ツールは通す
    exit 0
    ;;
esac

# --- 再帰防止カウンタ ---
. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
counter="$(marker_path "$cwd" "$session" main-agent-direct-work.count)"
hits=0
[ -f "$counter" ] && hits=$(cat "$counter" 2>/dev/null || echo 0)
hits=$((hits + 1))
printf '%d' "$hits" > "$counter"

if [ "$hits" -ge 4 ]; then
  exit 0
fi

# --- block ---
ctx="[MAIN-AGENT-DIRECT-WORK-BLOCK] メインエージェントの直接作業を検出。内容が確定済みなら worker-sonnet に確定内容をベタ書きで委任する。方針が未確定なら先にメイン（大規模なら brain）で確定させてから委任する（判断と反映の分離）。~/.claude/rules/always/agent/subagent-selection/rule.md を参照。"
jq -n --arg ctx "$ctx" '{"systemMessage":"[フック発火] 委任強制: メインの直接作業を検出","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
printf '%s\n' "$ctx" >&2
exit 2
