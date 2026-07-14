#!/bin/bash
# UserPromptSubmit hook: ユーザー入力のパターンからサブエージェント委任を提案する
# 注入タグ: [SUBAGENT-DELEGATION-HINT]
# block しない（提案のみ）。複数候補を同時注入する。
# 正本: ~/.claude/rules/always/agent/subagent-selection/rule.md

set -euo pipefail

input="$(cat)"
user_message="$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null)"
[ -z "$user_message" ] && exit 0

hint=""

# investigator / worker-sonnet: 調査・分析パターン
if echo "$user_message" | grep -qE '(調査|調べて|影響範囲|呼び出し元|依存関係|分析して|探して|追跡|整合性|違反.*チェック|dead.?code)'; then
  hint="調査・分析系のタスクを検出。変更を伴わない調査・分析は investigator（調査チェックリストパイプライン）、変更を前提とした影響範囲分析は worker-sonnet への委任を検討すること。"
fi

# worker-haiku: 一括編集パターン
if echo "$user_message" | grep -qE '(一括|全部.*変更|全ファイル|全件|リネーム|置換して|まとめて|一斉|テスト.*走|ビルド.*確認|lint.*実行)'; then
  hint="${hint:+$hint }一括編集系のタスクを検出。worker-haiku への委任を検討すること。"
fi

# researcher: 外部情報検索パターン
if echo "$user_message" | grep -qE '(検索して|ライブラリ|API.*(仕様|ドキュメント)|ドキュメント.*調べ|最新.*バージョン|Web.*検索|外部.*情報|公式|仕様を調べ|エラー.*(解決|原因|調べ))'; then
  hint="${hint:+$hint }外部情報収集のタスクを検出。researcher への委任を検討すること。"
fi

# brain: 複合タスク・計画パターン
if echo "$user_message" | grep -qE '(リファクタ|大規模|設計.*見直|分解|計画.*立て|アーキテクチャ|どうすべき|戦略|方針)'; then
  hint="${hint:+$hint }複合タスクを検出。brain による計画策定を検討すること。"
fi

[ -z "$hint" ] && exit 0

ctx="[SUBAGENT-DELEGATION-HINT] ${hint} 委任判定フローの正本: ~/.claude/rules/always/agent/subagent-selection/rule.md"
jq -n --arg msg "[フック発火] サブエージェント委任提案" --arg ctx "$ctx" \
  '{"systemMessage":$msg,"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$ctx}}'

exit 0
