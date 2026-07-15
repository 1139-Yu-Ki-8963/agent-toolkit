# Phase 5: 実装・テスト計画

実装の手順とテスト計画を策定する。

対象ルート: 機能実装（フル計画）・リファクタ（挙動保証）・機能修正（クイック）（簡略）

## Step 5-1: 実装手順の策定

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 5 "実装・テスト計画" 1 3 "実装手順の策定"`

Phase 4 の説明用 YAML（core.yaml）（フルルート）またはタスク内容（リファクタ（挙動保証）・機能修正（クイック））に基づき、実装手順を箇条書きで策定する。

クイックルートの場合は簡略化:
- 変更対象ファイルの列挙
- 変更内容の 1 行要約
- テスト方針の 1 行要約

**完了**: 実装手順が箇条書きで策定されていること（クイックルートは変更対象・変更内容・テスト方針の 1 行要約で代替されていること）

## Step 5-2: テスト計画（機能実装（フル計画）・リファクタ（挙動保証））

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 5 "実装・テスト計画" 2 3 "テスト計画"`

**スキップ**: 機能修正（クイック）ルートの場合はスキップ

TDD で書くテストの振る舞い一覧を策定する:
- テスト対象の振る舞いを優先順位付きでリストアップ
- パブリックインターフェース経由のテストを設計
- 「全部テストは不可能」— 重要パスと複雑ロジックに集中

**出力**: テスト計画（振る舞い一覧）（Phase 6 Step 6-2 の TDD サイクルに渡す）

**完了**: TDD で書くテストの振る舞い一覧が優先順位付きで策定されていること

## Step 5-2a: 単体テスト観点表の作成/更新（UI 変更時）

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 5 "実装・テスト計画" 2 3 "単体テスト観点表"`

**スキップ**: UI 変更がない場合、flow-values.yml に `screen_docs` が未設定の場合はスキップ

単体テスト観点表・結合テスト観点表の 2 枚を起票する（骨格は当該画面ディレクトリのテンプレート。受け入れ◯の観点は Phase 6 冒頭に失敗するテストとして先行作成する = 二重ループの外側）。

1. 配置先: `<screen_docs.base_dir>/<画面名>/単体テスト観点表.md`
2. 骨格: 当該画面ディレクトリのテンプレート（正本: `~/agent-home/templates/project-docs/02_画面基本設計/`）から複製する
3. Step 5-2 のテスト計画（振る舞い一覧）から観点を導出し、観点一覧に意味語キー（`<対象>-<観点要約>` 形式。例: `金額-下限境界`・`api失敗-error表示`）付きで記載する。連番 ID（記号 + 通し番号）は使わない（rules: always/review-checklist/meaningful-key-naming）

**入力**: Step 5-2 のテスト計画 + flow-values.yml の `screen_docs`

**完了**: 単体テスト観点表.md が作成/更新され、観点が 1 件以上記載されていること

## Step 5-2b: 結合テスト観点表の作成/更新（UI 変更時）

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 5 "実装・テスト計画" 2 3 "結合テスト観点表"`

**スキップ**: UI 変更がない場合、flow-values.yml に `screen_docs` が未設定の場合、または画面基本設計書が 30 行未満の場合はスキップ

flow-values.yml の `screen_docs` セクションを参照し、結合テスト観点表を作成/更新する。

1. 配置先: `<screen_docs.base_dir>/<画面名>/結合テスト観点表.md`
2. テンプレート: `project-portal/sites/rules/05-test/integration-test-viewpoint-template/rule.html` に従う
3. 必須セクション: 観点表概要 + テスト対象範囲 + 観点一覧 + 観点詳細 + 観点カバレッジ判定 + V 字対応マトリクス
4. Step 5-2 のテスト計画（振る舞い一覧）から観点を導出し、観点一覧に意味語キー（`<対象>-<観点要約>` 形式。例: `画面間連携-保存後遷移`・`参照権限-保存不可`）付きで記載する。連番 ID（記号 + 通し番号）は使わない（rules: always/review-checklist/meaningful-key-naming）。テストコードからのトレース（テスト名・コメント）にも同じ意味語キーを使う
5. V 字対応マトリクスに画面基本設計書のパスを記載する

**入力**: Step 5-2 のテスト計画 + flow-values.yml の `screen_docs`

**完了**: 結合テスト観点表.md が必須 6 セクションを含み、観点が 1 件以上記載されていること

## Step 5-3: 計画宣言

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 5 "実装・テスト計画" 3 3 "計画宣言"`

策定した実装計画をユーザーに宣言し、**待機せず次 Phase に進む**。承認待ちはしない。

「実装計画: [計画の要約]。このまま進めます」

ユーザーが途中で計画変更を指示した場合はその時点で修正する。

**完了**: 実装計画が宣言され、次 Phase に進んでいること

## 完了条件

- 実装手順が策定されている
- テスト計画が策定されている（機能実装（フル計画）・リファクタ（挙動保証））

## 次 Phase

ルートに応じて次 Phase が異なる:
- **feature-with-full-planning / feature-with-quick-delivery**: `references/phase-6-tdd-cycle.md` を Read して実行
- **refactor-with-safety-guarantee**: Phase 6 をスキップし `references/phase-7-completion-checks.md` を Read して実行

## 参照コンテキスト

### プロジェクト固有（flow-values.yml）
- `screen_docs` — 画面ドキュメント 4 ファイルセット定義（単体テスト観点表・結合テスト観点表の配置先）

### グローバル規約
- subagent-delegation-rules — Agent 委任判定
- no-premature-deferral-rules — 作業先送り禁止

### グローバル hook
- check-main-agent-direct-work.sh [MAIN-AGENT-DIRECT-WORK-BLOCK] — メイン直接作業 block（PreToolUse）

### 進捗管理
- 各 Step 開始時: TaskUpdate(in_progress)
- 各 Step 完了時: TaskUpdate(completed)
- Step 5-3（最後の Step）完了時: feature-with-full-planning / feature-with-quick-delivery は Phase 6 の references を先読みし TaskCreate。refactor-with-safety-guarantee は Phase 7 の references を先読みし TaskCreate
