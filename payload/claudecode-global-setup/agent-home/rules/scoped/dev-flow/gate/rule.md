---
paths:
  - "src/**"
  - "app/**"
  - "lib/**"
  - "pages/**"
  - "components/**"
---

# 実装フローゲート（FLOW-GATE）

~/Projects/ 配下のプロジェクトへのコードファイル書き込みを、orchestrating-dev-flow の Phase 6（実装）到達前に block する規約。サブエージェントも block 対象。

## 概要

orchestrating-dev-flow を経由せずにサブエージェントが ~/Projects/ 配下のプロジェクトに直接コードを書ける問題を防止する。既存の flow ゲート hook が全て advisory（exit 0）で block しない設計であり、check-main-agent-direct-work.sh がサブエージェントを明示除外していたため、サブエージェント経由の無制約な書き込みが可能だった。

## 判定ロジック

1. file_path が `.flow-progress.json` → block（直接書き換え防止。`update-flow-status.sh` 経由のみ許可）
2. file_path が ~/Projects/ 配下でなければ通過
3. file_path が .claude/ 配下、CLAUDE.md、docs/ 配下なら通過
4. cwd が agent-home なら通過
5. CLAUDE_SKILL_NAME が creating-new-project なら通過
6. プロジェクトルートに `.claude/rules/always/project-context/flow-values.yml` が存在しない → block
7. `.flow-progress.json` の `route` を読み、ルート別の前提 Phase が `phases_completed` に全て含まれるか検証 → 不足があれば block
8. `route` が不明の場合はフォールバック: `current_phase >= 6` チェック
9. 上記以外 → 通過

### current_phase の取得元（優先順）

1. `<project_root>/.flow-progress.json`（セッション跨ぎ進捗）
2. `marker_path` ヘルパー経由の `flow-status.json`（セッション内進捗）
3. どちらも存在しない場合は Phase 0 として扱う

### ルート別コード書き込み前提条件

| ルート | 前提 Phase（全て phases_completed に含まれる必要あり） |
|---|---|
| feature-with-full-planning | 1, 2, 3, 4, 5 |
| feature-with-quick-delivery | 1, 2, 5 |
| refactor-with-safety-guarantee | 1, 2, 5 |
| config-with-review-and-verify | 通過（コードゲート不要） |
| incident-with-emergency-path | 通過（緊急復旧はゲートで止めない） |
| route 不明 | フォールバック: current_phase >= 6 |

### .flow-progress.json 直接書き換え防止

Write / Edit ツールで `.flow-progress.json` を直接編集することを block する。Phase 進捗の更新は `update-flow-status.sh` 経由のみ許可する。`update-flow-status.sh` は Bash ツール経由で実行されるため、PreToolUse(Write|Edit) hook の検出対象外となる。

### 特殊ルートの扱い

- Phase D（ドキュメント編集）: 通過（コード編集を伴わないルートのため）
- Phase I（インシデント対応）: 通過（緊急復旧はゲートで止めない）

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PreToolUse(Write\|Edit\|MultiEdit\|NotebookEdit) | `check-dev-flow-phase-gate.sh` | `[DEV-FLOW-PHASE-GATE-BLOCK]` | ~/Projects/ 配下のコードファイル編集を exit 2 で block |
| PreToolUse(Agent) | `check-dev-flow-agent-gate.sh` | `[DEV-FLOW-AGENT-GATE-BLOCK]` | `~/Projects/`配下のcwdで、ファイル編集可能なsubagent_type（worker-sonnet等）のAgent起動時に`.flow-progress.json`のrouteが空ならexit 2でblock。Read-only系subagent_type・`.flow-progress.json`不在・route確定済みは通過。同一セッション3回連続で自動解除 |

## 違反検知時の手順

### `[DEV-FLOW-PHASE-GATE-BLOCK]` 受信（実装フロー未設定）

1. `Skill(orchestrating-dev-flow)` を起動する
2. フローが `.claude/rules/always/project-context/flow-values.yml` を作成する
3. フロー内の Phase に従い作業を進める

### `[DEV-FLOW-PHASE-GATE-BLOCK]` 受信（Phase 6 未到達）

1. 現在の Phase を確認する（block メッセージに Phase 番号が記載されている）
2. orchestrating-dev-flow のフローに従い、Phase 6 まで進める
3. Phase 6 到達後に改めてコードの書き込みを行う

### `[DEV-FLOW-PHASE-GATE-BLOCK]` 受信（前提 Phase 未完了）

1. block メッセージに記載された不足 Phase を確認する
2. orchestrating-dev-flow のフローに従い、不足 Phase を順番に実行する
3. 全前提 Phase が完了した後に改めてコードの書き込みを行う

### `[DEV-FLOW-PHASE-GATE-BLOCK]` 受信（.flow-progress.json 直接編集）

1. Write / Edit による `.flow-progress.json` の直接編集を中止する
2. Phase 進捗の更新が必要な場合は `update-flow-status.sh` を Bash ツールで実行する
3. 初期化が必要な場合は `update-flow-status.sh --init <route>` を実行する

### `[DEV-FLOW-AGENT-GATE-BLOCK]` 受信

1. `Skill(orchestrating-dev-flow)`を起動し、route確定（Phase 1完了）まで完走させる
2. 確立されたworktreeパスを委任プロンプトにベタ書きで渡してからAgent委任を再実行する

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: フロー Phase ゲートは開発フローの枠組みであり、プロジェクトに依存しない（ルート別条件は `.flow-progress.json` 側が持つ）ため受け口を設けない

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 関連

- `~/agent-home/skills/orchestrating-dev-flow/SKILL.md` — 統合開発フローの全体設計
- `~/.claude/rules/always/agent/subagent-selection/rule.md` — check-main-agent-direct-work.sh（メインエージェントの直接作業 block）
- `~/.claude/rules/scoped/dev-flow/worktree/rule.md` — worktree 外編集 block
- `~/agent-home/skills/orchestrating-dev-flow/scripts/check-flow-progress.sh` — git push 時の advisory
- `~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh` — flow-status.json 書き出し
