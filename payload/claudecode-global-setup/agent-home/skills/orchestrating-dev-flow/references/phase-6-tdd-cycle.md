# Phase 6: TDD サイクル

テスト駆動開発の赤→緑→リファクタループで実装する。

対象ルート: 機能実装（フル計画）・機能修正（クイック）

## Step 6-1: E2E 先行作成（UI 変更時のみ）

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 6 "テスト駆動実装（TDD）" 1 4 "E2E 先行作成"`

**スキップ**: UI 変更がない場合はスキップ

UI コンポーネントの変更を伴う場合、TDD サイクルの開始前に E2E テストの spec ファイルを作成する。プロジェクト側で E2E 先行作成を強制する hook が設定されている場合、spec 未作成のまま実装に入ることがブロックされる。

3. 結合テスト観点表（`<screen_docs.base_dir>/<画面名>/結合テスト観点表.md`）が存在する場合、各観点の意味語キー（`<対象>-<観点要約>` 形式。連番 ID は使わない）を E2E spec ファイルの describe/it ブロックにコメントとして記載する:
   ```typescript
   // 観点: ログイン-正常遷移
   it('正常ログインで TOP ページへ遷移する', async () => { ... });
   ```

**完了**: E2E テスト spec ファイルが作成されていること（UI 変更がある場合のみ。なければスキップ済みであること）

## Step 6-2: TDD サイクルの実行

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 6 "テスト駆動実装（TDD）" 2 4 "TDD サイクルの実行"`

**入力**: Phase 5 Step 5-2 のテスト計画（振る舞い一覧）

以下の TDD サイクルを実行する。水平スライス（テスト一括→実装一括）は禁止し、垂直スライス（1テスト→1実装）を徹底する。

1. **計画確認**: テスト対象の振る舞い一覧（Phase 5 で策定済み）をユーザーに確認する
2. **Tracer Bullet（最初の 1 サイクル）**: 振る舞い一覧の先頭 1 件について RED→GREEN を達成する
   - RED: パブリックインターフェース経由で失敗するテストを 1 件書く
   - GREEN: テストを通す最小限の実装を書く
3. **Incremental Loop（残りの振る舞い）**: 残りの振る舞いを 1 つずつ RED→GREEN で実装する。1 テストを書いたら即座に対応する実装を書き、GREEN を確認してから次のテストに進む
4. **Refactor**: 全振る舞いについて GREEN 達成後、テストを壊さない範囲でリファクタリングする

**完了**: 全振る舞いについて RED→GREEN が達成し、全テストが通過していること

## Step 6-3: review gate 呼び出し

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 6 "テスト駆動実装（TDD）" 3 4 "review gate 呼び出し"`

`.claude/rules/always/project-context/flow-values.yml` の `review_gates.impl_quality` が設定されていれば、各サイクル完了後に Skill ツールで呼び出す。

**スキップ**: review_gates.impl_quality が未設定の場合はスキップ

**委任**: review_gates.impl_quality に指定された Skill に以下を渡す:
- 引数: 実装済みコードと対応するテスト一覧
- 期待出力: 実装品質の評価結果（PASS / FAIL）

**完了**: review_gates.impl_quality ゲートを通過していること（設定されている場合）

## Step 6-4: ルート再評価（クイックルートのみ）

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 6 "テスト駆動実装（TDD）" 4 4 "ルート再評価"`

commit 直前に classify 条件を再評価する。条件違反（migration 追加・UI 変更等）を検出したらフルルートに昇格し Phase 1 から再開する。

**完了**: classify 条件の再評価が完了し、昇格不要が確認されていること（昇格した場合は Phase 1 から再開されていること）

## ループ設計

| 要素 | 定義 |
|---|---|
| 反復条件 | Step 6-2 内で管理（振る舞い一覧の各項目について RED→GREEN を繰り返す） |
| 上限回数 | 振る舞い一覧の項目数が上限。追加が必要な場合は Phase 5 に差し戻す |
| 収束停止 | 全振る舞いについて GREEN 達成、全テスト通過 |
| 発散検知 | 同一テストが 3 回連続 RED→GREEN に失敗した場合、Phase 5 の計画を見直す |

## 完了条件

- 全テストが通過している
- review gate を通過している（設定されている場合）
- クイックルートの再評価で昇格していない（昇格した場合は Phase 1 から再開）

## 次 Phase

完了条件を満たしたら `references/phase-7-completion-checks.md` を Read して実行する。

## 参照コンテキスト

### プロジェクト固有（flow-values.yml）
- `review_gates.impl_quality` — 実装品質ゲート
- `review_gates.e2e` — E2E テストゲート
- `scripts.detect_e2e_mandate` — E2E 必須判定スクリプト
- `e2e` — E2E 設定（fe_url / be_url / test_cmd）

### グローバル規約
- subagent-delegation-rules — Agent 委任判定
- worktree-required-rules — メインツリー直接編集禁止
- file-guard-rules — ファイル配置ガード

### グローバル hook
- check-main-agent-direct-work.sh [MAIN-AGENT-DIRECT-WORK-BLOCK] — メイン直接作業 block（PreToolUse）
- check-worktree-required.sh [WORKTREE-REQUIRED] — メインツリー編集 block（PreToolUse）

### フロー専用 hook
- check-review-gate.sh [REVIEW-GATE-BLOCK] — review gate 未通過 block（advisory）

### 進捗管理
- 各 Step 開始時: TaskUpdate(in_progress)
- 各 Step 完了時: TaskUpdate(completed)
- Step 6-4（最後の Step）完了時: 次 Phase（Phase 7）の references を先読みし、Phase 7 の全 Step を TaskCreate
