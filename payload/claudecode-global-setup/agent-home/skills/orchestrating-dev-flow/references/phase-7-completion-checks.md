# Phase 7: 完了チェック

lint・型チェック・テスト全通過を確認する。

対象ルート: 機能実装（フル計画）・機能修正（クイック）・設定・ドキュメント編集・リファクタ（挙動保証）

## Step 7-1: lint 実行

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 7 "完了チェック" 1 3 "lint 実行"`

プロジェクトの lint コマンドを実行し、エラーをゼロにする。

**完了**: lint エラーが 0 件であること

## Step 7-2: 型チェック

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 7 "完了チェック" 2 3 "型チェック"`

TypeScript プロジェクトの場合、tsc --noEmit で型エラーをゼロにする。

**完了**: 型エラーが 0 件であること（TypeScript プロジェクトの場合のみ）

## Step 7-3: テスト全実行

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 7 "完了チェック" 3 3 "テスト全実行"`

全テストスイートを実行し、通過を確認する。失敗テストがあれば修正する。

ドキュメントルートの場合: HTML 構文チェック・リンク切れ検出に置換する（Phase D の Step D-5 で実施済みの場合はスキップ）。

**完了**: 全テストスイートが通過していること（ドキュメントルートは HTML 構文チェックとリンク切れ検出を通過していること）

## ループ設計

| 要素 | 定義 |
|---|---|
| 反復条件 | lint・型チェック・テストのいずれかが失敗した場合、修正→再実行を繰り返す |
| 上限回数 | 最大 5 回 |
| 収束停止 | lint エラー 0 件 + 型エラー 0 件 + テスト全通過 |
| 発散検知 | 同じエラーが 2 回連続で再発した場合、ループを止めて原因を報告する |

## 予想を裏切る挙動

- Step 7-1: lint 対象に main 由来の既存違反行（本ブランチ未変更の負債）が混ざり「既存行は変更しない」制約と衝突した場合、完了条件（lint エラー 0 件）を優先する。意味論が等価な safe fix（例: `NaN` → `Number.NaN`）は既存行にも適用してよい。等価な修正ができない場合は、プロジェクト既存の allowlist・凍結登録の仕組みで理由を付けて除外する（2026-07 実測）
- Step 7-3: lychee 検査に main 由来の既存リンク切れ負債が混ざり「PASS」の完了条件をそのまま満たせない場合、main ベースラインで同一コマンドを実行してエラー集合を突合し、「本ブランチ起因の新規リンク切れ 0 件」をもって通過と判定する。判断根拠（ベースライン件数との一致）を完了報告に記録する（2026-07-10 実測: main と worktree が共に 54 件で一致し新規 0 件と確認）

## 完了条件

- lint エラー 0 件
- 型エラー 0 件（TypeScript の場合）
- テスト全通過
- docs/ 配下を変更した場合、lychee（`.config/lychee.toml`）によるリンク検査が PASS していること

## 次 Phase

完了条件を満たしたら `references/phase-8-pre-push-confirmation.md` を Read して実行する。

## 参照コンテキスト

### プロジェクト固有（flow-values.yml）
- `pr.required_sections` — PR 必須セクション
- `pr.critical_globs` — クリティカルパスの glob パターン

### グローバル規約
- pre-bash-dispatch-rules — commit/branch/PR 命名・textlint

### グローバル hook
- dispatch-pre-bash-checks.sh [TEXTLINT-BLOCK] — docs 追加行・PR 本文の textlint block（PreToolUse）

### 進捗管理
- 各 Step 開始時: TaskUpdate(in_progress)
- 各 Step 完了時: TaskUpdate(completed)
- Step 7-3（最後の Step）完了時: 次 Phase（Phase 8）の references を先読みし、Phase 8 の全 Step を TaskCreate
