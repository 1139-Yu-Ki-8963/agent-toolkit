# Phase 10: マージ後片付け

worktree の削除と後処理を行う。

対象ルート: 機能実装（フル計画）・機能修正（クイック）・設定・ドキュメント編集・リファクタ（挙動保証）

## Step 10-1: 進捗ファイルのクリーンアップ

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 10 "マージ後片付け" 1 4 "進捗ファイルのクリーンアップ"`

1. worktree 内の `.claude/markers/${session}/flow-status.json` を削除する。sandbox フォールバック先 `/tmp/claude/claude-hooks/${session}/flow-status.json` も存在すれば削除する。session ID 不明の実行では `${session}` が `unknown` になるため、`unknown` ディレクトリ側も確認する
2. セッション固有の一時ファイルを削除する
3. worktree ルートの `.flow-progress.json` を削除する（PR マージ済みの場合のみ。レビュー中は残す）
4. 進捗ファイルを監査用に退避する場合は、可視ファイル名（例: `flow-progress-final.json`）にリネームして cp する。隠しファイル名（`.flow-progress.json` 等）のまま退避しない（監査での見落とし防止）

**完了**: flow-status.json と一時ファイルが削除されていて、.flow-progress.json の状態（削除 or 保持）が確定していること

## Step 10-2: worktree 削除

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 10 "マージ後片付け" 2 4 "worktree 削除"`

1. PR がマージされた場合:
   - 作業用 worktree を削除する（.flow-progress.json・.port-slot も自動消滅）
   - ポート管理規約に従い、該当スロットのポート範囲を一括 kill する
2. PR がまだオープンの場合:
   - worktree はそのまま残す（レビュー対応のため）
   - `.flow-progress.json` も残す（セッション再開時に進捗復元するため）

**完了**: worktree が削除されていること（PR マージ済み）またはそのまま保持されていること（PR オープン中）で、残留プロセスがないこと

## Step 10-3: ブランチ削除

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 10 "マージ後片付け" 3 4 "ブランチ削除"`

1. マージ済みのローカルブランチを `git branch -d <branch>` で削除する
2. リモートブランチはマージ時の自動削除の確認のみでよい。`git ls-remote --heads origin <branch>` が空なら削除済み。この状態での `git push --delete` は「remote ref does not exist」で終わるが異常ではない。残っている場合のみ `git push origin --delete <branch>` で削除する

**完了**: マージ済みのローカルブランチが削除されていて、リモートブランチの削除（自動削除の確認を含む）が確定していること

## Step 10-4: 完了報告

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 10 "マージ後片付け" 4 4 "完了報告"`

1. ユーザーに以下を報告する:
   - 作成した PR の URL
   - 実行した Phase の一覧
   - スキップした Phase とその理由
   - 進捗ファイルの状態（削除済み or 保持中）

**完了**: PR URL・実行 Phase・スキップ Phase・進捗ファイルの状態がユーザーに報告されていること

## 完了条件

- セッション固有の進捗ファイル（flow-status.json）が削除されている
- worktree の後処理が完了している（削除 or 保持）
- マージ済みのローカルブランチが削除されている
- 残留プロセスがない
- PR マージ済みの場合: .flow-progress.json が削除されている
- PR オープン中の場合: .flow-progress.json が保持されている

## 次 Phase

完了条件を満たしたら `references/phase-11-main-sync-and-improve.md` を Read して実行する。

## 参照コンテキスト

### プロジェクト固有（flow-values.yml）
- `flow.log_dir` — フローログ出力先ディレクトリ

### グローバル規約
- port-management-rules — ポート番号管理（worktree 削除時のポート kill）

### グローバル hook
（なし）

### 進捗管理
- 各 Step 開始時: TaskUpdate(in_progress)
- 各 Step 完了時: TaskUpdate(completed)
- Step 10-4（最後の Step）完了時: 次 Phase（Phase 11）の references を先読みし、Phase 11 の全 Step を TaskCreate
