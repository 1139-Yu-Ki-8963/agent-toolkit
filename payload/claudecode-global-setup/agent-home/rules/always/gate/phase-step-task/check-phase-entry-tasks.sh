#!/usr/bin/env bash
# check-phase-entry-tasks.sh - PreToolUse(Bash) hook（rules-bash-runner.sh 経由・9 本目）
#
# 役割: update-flow-status.sh の新 phase 宣言（前回宣言と異なる phase 番号）を検出し、
#       当該 phase の step タスク登録数（record-step-tasks.sh のカウンタ）が total_steps に
#       達していなければ exit 2 で block する。
# 素通り（fail-safe）: 非対象コマンド / --init / 同一 phase の step 更新 / Phase D・I / 引数パース不能
# 仕様: ~/.claude/rules/always/gate/phase-step-task/rule.md
set -u

input="$(cat)"
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0
case "$cmd" in *update-flow-status.sh*) ;; *) exit 0 ;; esac
case "$cmd" in *--init*) exit 0 ;; esac

# 行継続（\ + 改行）を実引数の連結として解決してから、残る改行を空白化する。
# orchestrating-dev-flow の実行例は行継続付きのため、これを解決しないと引数パースが崩れて gate が素通りする
flat="${cmd//\\$'\n'/ }"
flat="${flat//$'\n'/ }"

# update-flow-status.sh 以降の引数部分を抽出（&& ; | で打ち切り）
argstr=$(printf '%s' "$flat" | sed -e 's/.*update-flow-status\.sh//' -e 's/&&.*//' -e 's/;.*//' -e 's/|.*//')

# クォートを尊重してトークン化。失敗時は fail-safe で素通り
tokens=$(printf '%s' "$argstr" | xargs printf '%s\n' 2>/dev/null) || exit 0
phase_num=$(printf '%s\n' "$tokens" | sed -n 1p)
total_steps=$(printf '%s\n' "$tokens" | sed -n 4p)

# 引数の妥当性検査（パース不能は素通り）
case "$phase_num" in ''|*[!0-9DI]*) exit 0 ;; esac
case "$total_steps" in ''|*[!0-9]*) exit 0 ;; esac

# Phase D / I はドキュメント・インシデント系のため gate で止めない（flow-gate 規約と同判断）
case "$phase_num" in D|I) exit 0 ;; esac

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

. "$HOME/.claude/rules/scoped/agent-config/hooks/shared/transcript-query.sh"
tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

# 同一 phase 内の step 更新は素通り（transcript から最後に突入した phase を取得）
last_phase=""
if [ -n "$tp" ] && [ -f "$tp" ]; then
  last_phase=$(grep -o '\[PHASE-ENTERED:[0-9A-Z]*\]' "$tp" 2>/dev/null | tail -1 | sed 's/\[PHASE-ENTERED:\(.*\)\]/\1/' || true)
fi
[ "$phase_num" = "$last_phase" ] && exit 0

# 新 phase 突入: transcript 内の step タスク登録数を検証
count=0
if [ -n "$tp" ] && [ -f "$tp" ]; then
  count=$(grep -c "\[STEP-TASK-RECORDED:${phase_num}\]" "$tp" 2>/dev/null || true)
fi
case "$count" in ''|*[!0-9]*) count=0 ;; esac

if [ "$count" -lt "$total_steps" ]; then
  printf '[PHASE-TASK-BLOCK] Phase %s 突入前の step タスク登録が不足（登録 %s / 必要 %s）。当該 phase の全 step を subject「Phase %s Step %s-<M>: <作業内容>」形式で TaskCreate してから再実行すること。~/.claude/rules/always/gate/phase-step-task/rule.md を参照。\n' \
    "$phase_num" "$count" "$total_steps" "$phase_num" "$phase_num" >&2
  exit 2
fi

jq -n --arg phase "$phase_num" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: ("[PHASE-ENTERED:" + $phase + "]")
  }
}'
exit 0
