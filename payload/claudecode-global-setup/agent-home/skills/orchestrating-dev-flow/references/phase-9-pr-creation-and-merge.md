# Phase 9: PR 作成・マージ

PR を作成し、レビュー・マージまで完了する。

対象ルート: 機能実装（フル計画）・機能修正（クイック）・設定・ドキュメント編集・リファクタ（挙動保証）

## Step 9-1: PR 作成

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 9 "PR 作成・マージ" 1 3 "PR 作成"`

`references/module-formatting-pr.md` を Read して手順に従い PR タイトルとボディを生成し、gh pr create で PR を作成する。PR タイトルとボディは命名規約（rules: always/naming/commit-branch）に従う。

**入力**: `references/module-formatting-pr.md` の手順に以下を渡す:
- 引数: 実装内容の概要・関連 issue 番号・flow-values.yml の pr.template
- 期待出力: 命名規約に準拠した PR タイトルと本文

**完了**: PR が命名規約に従い作成されていること

## Step 9-2: CI 確認

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 9 "PR 作成・マージ" 2 3 "CI 確認"`

CI が通過するまで待機する。失敗した場合は修正して再 push する。

**待機方法**: CI 待ちはフォアグラウンドの短周期ポーリングで行う（`gh pr checks <PR番号> --watch`、または timeout 付きの再試行ループ）。`run_in_background` の sleep での待機は禁止する（完了通知が届かず長時間 stall した実測あり）。

**PR にチェックが 1 件も報告されない場合の判定手順**:
1. リポジトリの workflow 稼働状況を確認する（`.github/workflows/` の有無・`gh workflow list`）
2. 直近のマージ済み先例 PR のチェック状況と、ローカル検証結果（lint・型・テスト）に基づき通過扱いとするかを判断する
3. 判断根拠を完了報告（または PR コメント）に記録する

**完了**: CI が通過していること（チェックが 1 件も報告されない場合は、上記判定手順の判断根拠が記録されていること）

**注記**: 恒常的に失敗する workflow（全 push で 0 秒失敗等）を根拠に通過扱いとした場合は、workflow 自体の修理タスクを spawn_task 等で切り出し、放置を防ぐ

## Step 9-3: マージ

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 9 "PR 作成・マージ" 3 3 "マージ"`

CI 通過後、gh pr merge でマージする。

**完了**: マージが完了していること

## 予想を裏切る挙動

- Step 9-1 の実害検証（UI 観察）: 新規 worktree には gitignore 済みの起動前提ファイル（`frontend/.env.local` 等）が引き継がれない。このとき dev サーバーを素で起動すると、アプリ全体が初期化失敗で描画不能になる場合がある（2026-07 実測）。ファイルを新規作成せず、必要な環境変数（`VITE_SUPABASE_URL` 等）をインライン指定して起動してから観察する

## 完了条件

- PR が作成されている
- CI が通過している
- マージが完了している

## 次 Phase

完了条件を満たしたら `references/phase-10-post-merge-cleanup.md` を Read して実行する。

## 参照コンテキスト

### プロジェクト固有（flow-values.yml）
- `pr.template` — PR テンプレートファイルパス

### グローバル規約
- pre-bash-dispatch-rules — commit/branch/PR 命名・textlint
- response-guard-rules — ユーザー操作依頼禁止・先送り禁止

### グローバル hook
- dispatch-pre-bash-checks.sh [TEXTLINT-BLOCK][PUBLISH-SAFETY] — PR 本文 textlint・公開可否 block（PreToolUse）
- check-no-deferral-pre-bash.sh [NO-DEFERRAL-BLOCK] — gh pr create 先送り表現 block（PreToolUse）

### 進捗管理
- 各 Step 開始時: TaskUpdate(in_progress)
- 各 Step 完了時: TaskUpdate(completed)
- Step 9-3（最後の Step）完了時: 次 Phase（Phase 10）の references を先読みし、Phase 10 の全 Step を TaskCreate
