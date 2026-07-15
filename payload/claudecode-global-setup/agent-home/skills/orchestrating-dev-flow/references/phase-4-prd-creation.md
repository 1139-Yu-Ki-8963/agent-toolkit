# Phase 4: 仕様書 + 画面 UI モック作成

Phase 3 のヒアリング結果を説明用 YAML に変換し、説明用 HTML と画面 UI モックを生成してユーザーの承認を得る。

対象ルート: 機能実装（フル計画）のみ

## Step 4-1: 説明用 YAML 生成

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 4 "仕様書 + 画面 UI モック作成" 1 6 "説明用 YAML 生成"`

**入力**: Phase 3 のヒアリング結果（設計ツリー全分岐の確定内容）

`references/module-generating-explainer-yaml.md` を Read して手順に従う。

**入力**: `references/module-generating-explainer-yaml.md` の手順に以下を渡す:
- 引数: Phase 3 のヒアリング結果・画面基本設計書（存在する場合）
- 前処理指示: 課題→解決策→ユーザーストーリー→判断→テスト→スコープ外の構造でコンテンツを整理する
- audience.role: engineer
- 期待出力: core.yaml（意味構造）+ view.yaml（表示戦略）

**完了**: core.yaml と view.yaml が生成されていること

**保存先**: core.yaml と view.yaml は worktree 内に保存する（使い捨て）。worktree 削除時に自動消滅する。説明用 HTML は `<portal_dir>/mocks/` にコミットされ永続化される。画面 UI モックは `~/.claude/mock-archive/` に直接出力される。

## Step 4-1b: 画面設計ドキュメント作成（UI 変更時）

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 4 "仕様書 + 画面 UI モック作成" 1 6 "画面設計ドキュメント作成"`

**スキップ**: UI 変更がない場合、または新規画面追加でない場合はスキップ

flow-values.yml の `screen_docs` セクションを参照し、画面ドキュメント **4 ファイルセット**（画面基本設計書・DESIGN.md・単体テスト観点表・結合テスト観点表）のうち Phase 4 で作成する 2 ファイル（画面基本設計書・DESIGN.md。観点表 2 枚は Phase 5 で起票する）を処理する。

1. **画面基本設計書.md の作成/更新**
   - 配置先: `<screen_docs.base_dir>/<画面名>/画面基本設計書.md`
   - 新規画面の場合: プロジェクト内のテンプレート（flow-values の screen_docs 定義）を優先し、未整備の場合は正本 `~/agent-home/templates/project-docs/02_画面基本設計/` から 4 ファイルを複製して骨格を作成する
   - 既存画面の場合: 変更内容に応じてセクションを更新
   - 必須セクション: YAML フロントマター + 基本情報 + 目的 + 機能概要 + レイアウト

2. **DESIGN.md の作成/更新**
   - 配置先: `<screen_docs.base_dir>/<画面名>/DESIGN.md`
   - `validate-design-md.sh` で構造検証する
   - 必須セクション: YAML フロントマター（doc_id, type: design, status, target_screen）+ デザイントークン + コンポーネント構成 + レスポンシブ仕様 + アクセシビリティ

**入力**: flow-values.yml の `screen_docs`（未設定の場合はスキップ）

**完了**: 画面基本設計書.md が必須 4 セクションを含み、DESIGN.md が validate-design-md.sh を PASS していること

## Step 4-2: 説明用 HTML 生成

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 4 "仕様書 + 画面 UI モック作成" 2 6 "説明用 HTML 生成"`

core.yaml + view.yaml をもとに、ロジック・構造・フロー図・依存関係を説明する HTML バンドルを生成する。

1. `references/module-generating-explainer-html.md` を Read して手順に従う
   - 入力: Step 4-1 で生成した core.yaml + view.yaml
   - 出力: `<portal_dir>/mocks/issue-<N>-spec/` にバンドル生成

**入力**: `references/module-generating-explainer-html.md` の手順に以下を渡す:
- 引数: core.yaml + view.yaml（Step 4-1 の出力）
- 期待出力: `<portal_dir>/mocks/issue-<N>-spec/` に生成された HTML バンドル

**完了**: 説明用 HTML バンドルが `<portal_dir>/mocks/issue-<N>-spec/` に生成されていること

## Step 4-3: 画面 UI モック生成（UI 変更がある場合のみ）

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 4 "仕様書 + 画面 UI モック作成" 3 6 "画面 UI モック生成"`

**スキップ**: UI 変更がない場合はスキップ

1. 以下のコンテキストを Read（モック生成前の調査）:
   - 変更対象の画面コンポーネント（.tsx / .vue 等）→ 現在の UI 構造を把握する
   - 関連する CSS / スタイルファイル → 現在のデザインを把握する
   - flow-values.yml の design_system → デザイントークン
   - 画面基本設計書 → 既存画面の構造（Phase 3 で生成した雛形がある場合はそれを Read する）
   - style.css → portal 共通 CSS 変数

2. Skill("frontend-design") を呼び出してデザインガイドをロードする
   - 新規画面・コンポーネント作成時: デザインプランの策定（palette / typography / layout / signature）に使う
   - 既存画面の改善・刷新時: 現状の UI 構造を踏まえた改善方針の策定に使う
   - デザインルールの読み込みだけでは不十分。作成・改善の意思決定には必ず本スキルを経由する

3. 上記の調査結果と frontend-design のガイドを踏まえて `references/module-creating-screen-mock.md` を Read して手順に従う
   - mock_type: screen
   - DESIGN.md のトークンを #screen-mock スコープに --app-* CSS 変数として注入
   - Before（現状の UI）と After（変更後の UI）の 2 パターンを生成する
   - 出力: `~/.claude/mock-archive/issue-<N>/<sha8>-mockup.html`（スキルの正規配置先）

**委任・入力**:
- Skill("frontend-design"): デザインプラン策定（palette / type / layout / signature）。出力をモック生成の入力として使う
- `references/module-creating-screen-mock.md` の手順: mock_type=screen・デザイントークン（flow-values.yml の design_system）・画面基本設計書・変更対象コンポーネントの現在の UI 構造・frontend-design の出力
- 期待出力: Before/After の 2 パターンを含む `~/.claude/mock-archive/issue-<N>/<sha8>-mockup.html`

**完了**: 画面 UI モック HTML が `~/.claude/mock-archive/issue-<N>/` に生成されていること（UI 変更がある場合のみ）

## Step 4-4: ポータルサーバー起動確認（説明用 HTML バンドルの提示用）

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 4 "仕様書 + 画面 UI モック作成" 4 6 "ポータルサーバー起動確認"`

説明用 HTML バンドル（`<portal_dir>/mocks/issue-<N>-spec/`）は `index.html` が `views/*.html` を相対パスで参照する複数ファイル構成のため Artifact 非対応。ポータルサーバーが起動しているか確認し、未起動なら起動する。ポートはポート管理規約に従い worktree スロットから動的に算出する。

画面 UI モック（単一ファイル、UI 変更時のみ生成）は Artifact ツールで直接公開できるため、本 Step のポータルサーバー起動は不要。

**完了**: 説明用 HTML バンドルを提示するポータルサーバーが起動していること

## Step 4-5: 仕様確認 + 画面 UI モック承認

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 4 "仕様書 + 画面 UI モック作成" 5 6 "仕様確認 + 画面 UI モック承認"`

1. 生成した成果物をユーザーに提示可能な形にする
   - 説明用 HTML バンドル（`<portal_dir>/mocks/issue-<N>-spec/index.html`）は複数ファイル構成のため Artifact 非対応。Step 4-4 で起動したポータルサーバー経由の URL を使う
   - UI 変更ありの場合は画面 UI モック（`~/.claude/mock-archive/issue-<N>/<sha8>-mockup.html`）を `references/module-creating-screen-mock.md` の手順に従い Artifact として公開する（単一ファイルのため対応可能）

2. URL をユーザーに提示する
   - チャットに定型文で表示:

     「以下を確認してください:
       説明資料: <ポータルサーバー URL>（ロジック・構造・依存関係）
       画面モック: <Artifact URL>（Before/After の視覚表現）← UI 変更時のみ」

3. AskUserQuestion で承認を得る（2 問同時）

   質問 1（単一選択）:
   header: "承認判定"
   question: "仕様（説明用 HTML）と画面 UI モックを確認しましたか？"
   options:
     A) 承認して実装に進む
     B) 修正が必要（チャットで指示）

   質問 2（multiSelect: true）:
   header: "ビュー追加"
   question: "追加したいビューがあれば選んでください"
   options:
     A) 追加不要
     B) テーブル形式（概念・重要度・難易度の一覧）
     C) フロー図（処理の流れ・依存関係）

4. 分岐

   | 質問 1 | 質問 2 | 動作 |
   |---|---|---|
   | 承認 | 追加不要 | Step 4-6 へ |
   | 承認 | ビュー選択あり | ビューを一括生成 → ポータルサーバー経由で再公開 → Step 4-5 に戻る |
   | 修正が必要 | — | 修正 → 該当する成果物を再公開（説明用 HTML バンドルはポータルサーバー、画面 UI モックは Artifact）→ Step 4-5 に戻る |

**完了**: 説明用 HTML バンドルと画面 UI モック（UI 変更時）が生成されていて、ユーザーが「承認」+「追加不要」を選択していること

## Step 4-6: 承認 + 後処理

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 4 "仕様書 + 画面 UI モック作成" 6 6 "承認 + 後処理"`

1. EnterPlanMode → ExitPlanMode（フルルートの唯一の停止点）
2. 画面レジストリへ specUrl / screenUrl を登録（内部処理）: `<portal_dir>/data/mocks.js` に `type: screen` のエントリとして screenUrl + specUrl を追記する（oradora-battle-base の正本レジストリは `project-portal/data/mocks.js`）。このレジストリが無いプロジェクトでは、flow-values.yml の portal_dir 配下から specUrl / screenUrl フィールドを持つ実在レジストリを既存エントリ（先例）の grep で特定してから追記する
3. flow-values.yml の review_gates.pre_impl が設定されていれば review gate を Skill 呼び出し

**スキップ（項目 3）**: review_gates.pre_impl が未設定の場合は Skill 呼び出し（項目 3）をスキップ

**委任（項目 3）**: review_gates.pre_impl に指定された Skill に以下を渡す:
- 引数: 承認済みの説明用 YAML（core.yaml）とモック URL
- 期待出力: 仕様承認（PASS）または差し戻し理由（FAIL）
- プロジェクトに `docs/設計書レビュー観点.md` が存在する場合、その §3 観点表を合否基準として使う

**完了**: ExitPlanMode によるユーザー承認が得られ、review gate を通過していること（設定されている場合）

## 順序保証

Step 4-5 のモック承認は EnterPlanMode（Step 4-6）より必ず前。EnterPlanMode 後はファイル編集がブロックされるため、モック修正ができなくなる。

## ループ設計

| 要素 | 定義 |
|---|---|
| 反復条件 | Step 4-5 で「修正が必要」またはビュー追加が選択された場合に Step 4-5 に戻る |
| 上限回数 | 最大 5 回 |
| 収束停止 | Step 4-5 で「承認」+「追加不要」が選択された |
| 発散検知 | 3 回連続で「修正が必要」が選択された場合、Phase 3 に差し戻して要件を再ヒアリング |

## 予想を裏切る挙動

- Step 6-1 で参照する flow-values.yml の `scripts.detect_e2e_mandate` が実在しないパスを指す場合がある（2026-07-09 実測）。その場合は module-reviewing-pre-impl Step 1.5 と同じ layers.yml の `e2e: true` 判定に代替する

## 完了条件

- 説明用 YAML（core.yaml + view.yaml）が生成されている
- 説明用 HTML バンドルが生成済み
- UI 変更時は画面 UI モックが生成済み（説明用 HTML とは別ファイル）
- ユーザーの承認（ExitPlanMode）を得ている
- review gate を通過している（設定されている場合）

## 次 Phase

完了条件を満たしたら `references/phase-5-implementation-plan.md` を Read して実行する。

## 参照コンテキスト

### プロジェクト固有（flow-values.yml）
- `review_gates.pre_impl` — 仕様承認ゲート
- `scripts.design_compliance` — デザイン準拠チェックスクリプト
- `screen_docs` — 画面ドキュメント 4 ファイルセット定義（base_dir / files_per_screen / lifecycle_rule）

### グローバル規約
- file-guard-rules — ファイル配置ガード
- no-premature-deferral-rules — 作業先送り禁止

### グローバル hook
- check-main-agent-direct-work.sh [MAIN-AGENT-DIRECT-WORK-BLOCK] — メイン直接作業 block（PreToolUse）
- check-playwright-filename.sh [FILE-PLACEMENT-BLOCK] — スクリーンショットファイル配置 block（PreToolUse）

### フロー専用 hook
- check-review-gate.sh [REVIEW-GATE-BLOCK] — review gate 未通過 block（advisory）

### 進捗管理
- 各 Step 開始時: TaskUpdate(in_progress)
- 各 Step 完了時: TaskUpdate(completed)
- Step 4-6（最後の Step）完了時: 次 Phase（Phase 5）の references を先読みし、Phase 5 の全 Step を TaskCreate
