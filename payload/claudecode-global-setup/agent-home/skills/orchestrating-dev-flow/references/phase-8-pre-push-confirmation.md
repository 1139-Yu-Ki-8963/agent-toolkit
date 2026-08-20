# Phase 8: プッシュ前最終確認

push 前の最終チェックを実行する。

対象ルート: 機能実装（フル計画）・機能修正（クイック）・設定・ドキュメント編集・リファクタ（挙動保証）

## Step 8-1: diff 確認

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 8 "プッシュ前最終確認" 1 4 "diff 確認"`

staged 全体の diff を確認し、意図しない変更が含まれていないことを確認する。

**完了**: staged 全体の diff に意図しない変更が含まれていないことが確認されていること

## Step 8-2: review gate 呼び出し

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 8 "プッシュ前最終確認" 2 4 "review gate 呼び出し"`

`.claude/rules/always/project-context/flow-values.yml` の `review_gates.pre_push` が設定されていれば、Skill ツールで呼び出す。

**スキップ**: review_gates.pre_push が未設定の場合はスキップ

**委任**: review_gates.pre_push に指定された Skill に以下を渡す:
- 引数: push 予定の diff 全体・対象ブランチ名
- 期待出力: プッシュ承認（PASS）または差し戻し理由（FAIL）
- プロジェクトに `docs/設計書レビュー観点.md` が存在する場合、その §3 観点表を合否基準として使う

**完了**: review_gates.pre_push ゲートを通過していること（設定されている場合）

## Step 8-3: commit と push 実行

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 8 "プッシュ前最終確認" 3 4 "commit と push 実行"`

```bash
git commit
git push -u origin <branch-name>
```

**完了**: commit SHA が取得でき、リモートへの push が成功していること

## Step 8-4: 公開同期と公開後確認

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 8 "プッシュ前最終確認" 4 4 "公開同期と公開後確認"`

**スキップ**: 共通 handoff の `publication.required` が false の場合

`publication.target` に定めた正規手順で agent-toolkit へ同期し、公開先を remote から再取得して内容と commit を確認する。ローカル payload の一致だけでは公開確認とみなさない。`publicationEvidence` は次の object schema で記録する。

```json
{
  "commit": {"sha": "<target-repo-sha>", "repository": "agent-toolkit"},
  "push": {"sha": "<same-sha>", "remote": "origin", "ref": "<remote-ref>"},
  "sync": {"command": "<executed-sync-command>", "exitCode": 0},
  "remoteFetch": {
    "remote": "origin",
    "ref": "<remote-ref>",
    "sha": "<same-sha>",
    "contentVerified": true
  }
}
```

`commit.sha`・`push.sha`・`remoteFetch.sha` は、publication target リポジトリの同一 commit でなければならない。単なる `done` 等の文字列は証拠として無効。記録後に次を実行する。

```bash
node ~/agent-home/skills/orchestrating-dev-flow/scripts/validate-handoff-coverage.mjs publication .claude/dev-flow/handoff-and-coverage.json
```

publication mode が PASS するまで Phase 8 と Goal を完了にしない。Goal/publication の最終判定はこの mode だけが担う。

## 完了条件

- diff に意図しない変更がない
- review gate を通過している（設定されている場合）
- commit SHA が記録されている
- push が成功している
- publication.required 時は正規同期と remote 再取得確認が済み、publication validator が PASS

## 次 Phase

完了条件を満たしたら `references/phase-9-pr-creation-and-merge.md` を Read して実行する。

## 参照コンテキスト

### プロジェクト固有（flow-values.yml）
- `review_gates.pre_push` — プッシュ前ゲート

### グローバル規約
- pre-bash-dispatch-rules — commit/branch/PR 命名・textlint
- subagent-delegation-rules — Agent 委任判定

### グローバル hook
- dispatch-pre-bash-checks.sh [NAMING-BLOCK][TEXTLINT-BLOCK] — コミットメッセージ命名・textlint block（PreToolUse）

### フロー専用 hook
- check-review-gate.sh [REVIEW-GATE-BLOCK] — review gate 未通過 block（advisory）
- check-flow-progress.sh [FLOW-PROGRESS-MISSING] — 進捗ファイル未完了 block（advisory）

### 進捗管理
- 各 Step 開始時: TaskUpdate(in_progress)
- 各 Step 完了時: TaskUpdate(completed)
- Step 8-4（最後の Step）完了時: 次 Phase（Phase 9）の references を先読みし、Phase 9 の全 Step を TaskCreate
