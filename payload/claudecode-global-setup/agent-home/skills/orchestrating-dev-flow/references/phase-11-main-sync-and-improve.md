# Phase 11: メイン同期・自己改善

メインブランチを最新化し、フロー自体の改善を記録する。

対象ルート: 機能実装（フル計画）・機能修正（クイック）・設定・ドキュメント編集・リファクタ（挙動保証）

## Step 11-1: main 最新化

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 11 "メイン同期・自己改善" 1 2 "main 最新化"`

```bash
git pull origin main
```

**完了**: git pull が成功し、main ブランチが最新の状態であること

## Step 11-2: フロー改善メモ

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 11 "メイン同期・自己改善" 2 2 "フロー改善メモ"`

実行中に感じた摩擦・改善案があれば記録する。

**スキップ**: 摩擦・改善案がない場合はスキップ

**記録先の選び方**:
- 特定 Phase の手順に起因する摩擦 → 該当 `references/phase-N-*.md` の予想を裏切る挙動に追記
- フロー全体・複数 Phase にまたがる摩擦 → `SKILL.md` の予想を裏切る挙動に追記

**完了**: フロー改善メモが記録されていること（摩擦・改善案がない場合はスキップ済みであること）

## 予想を裏切る挙動

- Step 11-1: ローカル main に別セッション由来の未 push コミットがあると、`git pull origin main` が divergent branches で失敗する。変更ファイルの重なりを事前確認し、コンフリクト解消プロトコル（事前影響分析 → 報告・承認）を経てから解消する。解消方式は `git pull --rebase`（未 push コミットを origin/main 上へ載せ替え）または `git pull --no-rebase`（マージ統合）から選ぶ。別セッション由来の未 push コミットの push は本フローの責務外のため行わない

## 完了条件

- main ブランチが最新化されている

## 参照コンテキスト

### プロジェクト固有（flow-values.yml）
（なし）

### グローバル規約
- managing-review-gate-rules — managed ファイル編集ゲート

### グローバル hook
- check-managing-configs-review-needed.sh [MANAGING-REVIEW-REQUIRED] — managed ファイル編集 advisory（PostToolUse）

### 進捗管理
- 各 Step 開始時: TaskUpdate(in_progress)
- 各 Step 完了時: TaskUpdate(completed)
- （次 Phase なし。フロー完了）
