#!/usr/bin/env bash
# PreToolUse(Agent) hook.
# Agent 呼び出しで subagent_type が general-purpose/claude（model非固定の汎用型）
# のとき、prompt内容が既存の委任判定カテゴリに該当するなら、名前付き
# （model固定済み）サブエージェントへの変更を要求してblockする。
# 該当カテゴリがない残余タスクの場合は model の明示指定のみを要求する。
# 正本: ~/.claude/rules/always/agent/subagent-selection/rule.md
# 再帰防止: カテゴリ判定・model指定の各系統で同一セッション4回連続で自動解除。
set -u

[ "${CLAUDE_HOOKS_TEST:-}" = "1" ] && exit 0
[ -n "${CLAUDE_HOOK_SUMMARY_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_FLOW_REPORT_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_AUTOCOMMIT_RUNNING:-}" ] && exit 0

input=$(cat)

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$tool" != "Agent" ] && exit 0

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -n "$agent_id" ] && exit 0

subagent_type=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
[ -z "$subagent_type" ] && subagent_type="general-purpose"

case "$subagent_type" in
  general-purpose|claude) ;;
  *) exit 0 ;;
esac

prompt=$(printf '%s' "$input" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
model=$(printf '%s' "$input" | jq -r '.tool_input.model // empty' 2>/dev/null)

category=""
if printf '%s' "$prompt" | grep -qE '(調査|レビュー|分析|確認|検証|根本原因|evaluate|review|investigate|analyze|audit|inspect|PR.*差分|diff.*分析)'; then
  category="investigator（変更を伴わない調査・分析・根本原因特定）/ report-reviewer（調査報告の合否判定）/ worker-sonnet（確定方針に基づく修正・PR差分の分析）"
fi
if [ -z "$category" ] && printf '%s' "$prompt" | grep -qE '(検索して|ライブラリ|API.*(仕様|ドキュメント)|Web.*検索|外部.*情報|公式.*仕様)'; then
  category="researcher（外部情報検索）"
fi
if [ -z "$category" ] && printf '%s' "$prompt" | grep -qE '(リファクタ|大規模|設計.*見直|分解|計画.*立て|アーキテクチャ|戦略|方針)'; then
  category="brain（タスク分解・計画）"
fi
if [ -z "$category" ] && printf '%s' "$prompt" | grep -qE '(一括|全部.*変更|全ファイル|全件|リネーム|置換して|まとめて|テスト.*走|ビルド.*確認|lint.*実行)'; then
  category="worker-haiku（コマンド実行のみ）/ worker-sonnet（ファイル変更を伴う一括作業）"
fi

. "$HOME/.claude/rules/scoped/agent-config/hooks/shared/transcript-query.sh"
tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

if [ -n "$category" ]; then
  should_auto_release "$tp" "SUBAGENT-CHOICE-BLOCK" 4 && exit 0
  ctx="[SUBAGENT-CHOICE-BLOCK] このタスクは ${category} に分類されます。${subagent_type} ではなく、該当する名前付きサブエージェント（modelが固定済み）を使ってください。正本: ~/.claude/rules/always/agent/subagent-selection/rule.md"
  jq -n --arg ctx "$ctx" '{"systemMessage":"[フック発火] サブエージェント選択: 分類該当につき変更要求","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
fi

if [ -z "$model" ]; then
  should_auto_release "$tp" "SUBAGENT-CHOICE-BLOCK" 4 && exit 0
  ctx="[SUBAGENT-CHOICE-BLOCK] ${subagent_type} は model を固定していないため、セッションの現在モデルを継承します。model パラメータを明示指定してください。正本: ~/.claude/rules/always/agent/subagent-selection/rule.md"
  jq -n --arg ctx "$ctx" '{"systemMessage":"[フック発火] サブエージェント選択: model未指定","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
fi

exit 0
