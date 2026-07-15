# worktree 必須運用規約

orchestrating-dev-flow の全 5 ルートで worktree 内での作業を必須とする。

## 背景

- main ブランチで 3〜5 セッションが並行稼働する
- worktree なしだと複数セッションのファイル競合・進捗ファイル混在が発生する
- 進捗ファイル（flow-status.json）は worktree 内 `.claude/markers/${session}/` に配置する設計

## 規約

### 必須条件

- orchestrating-dev-flow の全ルート（フル・クイック・ドキュメント・メンテ・インシデント）で Phase 2（作業ブランチ準備）にて worktree を作成する
- cwd が既に worktree 内の場合は新規作成をスキップしてよい
- cwd が main ツリーの場合は必ず worktree を作成してから Phase 3 以降に進む

### main 直接編集が許されるケース

- orchestrating-dev-flow を呼ばない作業（調査・質問・設定変更のみ）
- フロー外の対話的なやりとり

### 進捗ファイルの配置

| ファイル | 配置先 | 用途 |
|---|---|---|
| flow-status.json | `.claude/markers/${session}/flow-status.json` | セッション内の進捗管理（揮発） |
| .flow-progress.json | worktree ルート直下 | セッション跨ぎの進捗引き継ぎ（.gitignore 対象） |

### .gitignore への追加

worktree 作成時に以下を `.gitignore` に追加する（未記載の場合）:

```
.flow-progress.json
.claude/markers/
```

## 違反時の動作

Phase 2 で worktree 外にいることを検出した場合:
1. ユーザーに「worktree を作成します」と通知
2. worktree を作成して cwd を移動
3. Phase 3 に進む

worktree 作成に失敗した場合:
1. エラーを報告し、フローを停止する
2. ユーザーに手動での worktree 作成を依頼しない（NO-DELEGATION 規約）
