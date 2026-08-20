# セッションワークフロー起動ゲート（SESSION-WORKFLOW-GATE）

毎ユーザーターンで managing-session-workflow の全文を供給し、(1) checksum 付き供給記録、(2) 実作業前検査、(3) 応答終了前検査の 3 層でセッション状態の再評価を強制する規約。

## 背景

managing-session-workflow の SessionStart hook は advisory（exit 0）のみで Skill() を直接呼べない設計制約がある。advisory だけでは Claude が無視する可能性があり、セッションログ分析（2026-07-23）で 902 セッション中一度も発火していなかった実績がある。advisory 注入の修正だけでは 100% の起動保証ができないため、実作業の block（第 2 層）で強制した。しかし第 2 層は Write / Edit / MultiEdit / Bash 呼び出しが一度も発生しない会話のみのセッション（2026-07-23 の 4493d208 で実測）では起動されないまま応答が終わる穴があり、ユーザー指摘を受けて第 1 層（毎発話への起動指示注入）と第 3 層（応答終了時の block）を追加し 3 層構成に拡張した。

## 規約の要点

- UserPromptSubmit ごとに `skills/managing-session-workflow/SKILL.md` 全文を additionalContext へ注入する
- 注入前に共通 handoff の必須キーを検査し、供給後に tmp 配下へ schemaVersion・sessionId・promptSha256・skillSha256・requestTypeHint・handoffContractKeys・workflowExecutionStatus・suppliedAt・contextSupplied を記録する
- 供給記録は Skill 実行完了ログではない。skill-log の名前一致や `codex-session-start-bootstrap` では通過しない
- `workflowExecutionStatus` は常に `not-recorded`。文脈供給を Skill 実行完了へ昇格させない
- PreToolUse と Stop は現在の SKILL.md checksum と現ターン prompt checksum を供給記録へ照合する
- 現ターン hash は入力 `.prompt`、`.current_prompt_sha256`、transcript の最新 user message の順で解決し、取得不能なら block
- Codex adapter は UserPromptSubmit の hash を turn-state に記録し、後続イベントの互換入力へ注入する
- `AGENT_HOME_ROOT` と `SESSION_WORKFLOW_CONTEXT_FILE` でテスト用正本を切り替えられる

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| UserPromptSubmit | `check-session-workflow-prompt.sh` | `[SESSION-WORKFLOW-CONTEXT]` | 毎発話へ全文を注入し checksum 付き供給記録を作る |
| PreToolUse(...) | `check-session-workflow-gate.sh` | `[SESSION-WORKFLOW-BLOCK]` | 供給記録と現在 checksum が一致しない実作業を exit 2 で block |
| Stop | `check-session-workflow-stop.sh` | `[SESSION-WORKFLOW-STOP-BLOCK]` | 現ターン供給を確認できない応答終了を差し戻す |

## 違反検知時の手順

### `[SESSION-WORKFLOW-CONTEXT]` 受信

1. 注入された全文に従い、直近発話を新規・追加・訂正・置換・質問へ分類する
2. これは Skill 実行済みの証明ではないため、実行していない Skill を実行済みと記録しない

### `[SESSION-WORKFLOW-BLOCK]` 受信

1. UserPromptSubmit の全文供給と tmp の checksum 記録を確認する
2. 現在 SKILL.md と不一致なら再供給後に実作業を再実行する

### `[SESSION-WORKFLOW-STOP-BLOCK]` 受信

1. 当該ターンの UserPromptSubmit 全文供給と現ターン hash を確認する
2. 再供給後、改めて応答を書き直して再送する

### `[SESSION-FACILITATOR]` 受信

1. 応答末尾を (a) 次の一手の提案 (b) ユーザーにしか決められない質問（選択肢付き） (c) 完了宣言 + 次タスク確認 のいずれかで締める
2. 報告・解説のみで応答を終えない

## 設計判断

### check-session-workflow-gate.sh

設計判断（必要性・代替案・保守責任者・廃棄条件）の全文は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

### check-session-workflow-prompt.sh

設計判断（必要性・代替案・保守責任者・廃棄条件）の全文は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

### check-session-workflow-stop.sh

設計判断（必要性・代替案・保守責任者・廃棄条件）の全文は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: セッションワークフローの起動強制はプロジェクトに依存しない普遍的な品質管理であり、受け口を設けない

## 関連

- `~/agent-home/skills/managing-session-workflow/SKILL.md` — 管理者スキル本体
- `~/agent-home/skills/managing-session-workflow/scripts/suggest-session-workflow.sh` — SessionStart hook（advisory 注入）
- `~/.claude/rules/always/session/infra/rule.md` — skill-log 記録（本 hook の参照元）
