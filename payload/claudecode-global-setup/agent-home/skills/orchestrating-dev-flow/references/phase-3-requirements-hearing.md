# Phase 3: 要件ヒアリング

タスクの設計を深掘りし、共通理解に到達する。

対象ルート: 機能実装（フル計画）のみ

## Step 3-1: hearing-requirements の実行

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 3 "要件ヒアリング" 1 3 "hearing-requirements の実行"`

`references/module-hearing-requirements.md` を Read して手順に従う。引数にタスクの概要を渡す。

**入力**: `references/module-hearing-requirements.md` の手順に以下を渡す:
- 引数: タスクの概要・Phase 1 で読み込んだドメイン知識（domain_glossary / design_system）
- 期待出力: 設計ツリーの全分岐について判断確定済みリスト・未解決分岐 0 件の確認

手順が以下を実行する:
- 設計ツリーの全分岐を洗い出す
- 1 問ずつ推奨回答付きで質問する
- コードベースで答えられる質問は自分で調べる
- 依存関係を意識した順序で質問する

**完了**: hearing-requirements の手順が開始し、設計ツリーの全分岐の洗い出しと質問が開始されていること

## Step 3-2: 画面基本設計書の確認（UI 変更時）

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 3 "要件ヒアリング" 2 3 "画面基本設計書の確認"`

**スキップ**: Step 3-1 で UI 変更対象の画面が特定されなかった場合はスキップ

Step 3-1 で対象画面が特定された場合:

1. `docs/個別設計/画面/<画面名>/画面基本設計書.md` が存在するか確認
2. **存在する** → Read して既存のレイアウト・コンポーネント配置を把握。ヒアリングで「既存のどこに何を追加/変更するか」を具体的に質問できるようにする
3. **存在しない（新規画面）** → ヒアリング完了後に画面基本設計書の雛形を生成する。以下のテンプレート構造に従う:

```yaml
doc_id: "screen/<画面名>"
type: screen
status: draft
last_verified: null
verified_against: null
source_of_truth: []
authoritative_code: []
supersedes: []
related: []
```

本文: 基本情報 / 目的 / 機能概要 / レイアウト ASCII art / 項目定義 / イベント定義 / 遷移 / 権限

この雛形は Phase 4 のモック生成の入力となる。ヒアリングで確定した内容を雛形に反映してから Phase 4 に進む。

**完了**: 既存の画面基本設計書が Read されていること、または新規画面の雛形が生成されヒアリング結果が反映されていること

## Step 3-3: ヒアリング結果の確認

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 3 "要件ヒアリング" 3 3 "ヒアリング結果の確認"`

全分岐が解消されたことを確認し、次の Phase（PRD 作成）への入力としてまとめる。

**出力**: 設計ツリー全分岐の確定内容（Phase 4 Step 4-1 の PRD 作成で使用）

**完了**: 全分岐が解消され、Phase 4（PRD 作成）への入力がまとめられていること

## ループ設計

| 要素 | 定義 |
|---|---|
| 反復条件 | Step 3-1 の手順内で管理（設計ツリーの未解決分岐がある間繰り返す） |
| 上限回数 | 最大 15 問（手順内で制御） |
| 収束停止 | 未解決の分岐が 0 件 |
| 発散検知 | 同じ分岐について 3 問以上合意に至らない場合、ユーザーに打ち切りを確認 |

## 完了条件

- 設計ツリーの全分岐について判断が確定し、ユーザーの合意を得ている
- 未解決の分岐が 0 件（またはループ上限到達時にユーザーが明示的に打ち切りを選択済み）

## 次 Phase

完了条件を満たしたら `references/phase-4-prd-creation.md` を Read して実行する。

## 参照コンテキスト

### プロジェクト固有（flow-values.yml）
- `design_docs` — 設計書ディレクトリ

### グローバル規約
- no-premature-deferral-rules — 作業先送り禁止（停止点）

### グローバル hook
- check-no-deferral-stop.sh [NO-DEFERRAL-RESPONSE] — 先送り表現 block（Stop）

### 進捗管理
- 各 Step 開始時: TaskUpdate(in_progress)
- 各 Step 完了時: TaskUpdate(completed)
- Step 3-3（最後の Step）完了時: 次 Phase（Phase 4）の references を先読みし、Phase 4 の全 Step を TaskCreate
