# Phase D: ドキュメント編集

アプリコードを一切変えない docs・.claude 編集専用フロー。

対象ルート: 設定・ドキュメント編集のみ

## Step D-1: 変更対象の特定

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh D "ドキュメント編集" 1 5 "変更対象の特定"`

編集対象のドキュメントファイルを特定する。

**完了**: 編集対象のドキュメントファイルが特定されていること

## Step D-2: 編集計画

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh D "ドキュメント編集" 2 5 "編集計画"`

変更内容の計画を策定する。共通 handoff の userCorrections・priorFailures・actionable findings を全件、`sourceId, source, target, implementation, verification, status` の指摘対応表へ入れる。priorFailures は先に再現し、文書・設定向けの回帰検証へ固定する。再現不能なら実測証拠と理由を記録する。

```bash
node ~/agent-home/skills/orchestrating-dev-flow/scripts/validate-handoff-coverage.mjs implementation .claude/dev-flow/handoff-and-coverage.json
```

**完了**: 変更計画と対応表が正規 artifact `.claude/dev-flow/handoff-and-coverage.json` に保存され、implementation validator が PASS

## Step D-3: 計画宣言

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh D "ドキュメント編集" 3 5 "計画宣言"`

変更計画をユーザーに宣言し、**待機せず Step D-4 に進む**。承認待ちはしない。

「変更計画: [対象ファイル一覧と変更内容の要約]。このまま進めます」

ユーザーが途中で計画変更を指示した場合はその時点で修正する。

**完了**: 変更計画が宣言され、Step D-4 に進んでいること

## Step D-4: 編集実行

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh D "ドキュメント編集" 4 5 "編集実行"`

承認された計画に従いドキュメントを編集する。

Step D-2 の implementation validator が PASS していなければ編集を開始しない。新 FAIL が出たら対応表と回帰検証へ追加した後だけ再編集する。

**完了**: 承認された計画に従いドキュメントの編集が完了していること

## Step D-5: 品質チェック

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh D "ドキュメント編集" 5 5 "品質チェック"`

ドキュメント固有の品質チェック:
- HTML 構文チェック（HTML ファイルの場合）
- リンク切れ検出（lychee（`.config/lychee.toml`）を使用）
- textlint（日本語ドキュメントの場合）

完了後は Phase 7（完了チェック）に合流する。

**完了**: HTML 構文チェック・リンク切れ検出・textlint の品質チェックを通過していること

## 完了条件

- ドキュメント編集が完了している
- Step D-2 の対応表と implementation validator が PASS
- 品質チェックを通過している

## 次 Phase

`references/phase-7-completion-checks.md` を Read して実行する。

## 参照コンテキスト

### プロジェクト固有（flow-values.yml）
（なし）

### グローバル規約
- pre-bash-dispatch-rules — commit/branch/PR 命名・textlint
- no-premature-deferral-rules — 作業先送り禁止

### グローバル hook
- dispatch-pre-bash-checks.sh [TEXTLINT-BLOCK] — docs 追加行・PR 本文の textlint block（PreToolUse）

### 進捗管理
- Phase D 開始時: Phase D の references から全 Step を TaskCreate（ドキュメントルートは Phase 1 → D に直行するため、Phase 1 の最後で TaskCreate）
- 各 Step 開始時: TaskUpdate(in_progress)
- 各 Step 完了時: TaskUpdate(completed)
- Step D-5（最後の Step）完了時: 次 Phase（Phase 7）の references を先読みし、Phase 7 の全 Step を TaskCreate
