---
name: orchestrating-dev-flow
description: "開発オーケストレーター。 TRIGGER when: 「新機能追加」「バグ修正」「リファクタ」「ドキュメント編集」「インシデント対応」時。 SKIP: 設定/単発コミット。"
invocation: orchestrating-dev-flow
execution: main-session
type: orchestration
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent, AskUserQuestion, Skill]
---

開発タスクを 5 つのルートに分類し、Phase 1〜11 + Phase D + インシデント独自フロー（I1〜I7）を統制するオーケストレーター。プロジェクト固有のコンテキストは `.claude/rules/always/project-context/flow-values.yml` から注入する。

## 入力契約

呼び出し元から次の共通 handoff を受理する。Goal が無い場合も `goal: null` とし、キーを省略しない。

```yaml
goal: null
purpose: ""
completionCriteria: []
constraints: []
userCorrections: []
inputs: []
publication:
  required: false
  target: null
  verification: null
```

`inputs` に priorFailures・画像の actionable findings・調査結果が含まれる場合、各 route の既存計画工程（feature/refactor は Phase 5、config は Phase D Step D-2、incident は I2）へ統合する。セッション管理や Goal 作成は本 Skill の責務に追加しない。

## 使用タイミング

- `~/Projects/` 配下でコード・テンプレート・スキルファイルの編集を伴うタスクは、本スキルで route 確定（Phase 1 完了）を先に済ませてから着手する。route 未確定の状態でサブエージェントに編集を委任すると `[DEV-FLOW-PHASE-GATE-BLOCK]` でブロックされる

## ルート一覧

| 識別子 | 日本語名 | 用途 | 目安時間 |
|---|---|---|---|
| feature-with-full-planning | 機能実装（フル計画） | 新機能追加・挙動変更を伴うバグ修正 | 60 分 |
| feature-with-quick-delivery | 機能修正（クイック） | 変更ファイル ≤ 2 / migration なし / UI なし / API 契約なし / DB スキーマなし | 20 分 |
| config-with-review-and-verify | 設定・ドキュメント編集 | アプリコードを変えない docs・skills・rules・hooks・agents 変更 | 15 分 |
| refactor-with-safety-guarantee | リファクタ（挙動保証） | 挙動を変えない lint・deps 更新・純粋リファクタ | 45 分 |
| incident-with-emergency-path | 本番障害復旧 | P0 障害の緊急復旧（本番ダウン・データ消失等） | 最速 |

## ルート判定（Phase 1 で実行）

`references/phase-1-route-determination.md` を Read して判定する。判定ソースはタスク内容と `.claude/rules/always/project-context/flow-values.yml` の `classify` セクション。

## Phase マトリクス

**注意**: Phase 1 の前にプリフライトチェック（`references/module-preflight-check.md` の手順）が全ルート共通で実行される。incident-with-emergency-path では最小モード（CRITICAL ツールのみ確認）で実行する。

```
Phase                          フル計画  クイック  設定・docs  リファクタ  障害復旧
───────────────────────────────────────────────────────────────────────────────
 1: 調査 + ルート判定           ○         ○          ○          ○          ○
 2: 作業ブランチ準備            ○         ○          ○          ○          ○
 3: 要件ヒアリング              ○         -          -          -          -
 4: 仕様書 + 画面 UI モック作成  ○         -          -          -          -
 5: 実装・テスト計画            ○         簡略       -          ○          -
 6: テスト駆動実装（TDD）       ○         ○          -          -          -
 7: 完了チェック                ○         ○          ○          ○          ○
 8: プッシュ前最終確認          ○         ○          ○          ○          ○
 9: PR 作成・マージ             ○         ○          ○          ○          ○
10: マージ後片付け              ○         ○          ○          ○          ○
11: メイン同期・自己改善        ○         ○          ○          ○          ○
 D: ドキュメント編集            -         -          ○          -          -
 I1-I7: インシデント独自        -         -          -          -          ○
```

incident-with-emergency-path は Phase 1-2 の後に I1〜I7 の独自フローへ分岐し、I7 後は Phase 7-8 の完了・公開 gate を通ってから PR 作成・マージ後処理へ合流する。

## 実行手順

### 起動直後

**[前処理]** `references/module-preflight-check.md` を Read してプロジェクトの前提条件を検証する（毎回実行）。go を返したら以下に進む。no-go の場合はプリフライトが案内した修正方法に従い、修正完了後にフローを再起動する。incident-with-emergency-path の場合は `mode: minimal` で実行する。

**[全ルート共通の実装開始・FAIL gate]** feature / refactor / config / incident の全ルートで、最初の Write/Edit より前に次を満たす。

1. 共通 handoff を `validate-handoff-coverage.mjs schema` で検証する
2. userCorrections・priorFailures・actionable findings を既存ルートの計画工程の対応表へ全件入れる
3. priorFailures を先に再現し、回帰テスト化する。再現不能なら証拠と理由を対応表へ記録する
4. handoff と対応表を正規 artifact `.claude/dev-flow/handoff-and-coverage.json` に保存する
5. `validate-handoff-coverage.mjs implementation .claude/dev-flow/handoff-and-coverage.json` が PASS してから Write/Edit を開始する
6. 実装中の新 FAIL は同じ artifact の対応表と回帰テストへ追加した後だけ再実装する

config は Phase D Step D-2、incident は I2、feature/refactor は Phase 5 Step 5-1 が既存工程内の実施箇所である。別フローを増やさない。

1. `references/phase-1-route-determination.md` を Read してルートを判定する
2. 判定結果を宣言する: 「ルート判定: 本タスクは [ルート名]」
3. 全 Phase の TaskCreate を登録する（ルートに応じた Phase のみ）
4. **TaskCreate 未実施の実装ファイル編集を禁止する**: TaskCreate で全 Step を登録するまで、実装ファイルの Write/Edit を開始してはならない。プロジェクト側で `enforce-flow-feature-taskcreate.sh` 相当の hook が設定されている場合、機械的にブロックされる
5. Phase マトリクスに従い、該当する Phase ファイルを順次 Read して実行する

### 定期ヘルスチェック（Phase 2〜10）

Phase 2 完了後、`references/periodic-health-check.md` を Read し、ScheduleWakeup(600s) で定期ヘルスチェックループを開始する。Phase 10 完了時にループを停止する。

### Phase ファイルの読み込み

各 Phase は `references/phase-N-*.md` に格納。着手時に Read する（事前一括読み込み禁止）。

### 進捗更新

各 Phase の各 Step 開始時に以下を実行し、ステータスラインの進捗バーを更新する:

```bash
bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh <phase_num> "<phase_name>" <current_step> <total_steps> "<step_name>"
```

- `phase_num`: 数値 1〜11、または `D`（Phase D）・`I`（インシデント）
- `current_step`: 0 始まり（Step N-0 があれば 0、なければ 1 始まり）
- 各 Phase ファイルの各 Step 見出し直後に実行コマンドが記載されている

### コンテキスト注入（Phase 1）

`.claude/rules/always/project-context/flow-values.yml` が存在する場合は Read し、全セクションを取得する。存在しない場合は WARN を記録し、標準値で続行する。既存ファイルが YAML として不正な場合だけ停止する。
- `classify`: ルート判定閾値
- `domain_glossary`: ドメイン用語辞書のパス
- `design_system`: デザイン規約のパス
- `test_conventions`: テスト規約のパス
- `adr_dir`: ADR ディレクトリのパス
- `review_gates`: Phase ごとの review gate マッピング（レビュー観点名、または module- prefix の組み込みモジュール名）

未設定の場合はスキップし、review gate なし・ドメイン用語なしで動作する。エラー停止はしない。

### review gate 呼び出し

Phase 内で review gate を呼ぶ箇所では、flow-values.yml の `review_gates` マッピングから値を解決する。マッピングが未設定なら gate をスキップする。

- 値が `module-` prefix（例: `module-running-e2e`） → 組み込みレビューゲート。`references/<値>.md` を Read して手順に従う
- 値が上記以外 → `managing-review-sets` が利用可能ならプロファイル明示で呼び出す。利用できなければ同じ値をレビュー観点名として、利用可能な独立 reviewer に渡す。独立 reviewer も利用できない場合は既存 Phase 内でセルフレビュー結果を提示し、通常応答でユーザー承認を得る。いずれも観点・指摘・反映結果・PASS/FAIL を同じ review gate 証拠として記録する

### ルート昇格

feature-with-quick-delivery で実装中に classify 条件を違反した場合（migration 追加・UI 変更等）、即座に feature-with-full-planning に昇格し Phase 1 から再開する。refactor-with-safety-guarantee で挙動変更を発見した場合も feature-with-full-planning に昇格する。

**昇格は 1 回限り。** 昇格後は再度 feature-with-quick-delivery / refactor-with-safety-guarantee に戻ることはない。feature-with-full-planning に昇格した時点で Phase 1〜11 を完走する。

refactor-with-safety-guarantee の昇格チェック（挙動変更の発見）は Phase 7（完了チェック）の commit 直前に実施する。

### 停止点

モック承認と本番操作承認の 2 箇所のみ。それ以外でフローを止めてはならない。ルート判定・計画策定などは宣言のみ行い、待機せず次 Phase に進む。

- feature-with-full-planning: **Phase 4 のみ**（仕様確認 + 画面 UI モック承認）— 1 回のみ
- feature-with-quick-delivery: なし（全自走）
- config-with-review-and-verify: なし（全自走）
- refactor-with-safety-guarantee: なし（全自走）
- incident-with-emergency-path: **I4 のみ**（本番操作承認）— 本番環境への操作は不可逆のため例外的に停止

## 統合する手順・スキル

| Phase | 統合する手順・スキル | 適用方法 |
|---|---|---|
| Phase 1 | 構造分析（Deletion Test・深いモジュール概念） | Step 1-4 で直接適用 |
| Phase 3 | `references/module-hearing-requirements.md` | 1 問ずつ推奨回答付きで深掘りヒアリング |
| Phase 4 | `references/module-generating-explainer-yaml.md` | ヒアリング結果を直接入力として説明用 YAML（core.yaml + view.yaml）を生成 |
| Phase 4 | frontend-design（利用可能時） | 利用可能ならデザインガイドをロードする。未提供時は DESIGN.md・既存 UI・`module-creating-screen-mock.md` を使い、同じモック品質証拠を満たす |
| Phase 6 | TDD サイクル（垂直スライス・水平スライス禁止・1テスト→1実装ループ） | Step 6-2 で直接適用 |

## 完了条件

| Phase | 完了条件 |
|---|---|
| プリフライト | handoff schema が PASS。不在 flow-values.yml は WARN、既存不正 YAML は no-go |
| Phase 1 | flow-values.yml または標準値の読み込み済み。構造分析完了。ルート確定・提示済み |
| Phase 2 | worktree 内で作業している。feature ブランチが作成されている。並走 PR の競合リスクを確認済み。`.flow-progress.json` が初期化されている |
| Phase 3 | 設計ツリーの全分岐について判断が確定し、ユーザーと合意済み |
| Phase 4 | 説明用 YAML（core.yaml）が生成され、説明用 HTML がユーザーに承認されていること。UI 変更時はモック承認済み。ExitPlanMode 通過。review gate 通過（設定時） |
| Phase 5 | 全訂正・priorFailures・actionable findings が対応表で実装・検証へ対応付け済み |
| Phase 6 | 既知 FAIL の再現・回帰化後、全テスト通過。新 FAIL も対応表へ反映済み |
| Phase 7 | lint・型・テスト通過、対応表の全行が verified |
| Phase 8 | diff/review通過、commit・push済み。publication.required 時は公開同期と remote 再取得証拠あり |
| Phase 9 | PR 作成済み・CI 通過・マージ完了 |
| Phase 10 | worktree 削除済み・残留プロセスなし |
| Phase 11 | main ブランチ最新化済み |
| Phase D | ドキュメント編集完了・品質チェック（HTML 構文・リンク切れ・textlint）通過 |
| I1-I7 | 障害復旧確認済み（メトリクス正常）・修正が main にマージ済み |
| **Goal** | **選択した全 Phase と handoff の completionCriteria を満たし、publication.required 時は公開後確認まで実測済み** |

## 中断手順

ユーザーが「やめたい」「中断して」と言った場合のクリーンアップ手順は `references/integration-and-abort.md` を参照する。

## ループ設計

| 要素 | 内容 |
|---|---|
| 定期ヘルスチェック | 反復条件: ScheduleWakeup(600s), 停止条件: Phase 10 完了 |
| ルート昇格再評価 | 反復条件: classify 条件違反検出, 上限: 1 回（昇格は 1 回限り） |

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。
固有の検証行: 通過ルート・完了 Phase 数

## 予想を裏切る挙動

- ルート判定は Phase 1 で確定するが、Phase 6（TDD サイクル）の各 commit 直前に再評価される。feature-with-quick-delivery → feature-with-full-planning への昇格はここで起きうる
- Phase ファイルは着手時に Read する。事前に全 Phase を一括で読み込むとトークンを浪費する
- incident-with-emergency-path の復旧作業は I1〜I7 の独自フローで行い、完了・公開判定だけは Phase 7-8 の共通 gate へ合流する
- flow-values.yml が存在しないプロジェクトでもエラーなく動作する。gate スキップ・ドメイン用語なしがデフォルト
- managing-session-workflow（セッション管理者）はこのスキルの呼び出し側。本スキルは実装エンジンに徹し、ゴール設定・セッション管理は担わない
- JSON 整形・テキスト抽出は node -e / jq を使う。python3 -c は permissions.deny（`Bash(python3 -c*)`）により権限拒否される環境がある
- Phase 1 の調査・レビュー対象をローカル main ツリーの checkout に置くと、別セッションが origin を進めている場合に廃止済みの古い実装を照合してしまう（2026-07-17 実測: ローカル checkout の旧 Next.js 実装をレビューし、origin/main は静的 HTML へ移行済みで結果が無効化された）。調査・レビューの対象は `git fetch` 後の origin/main（または origin/main から切った worktree）の実体で確定する

## 参照資料

### Phase ファイル（references/ に格納、着手時に Read）

- `references/phase-1-route-determination.md` — 調査 + ルート判定
- `references/phase-2-branch-preparation.md` — 作業ブランチ準備
- `references/phase-3-requirements-hearing.md` — 要件ヒアリング
- `references/phase-4-prd-creation.md` — 仕様書 + 画面 UI モック作成
- `references/phase-5-implementation-plan.md` — 実装・テスト計画
- `references/phase-6-tdd-cycle.md` — TDD サイクル
- `references/phase-7-completion-checks.md` — 完了チェック
- `references/phase-8-pre-push-confirmation.md` — プッシュ前最終確認
- `references/phase-9-pr-creation-and-merge.md` — PR 作成・マージ
- `references/phase-10-post-merge-cleanup.md` — マージ後片付け
- `references/phase-11-main-sync-and-improve.md` — メイン同期・自己改善
- `references/phase-d-docs-editing.md` — ドキュメント編集
- `references/incident-flow-i1-i7.md` — インシデント独自フロー
- `references/periodic-health-check.md` — 定期ヘルスチェック（10 分ループ）の仕様
- `references/integration-and-abort.md` — 中断手順の詳細（進行状況別クリーンアップ対象）

### テンプレート・スクリプト

- `assets/flow-values.example.yml` — プロジェクト用 flow-values.yml のテンプレート
- `~/agent-home/tools/design/validate-design-md.sh` — DESIGN.md の YAML フロントマター構造を検証する CLI
- `skills/orchestrating-dev-flow/scripts/update-flow-status.sh` — ステータスラインに Phase/Step 進捗を書き込む

## 設計判断

`references/design-decisions.md` — 補助スクリプト（update-flow-status / validate-design-md）の必要性・代替案・保守責任・廃棄条件
