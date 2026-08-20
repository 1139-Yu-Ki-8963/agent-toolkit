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

2. `frontend-design` がランタイムで利用可能なら呼び出し、デザインプラン（palette / typography / layout / signature）を策定する。利用できない場合は、Step 1 で読んだ DESIGN.md・既存 UI/CSS・画面基本設計書を入力として同じ 4 観点を Phase 4 内で明文化する。スキル不在だけを理由に停止しない

3. 上記の調査結果と、利用できた場合は frontend-design の出力を踏まえて `references/module-creating-screen-mock.md` を Read して手順に従う
   - mock_type: screen
   - DESIGN.md のトークンを #screen-mock スコープに --app-* CSS 変数として注入
   - Before（現状の UI）と After（変更後の UI）の 2 パターンを生成する
   - 出力: `~/.claude/mock-archive/issue-<N>/<sha8>-mockup.html`（スキルの正規配置先）

**委任・入力**:
- frontend-design（利用可能時）または Phase 4 内の縮退策定: デザインプラン（palette / type / layout / signature）
- `references/module-creating-screen-mock.md` の手順: mock_type=screen・デザイントークン（flow-values.yml の design_system）・画面基本設計書・変更対象コンポーネントの現在の UI 構造・デザインプラン
- 期待出力: Before/After の 2 パターンを含む `~/.claude/mock-archive/issue-<N>/<sha8>-mockup.html`

**完了**: 画面 UI モック HTML が `~/.claude/mock-archive/issue-<N>/` に生成されていること（UI 変更がある場合のみ）

## Step 4-4: ポータルサーバー起動確認（説明用 HTML バンドルの提示用）

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 4 "仕様書 + 画面 UI モック作成" 4 6 "ポータルサーバー起動確認"`

説明用 HTML バンドル（`<portal_dir>/mocks/issue-<N>-spec/`）は `index.html` が `views/*.html` を相対パスで参照する複数ファイル構成のため Artifact 非対応。ポータルサーバーが起動しているか確認し、未起動なら起動する。ポートはポート管理規約に従い worktree スロットから動的に算出する。

画面 UI モック（単一ファイル、UI 変更時のみ生成）は Artifact ツールで直接公開できるため、本 Step のポータルサーバー起動は不要。

**完了**: 説明用 HTML バンドルを提示するポータルサーバーが起動していること

## Step 4-5: 計画提示・承認

Step 4-1〜4-4 で作成した成果物をレビューし、ユーザーへ提示して承認を得る。

`presenting-plan-with-artifacts` が利用可能なら呼び出す。利用できない場合は本 Phase 内で次を実行する:
- 計画と成果物を利用可能な独立 reviewer にレビューさせる。独立 reviewer が利用できなければ、plan-review / artifact-review の観点でセルフレビューする
- 指摘、反映結果、再レビューの PASS/FAIL を review gate 証拠として記録する
- Artifact、HTML ファイル、または通常応答で成果物を提示する
- 利用可能な質問 UI または通常応答でユーザー承認を得る

**完了**: 計画・成果物のレビュー証拠が揃い、ユーザー承認を得ている

## Step 4-6: プランモード突入・承認

ランタイムに plan mode がある場合は Step 4-5 の証拠を引き継いで plan mode の承認を得る。plan mode がない場合は Step 4-5 の通常応答による明示承認を最終承認として記録する。対応 hook が存在する環境では、Step 4-5 の完了証拠を検査し、未完了なら block する。

なお、画面レジストリへの specUrl/screenUrl 登録は Step 4-4（ポータルサーバー起動確認）の完了後に Phase 4 内で実施する（presenting-plan-with-artifacts には移行しない。登録は成果物の「作成」に属する工程のため）。

`review_gates.pre_impl` が flow-values.yml で設定されている場合は Step 4-5 完了後に Phase 4 内で review gate を実行する。`managing-review-sets` が利用可能なら使用し、未提供時は SKILL.md の review gate 縮退規則に従う。

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

- Step 6-1 で参照する flow-values.yml の `scripts.detect_e2e_mandate` が実在しないパスを指す場合がある（2026-07-09 実測）。その場合はローカルの layers.yml にある `e2e: true` 判定へ縮退する
- Step 4-1 の core.yaml / view.yaml を worktree 内に Write すると、dev-flow Phase ゲート（Phase 4・5 未完了時のコード書き込み block）に衝突する（2026-07-17 実測）。ゲート対象外の `~/.claude/mock-archive/<タスク名>/` に生成して代替する（worktree 内への正式配置は必須ではない。仕様の正は承認済み計画ファイルが担う）

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
