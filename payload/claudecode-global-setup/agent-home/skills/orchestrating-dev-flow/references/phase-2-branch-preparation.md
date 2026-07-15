# Phase 2: ブランチ準備

feature ブランチを作成し、worktree 内で作業可能な状態にする。
全 5 ルートで worktree 作成は必須。main ブランチ直接での実装作業は禁止。

## Step 2-1: 並走 PR チェック

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 2 "作業ブランチ準備" 1 5 "並走 PR チェック"`

1. `gh pr list --state open` で同じ領域に関する OPEN な PR がないか確認する
2. 競合リスクがある PR を検出したらユーザーに報告する

**完了**: OPEN な PR が確認されていて、競合リスクがある場合はユーザーに報告されていること

## Step 2-2: worktree 判定

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 2 "作業ブランチ準備" 2 5 "worktree 判定"`

1. `git rev-parse --git-dir` で `.git` がファイルかディレクトリかを確認する
2. ファイルなら → 既に worktree 内。Step 2-3 をスキップし Step 2-4 へ
3. ディレクトリなら → メインツリー。Step 2-3 へ（必須、スキップ不可）

**完了**: 現在の作業場所（worktree またはメインツリー）が確定し、次の Step の要否が判断されていること

## Step 2-3: worktree 作成（メインツリーからの場合は必須）

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 2 "作業ブランチ準備" 3 5 "worktree 作成"`

**スキップ**: 既に worktree 内（Step 2-2 で `.git` がファイルと判定）の場合はスキップ

1. `Skill(parallel-dev-worktree)` を呼び出してブランチ + worktree を作成する
2. worktree のパスを記録する
3. 以降の全 Phase は作成された worktree 内で実行する

**委任**: Skill("parallel-dev-worktree") に以下を渡す:
- 引数: 作業ブランチ名（タスク内容から提案）・プロジェクトのベースポート
- 期待出力: 作成された worktree のパスとブランチ名

**完了**: worktree が作成され、以降の全 Phase の実行場所が worktree 内に確定していること

## Step 2-4: 環境確認

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 2 "作業ブランチ準備" 4 5 "環境確認"`

1. worktree 内で `git status` を実行し、クリーンな状態であることを確認する
2. 依存パッケージの扱いはルートで分岐する
   - config-with-review-and-verify ルート（アプリコードを変えない docs 等のみの変更）は依存インストールを省略する。`npm install` / `pip install` 等を実行しない
   - config ルートでは代わりに、Phase D-5 / 7 の品質チェックに必要なツール（textlint・lychee 等）の利用可否確認のみ行う
   - 他ルートは従来どおり依存パッケージをインストールする（`npm install` / `pip install` 等）

**完了**: git status がクリーンで、ルートに応じた依存準備（config ルートはツール利用可否確認、他ルートは依存インストール）が完了していること

## Step 2-5: 進捗ファイルの初期化

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 2 "作業ブランチ準備" 5 5 "進捗ファイルの初期化"`

1. worktree ルートに `.flow-progress.json` が存在するか確認する
2. 存在する場合 → 前セッションの進捗を復元し、中断した Phase から再開する
3. 存在しない場合 → 以下のコマンドで初期化する（Write ツールでの直接作成は hook で block される）:

   ```bash
   bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh --init <route>
   ```

   `<route>` には Phase 1 で確定したルート識別子（例: `feature-with-full-planning`）を指定する。

**完了**: .flow-progress.json が存在し、前セッションの進捗が引き継がれているか新規初期化が完了していること

## 完了条件

- [ ] 並走 PR の競合リスクが確認済みである
- [ ] worktree 内で作業している（メインツリーではない）
- [ ] feature ブランチが作成されている
- [ ] `git status` がクリーンである
- [ ] `.flow-progress.json` が初期化されている

## 次 Phase

ルートに応じて次 Phase が異なる:
- **feature-with-full-planning**: Phase 3 → 4 → 5 → 6 → 7 → 8 の順
- **feature-with-quick-delivery**: Phase 3-4 をスキップし Phase 5 に直行（簡略モード）
- **config-with-review-and-verify**: Phase D に直行（Phase 3-8 をスキップ）
- **refactor-with-safety-guarantee**: Phase 3-4 をスキップし Phase 5 に直行
- **incident-with-emergency-path**: `references/incident-flow-i1-i7.md` を Read して実行

## 参照コンテキスト

### プロジェクト固有（flow-values.yml）
- `scripts.suggest_branch` — ブランチ名提案スクリプト

### グローバル規約
- worktree-required-rules — メインツリー直接編集禁止
- port-management-rules — ポート番号管理
- pre-bash-dispatch-rules — commit/branch/PR 命名・textlint

### グローバル hook
- check-worktree-required.sh [WORKTREE-REQUIRED] — メインツリー編集 block（PreToolUse）
- dispatch-pre-bash-checks.sh [NAMING] — ブランチ命名規則 advisory（PreToolUse）

### 進捗管理
- 各 Step 開始時: TaskUpdate(in_progress)
- 各 Step 完了時: TaskUpdate(completed)
- Step 2-5（最後の Step）完了時:
  - feature-full: Phase 3 の references を先読みし TaskCreate
  - feature-quick / refactor: Phase 5 の references を先読みし TaskCreate
  - config: Phase D の references を先読みし TaskCreate
  - incident: incident-flow-i1-i7.md を先読みし全 Step を TaskCreate
