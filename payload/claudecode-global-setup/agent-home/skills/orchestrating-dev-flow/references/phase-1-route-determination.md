# Phase 1: 調査 + ルート判定

タスク内容とコードベース構造を調査し、ルートを判定する。全ルート共通の最初の Phase。

## Step 1-1: 起動前チェック

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 1 "調査 + ルート判定" 1 6 "起動前チェック"`

`references/module-preflight-check.md` を Read して手順に従い、プロジェクトの前提条件を検証する。

- flow-values.yml が存在しない → no-go。`Skill(creating-new-project)` によるセットアップを案内
- flow-values.yml が存在するが YAML パースエラー → no-go。構文エラーを報告
- go → 次 Step に進む

**入力**: `references/module-preflight-check.md` の手順に以下を渡す:
- 引数: なし（incident ルートの場合は mode: minimal）
- 期待出力: go / no-go

**完了**: 起動前チェックが go を返していること

## Step 1-2: コンテキスト読み込み

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 1 "調査 + ルート判定" 2 6 "コンテキスト読み込み"`

`.claude/rules/always/project-context/flow-values.yml` を Read し、全セクションを取得する。起動前チェックは別スキル（別コンテキスト）のため内容は引き継がれない。ここで読み込んだ内容を Step 1-5 のルート判定と以降の Phase で使用する。

取得対象:
- `classify` — ルート判定閾値（quick_max_files / quick_excludes）
- `context_a` — プロジェクト基本情報（architecture / project_index / techstack / project_overview / environments / domain_glossary / ui_terminology / game_constraints / coding_standards / master_tables）
- `context_b` — 開発規約（design_rules / test_rules）

context_b で指定されたファイルを Read する:
- `domain_glossary` — ドメイン用語辞書（PRD・コミット・PR で使う用語）
- `design_system` — デザイン規約（UI 実装時の制約）
- `test_conventions` — テスト規約（テスト作成時の方針）
- `adr_dir` — タスクに関連する ADR を確認する（矛盾する実装方針は取らない）

**スキップ**: flow-values.yml が存在しない場合はデフォルト値で代替し、context_b ファイルの Read はスキップする

**出力**: classify セクション（Step 1-5 のルート判定で使用）・ドメイン知識・設計規約・テスト規約

**完了**: flow-values.yml の全セクションが読み込まれていること（ファイルが存在しない場合はデフォルト値で代替されていること）

## Step 1-3: タスク内容の確認

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 1 "調査 + ルート判定" 3 6 "タスク内容の確認"`

ユーザーの依頼内容を確認し、以下の分類軸で評価する:

- 挙動変更を伴うか（新機能・バグ修正）
- アプリコードを変更するか
- 緊急復旧が必要か（本番障害）
- lint・リファクタのみか

**完了**: タスクを 4 つの分類軸（挙動変更・アプリコード変更・緊急性・lint 系）で評価されていること

## Step 1-4: 構造分析

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 1 "調査 + ルート判定" 4 6 "構造分析"`

**スキップ**: incident-with-emergency-path・config-with-review-and-verify・feature-with-quick-delivery ルートでは構造分析をスキップする。ただしルートは Step 1-5 で確定するため、タスク内容の確認（Step 1-3）でスキップ可能と判断できる場合のみ省略する

タスクの概要と関連ディレクトリを対象に、以下の構造分析を直接実行する:

1. **Deletion Test**: 「このモジュール／ファイルを削除したら、どれだけの呼び出し元が壊れるか」を関連ディレクトリごとに評価する。壊れる箇所が広範囲に及ぶものほど責務が過剰に集中している可能性が高い
2. **深いモジュール概念の適用**: インターフェースが単純な割に内部実装の複雑さ・価値を多く隠蔽しているモジュール（深いモジュール）を優先し、インターフェースの割に実装が薄い「浅いモジュール」候補を洗い出す
3. 洗い出した浅いモジュール候補について、Deletion Test の結果とあわせて推奨強度（Strong / Worth exploring）を判定する

候補リスト（浅いモジュール・Deletion Test 結果・推奨強度）をユーザーに提示する。

また、上記の構造分析結果から prefactoring（実装前リファクタ）が必要かをユーザーと合意する:
- Strong 候補がある場合: 実装前にリファクタを推奨
- Worth exploring 以下のみの場合: 実装後の検討に回してよい

**完了**: 構造分析の候補リストがユーザーに提示され、prefactoring の要否が確定していること（スキップ可能なルートの場合はスキップ済みであること）

## Step 1-5: ルート判定

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 1 "調査 + ルート判定" 5 6 "ルート判定"`

以下の条件分岐で 1 つのルートに確定する:

```
Q1: P0 障害（本番ダウン・データ消失等）の緊急復旧か？
    YES → incident-with-emergency-path（references/incident-flow-i1-i7.md に分岐）
    NO  → Q2

Q2: アプリコードを一切変えない編集のみか？
    （docs / .claude/skills / .claude/rules / .claude/agents / tools/hooks / tools/linter 等）
    YES → config-with-review-and-verify
    NO  → Q3

Q3: 挙動変更を伴わない lint・deps 更新・純粋リファクタか？
    YES → refactor-with-safety-guarantee
    NO  → Q4

Q4: 以下の全条件を満たすか？
    - 変更ファイル ≤ classify.quick_max_files（デフォルト: 2）
    - classify.quick_excludes に該当しない
    YES → feature-with-quick-delivery
    NO  → feature-with-full-planning
```

**入力**: Step 1-2 の classify セクション（quick_max_files・quick_excludes 等の閾値）・Step 1-4 の構造分析結果

`.claude/rules/always/project-context/flow-values.yml` が存在すれば `classify` セクションの閾値を使う。未設定ならデフォルト値で判定する。

**完了**: 条件分岐によりルートが 5 つのいずれか 1 つに確定していること

## Step 1-6: ルート宣言

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 1 "調査 + ルート判定" 6 6 "ルート宣言"`

判定結果をユーザーに宣言し、**待機せず Phase 2 に進む**:

「ルート判定: 本タスクは **[識別子]** で進めます」

ユーザーが途中でルート変更を指示した場合はその時点で切り替える。ここで確認待ちをしてはならない。

**完了**: ルートが宣言され、Phase 2 に進んでいること

## 完了条件

- ルートが 5 つのいずれか 1 つに確定している
- ルートが宣言されている（承認待ちではない）

## 次 Phase

ルートに応じて次 Phase が異なる:
- **feature-with-full-planning / feature-with-quick-delivery / refactor-with-safety-guarantee**: `references/phase-2-branch-preparation.md` を Read して実行
- **config-with-review-and-verify**: `references/phase-2-branch-preparation.md` を Read して実行（Phase 3-5 はスキップし Phase D に直行）
- **incident-with-emergency-path**: `references/phase-2-branch-preparation.md` を Read して実行（Phase 2 完了後に `references/incident-flow-i1-i7.md` に分岐）

## 参照コンテキスト

### プロジェクト固有（flow-values.yml）
- `context_a` 全体 — 地図と語彙（architecture / project_index / techstack / project_overview / environments / domain_glossary / ui_terminology / game_constraints / coding_standards / master_tables）
- `context_b` 全体 — 規約・制約（design_rules / test_rules）
- `scripts.flow_classify` — ルート判定スクリプト
- `classify` — ルート判定閾値（quick_max_files / quick_excludes）

### グローバル規約
- subagent-delegation-rules — Agent 委任判定

### グローバル hook
- suggest-subagent.sh [SUBAGENT-DELEGATION-HINT] — 委任提案（notify）

### 進捗管理
- Phase 1 開始時: SKILL.md の Phase テーブルから Phase 1 の全 Step を TaskCreate
- 各 Step 開始時: TaskUpdate(in_progress)
- 各 Step 完了時: TaskUpdate(completed)
- Step 1-6（最後の Step）完了時: Phase 2 の references を先読みし、Phase 2 の全 Step を TaskCreate
