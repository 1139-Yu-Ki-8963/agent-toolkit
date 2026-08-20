---
name: managing-session-workflow
description: |
  毎ターン目的・完了条件・制約・引き継ぎを再評価する。
  TRIGGER when: SessionStart時、ユーザーの新規・追加・訂正・置換・質問を受けた時。
  SKIP: なし。毎ユーザーターンで実行する。
invocation: managing-session-workflow
type: orchestration
allowed-tools: [Read, Bash, Grep, Glob, Skill, Agent, Workflow, AskUserQuestion, TaskCreate, TaskUpdate]
execution: main-session
---

# セッションワークフロー管理

毎ユーザーターンで目的と到達状態を再評価し、専門 Skill への引き継ぎと実測証拠に基づく最終完了判定を管理する。

## 責務: セッションの進行係

本スキルの職務は進行係であり、以下に限定する。実装・詳細調査・文字起こし・テスト自体は専門 Skill または実行担当へ委任する。

| 責務 | 内容 |
|---|---|
| purpose | ユーザーが解決したい目的を正規化する |
| Goal | ユーザーが明示的に依頼した場合のみシステム Goal を作成・更新する |
| completionCriteria | 測定可能な完了条件を保持する |
| constraints | 作業範囲・禁止事項・公開条件を保持する |
| routing | 実行を専門 Skill・サブエージェント・Workflow へ委任する |
| handoff | 共通引き継ぎ契約を後続 Skill に渡す |
| tracking | ユーザー訂正と証拠を全体追跡する |
| final | 実測証拠と完了条件を照合し、最終完了を判定する |

### 毎ターンの締め義務

応答の末尾は必ず次のいずれかで終える。単なる報告・解説で終えることを禁止する。

- (a) 次の一手の提案: 「次は <具体的な行動> を実行しましょうか？」
- (b) ユーザーにしか決められない質問（選択肢付き）
- (c) 完了宣言 + 「他に対応すべきことはありますか？」

違反例: 「〜を修正しました。」で終わる／状況説明だけで終わる／選択肢を並べて推奨を示さない

## 設計思想

- 管理者の本質は「ゴール → 道筋 → 実行 → 検証」のサイクルを司ること
- **提案先行**: ユーザーの指示を待つ受け身の進行を禁止する。依頼とコンテキストから管理者が先に道筋を提案し、合意を得てから実行する。後手の逐語実行は管理者の職務放棄とみなす
- 既存スキルへのルーティングは管理者の仕事の一部であり、全体ではない
- 誘導（本スキル）+ 防御（hook）の二重構造。hook を置き換えない
- セッション自体を管理単位として扱う

## 毎ターン再評価

UserPromptSubmit で本 Skill の全文コンテキストを受け取るたびに、直近のユーザー発話を分類する。

| 分類 | 動作 |
|---|---|
| 新規 | purpose と handoff を作成する |
| 追加 | completionCriteria・constraints・inputs を追記する |
| 訂正 | userCorrections に原文と置換先を記録し、影響する handoff を再生成する |
| 置換 | 古い条件を失効扱いにして新しい条件を正本化する |
| 質問 | Goal を変更せず、必要な証拠だけを取得して回答する |

追加・訂正・置換を SessionStart 限定の判定で無視してはならない。後続 Skill が実行中でも、最新版の共通引き継ぎ契約を再提示する。

## ランタイム別ツールアダプタ

実在し利用可能なツールだけを選ぶ。表のツールが現在の環境に無い場合は、同じ行に記載した代替へ縮退する。

| 用途 | Claude Code | Codex |
|---|---|---|
| Goal 状態確認・更新 | 利用可能な `/goal` | `get_goal` / `create_goal` / `update_goal` |
| ユーザー確認 | `AskUserQuestion` | `request_user_input` が利用可能なら使用し、無ければ通常応答 |
| Skill 実行 | `Skill` | 対象 `SKILL.md` を全文読み、その手順を実行 |
| サブエージェント | `Agent` | `spawn_agent` |

Goal の作成は、ユーザーが Goal 化を明示的に選択・依頼した場合だけ行う。通常のタスク受理だけを根拠に `/goal` や `create_goal` を呼ばない。Goal は目的と最終到達状態を保持し、詳細条件は共通引き継ぎ契約で補う。

## 共通引き継ぎ契約

後続 Skill へ渡す YAML または同型 JSON は、次の必須キーをすべて持つ。空値が許される場合もキー自体は省略しない。

```yaml
goal: "ユーザーが明示した最終到達状態。Goal 化していない場合は null"
purpose: "解決したい目的"
completionCriteria: []
constraints: []
userCorrections: []
inputs: []
publication:
  required: false
  target: null
  verification: null
```

`userCorrections` は `sourceId`・`original`（訂正原文）・`normalized`（正規化後内容）・`target`（反映先）を保持し、訂正のたびに影響する completionCriteria・constraints・inputs・publication を再生成する。`inputs` は画像・調査報告・priorFailures・既存成果物、`publication` は commit・push・公開先同期・公開後確認の要否と証拠条件を保持する。口頭要約だけで委任せず、この契約をそのまま後続 Skill の入力へ含める。

## 画像指摘後の範囲確認

`transcribing-images` から `actionable: true` の指摘を受けた場合、ユーザーが最初から実装・公開範囲を明示していなければ次の順で 2 段階確認する。

1. 指摘を調査・実装まで進めるか: **進める（推奨）** / 文字起こしのみ
2. どこまでを Goal にするか: **実装・回帰テスト・レビュー・commit・push・agent-toolkit 公開・公開後確認まで（推奨）** / ローカル検証まで

最初の依頼に実装や公開後確認まで含まれている場合は、同じ質問を重ねない。2 段階目の「公開確認まで」と「ローカル検証まで」は、どちらもユーザーが最終到達状態を明示した Goal 範囲選択として扱う。1 段階目で「文字起こしのみ」を選んだ場合は Goal 作成の明示選択として扱わない。

確認結果は actionable 画像 input の `scopeConfirmation.investigationAndImplementation` に `proceed` / `transcription-only`、`scopeConfirmation.goalScope` に `publication` / `local` を記録してから共通 handoff を再生成する。`proceed` なのに第2確認が無い input、または `transcription-only` の input を実装フローへ渡してはならない。

`proceed` の後続は、利用可能な専門 Skill があれば共通 handoff を渡して起動する。該当 Skill が存在しない場合は、利用可能な標準 reviewer・実行担当、または通常応答へ縮退し、同じ completionCriteria と証拠条件を渡す。画像文字起こしの完了を、特定 Skill の存在や起動に依存させない。

## 進行宣言（PHASE-STEP-TASK ゲートとの結線）

縮退判定で非縮退となった全タスクで、本スキルの Phase / Step 進行を機械強制の観測点に載せる。`update-flow-status.sh` を呼ばないフローには phase 突入ゲート（`~/.claude/rules/always/gate/phase-step-task/rule.md`）が発火しないため、セッション管理者が進行宣言の起点となることで観測点をセッション横断で保証する。

1. **Step タスクの事前登録**: 各 Phase 突入前に、当該 Phase の全 Step を TaskCreate で登録する。subject は規約形式 `Phase <N> Step <N>-<M>: <完了判定可能な動詞句>` とする
2. **進行宣言**: Phase 開始時と Step 完了ごとに以下を実行する:

```bash
bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh <phase_num> "<phase名>" <current_step> <total_steps> "<step名>"
```

3. **グラフ実行時**: Phase 3 でグラフのノードを実行する場合、各ノードを Step としてタスク登録してから実行する
4. **委任先スキルが独自の進行宣言を持つ場合**（orchestrating-dev-flow 等）: 委任した時点で進行宣言の主体を委任先に引き継ぐ（二重宣言しない）
5. **縮退モードは対象外**: 1 手で完了するタスクに Phase 構造はないため、進行宣言・タスク登録とも不要

`update-flow-status.sh` は `.flow-progress.json` が無い環境では statusline 用の書き出しのみを行い Phase 順序検証をスキップするため、どのセッション・どのリポジトリでも安全に呼べる。

## Phase 1: ゴール設定

### Step 1-1: 縮退判定

軽量タスクにグラフ設計のフルコースを適用しない。以下を**すべて**満たす場合は縮退モードとする:

- ユーザーの依頼が単文で、対象が明示されている（例: 「このファイルの typo を直して」）
- 設計判断を伴わない（新規機能・アーキテクチャ変更でない）
- 編集対象が 2 ファイル以内に収まる見込み（3 ファイル以上は PLAN-BEFORE-BULK-EDIT hook が機械的に block する。見込みが曖昧なら縮退にしない）
- 完了条件が自明（修正の適用そのもの）

縮退モードの動作:
- 「〜を修正します」と 1 文で宣言し、Step 1-2 以降と Phase 2 をスキップして直接実行する
- 実行と完了確認のみ行い、完了報告も 3 行以内に収める

縮退に該当しない場合は Step 1-2 に進む。

### Step 1-2: ゴールの確認

ユーザーに「このセッションで何を達成したいか」を確認する。確認は受け身の質問ではなく提案で行う: 依頼内容とセッションコンテキスト（渡された資料・直前の作業・プロジェクト状態）から推奨ゴールと道筋を組み立て、「〜という理解です。<調査 → 計画 → レビュー → 成果物提示> の流れで進めましょうか？」と管理者側から先に提示する。

- ユーザーが明確なゴールを持っている場合: そのまま採用する
- 曖昧な場合: AskUserQuestion で具体化する
  - 「バグ修正」→「どの画面の、何が、どうなれば完了か」
  - 「機能追加」→「何が動けば完了か、どこまでやるか」
- 前回セッションの続きの場合: skill-log と git status から状態を復元し、「前回の続きから再開しますか？」と確認する
- ユーザーの依頼がない起動（払い出しセッション）の場合: `node ~/agent-home/tools/harness/scripts/task-board.mjs next` で pending タスクを取得し、`claim` してゴールとして所有する。ボードが空なら「ボードに pending タスクはありません」と報告して終了する

### Step 1-3: 完了条件の明文化

ゴールに対する完了条件を明文化し、ランタイムで利用可能な確認 UI を使ってユーザーと合意する。

完了条件の例:
- テストが全件通過する
- 特定の画面が指定通り動作する
- Pull Request がレビュー可能な状態になる
- 設計書が完成し、レビューを通過する

曖昧な完了条件（「いい感じにする」「改善する」）は許可しない。測定可能な条件に具体化する。

**完了**: ゴールと完了条件がユーザーと合意されている

## Phase 2: グラフ設計

### Step 2-1: ループ型の判定

ゴールの性質から適切なループ型を判定する。

| ループ型 | 判定条件 | 終了条件 |
|---|---|---|
| ゴールベース | テスト合格・バグ修正・機能実装など完了条件が明確 | 完了条件を満たす、または試行上限到達 |
| ターンベース | 探索的な質問・設計相談・調査など終点が不明確 | ユーザーが「ここまで」と判断 |
| タイムベース | 定期チェック・CI 監視・定期レポート | キャンセルまたは自然終了 |
| プロアクティブ | イベント駆動・Pull Request 監視・通知対応 | 常時実行 |

### Step 2-2: 既存スキルの検索

ユーザーのゴールに対して、利用可能なスキル一覧を走査する。

- 該当スキルがある場合: 「このスキルで対応できます」と提示し、ユーザーの合意を得て Skill() で起動する
- 該当スキルがない場合: 「該当スキルなし。直接対応します」と判断し、Step 2-3 に進む

走査対象: スキル一覧の description（TRIGGER when / SKIP 節）を照合する。

### Step 2-3: グラフ複雑度の判定

ゴールの性質からグラフの複雑度を判定する。

| 複雑度 | 判定条件 | 実行方式 |
|---|---|---|
| 単純 | 1 スキルまたは 1 エージェントで完結。チェッカー不要 | Skill() 直接委任 |
| 中程度 | 複数 step の直列実行。各 step にチェッカー | Workflow の pipeline |
| 複雑 | 並列ブランチ・複数チェッカー・動的分岐 | Workflow の parallel + pipeline |

判定基準:
- step 数が 1 → 単純
- step 数が 2〜5 で依存関係が直列 → 中程度
- step 数が 3 以上で並列実行可能な独立 step がある、または複数のチェッカーが必要 → 複雑

### Step 2-4: グラフのノードとエッジ設計

複雑度に応じてグラフ（ノード・エッジ・完了シグナル）を設計する。

**ノード（誰が何をするか）**:

| 役割 | Claude Code | Codex |
|---|---|---|
| プランナー | brain | 利用可能な計画系定義、無ければ spawn_agent 既定 |
| リサーチャー | researcher / investigator | 利用可能な調査系定義、無ければ spawn_agent 既定 |
| ビルダー | worker-sonnet | 利用可能な実装系定義、無ければ spawn_agent 既定 |
| 実行者 | worker-haiku | 利用可能な軽量実行系定義、無ければ spawn_agent 既定 |
| チェッカー | 各 reviewer | 利用可能な判定系定義、無ければ spawn_agent 既定 |
| 懐疑者 | adversarial-verifier | 利用可能な反証系定義、無ければ spawn_agent 既定 |

**エッジ（誰から誰へ何を渡すか）**:

- プランナー → ビルダー: 作業指示（確定済み内容をベタ書き）
- リサーチャー → 共有状態: 証拠を書き込み
- ビルダー → チェッカー: 成果物を渡してレビュー
- チェッカー → ビルダー: FAIL 時に差し戻し（修正指示付き）
- チェッカー → 共有状態: 判定結果を書き込み

共有状態は Workflow ツールの pipeline/parallel の戻り値で受け渡す。

**スキル推奨パターン**:

| ゴールの性質 | 推奨スキル |
|---|---|
| 新機能追加・バグ修正・リファクタ | orchestrating-dev-flow |
| スキル・ルール・hook の作成・修正 | managing-agent-configs |
| 既存成果物のレビュー | managing-review-sets |
| 新規プロジェクトセットアップ | creating-new-project |
| issue 作成・着手 | managing-github-operations |
| 繰り返し作業の自動化 | managing-agent-configs（hook・スキル化を推奨） |
| 単純な質問・小規模修正 | フロー不要。直接対応 |

### Step 2-5: 完了シグナルの設定

Phase 1 で合意した完了条件に加え、以下の機械的シグナルを設定する。完了はエージェントの自己申告に依存しない。シグナルによる機械判定を優先する。

| シグナル | 用途 |
|---|---|
| テスト通過 | コード変更の完了判定 |
| チェッカー全員が PASS | レビュー完了の判定 |
| 予算上限到達 | Workflow の budget.remaining() で制御 |
| 進捗なし検出 | 同じエラーが 2 回連続で差し戻された場合にループ停止 |
| 試行上限 | maker-checker ループの最大回数（デフォルト 3 回） |

### Step 2-6: 自動化の推奨

ユーザーのゴールや発言が以下に該当する場合、Skill("managing-agent-configs") でのスキル・hook 化を積極的に推奨する。

- 「毎回同じ手順を踏んでいる」「繰り返しやっている」と言及している
- 「自動化したい」「勝手にやってほしい」と要望している
- セッションログ分析で同じ指摘が複数回検出されている
- 手順の標準化・品質チェックの自動化に該当する

推奨時の説明: 「この作業は hook で自動化できます。Skill("managing-agent-configs") で作成しましょうか？」

### Step 2-7: グラフの提示

設計したグラフをユーザーに提示し、ランタイムで利用可能な確認 UI を使って合意を得る。**Phase 3 の実行は本 Step の合意を得るまで開始しない**（提案なしの実行開始は提案先行原則への違反）。提示内容:
- ループ型
- グラフ複雑度（単純 / 中程度 / 複雑）
- ノード一覧と各ノードの役割
- エッジ（データフロー）
- 完了シグナル

**完了**: ループ型・グラフ・完了シグナルがユーザーと合意されている

## Phase 3: グラフ実行

### Step 3-1: グラフの実行

複雑度に応じた方式でグラフを実行する。

**単純（Skill 直接委任）**:

Skill() で該当スキルを起動し、完了を待つ。

**中程度（Workflow pipeline）**:

Workflow ツールで pipeline を構成する。各 step を maker → checker の順で直列実行する。checker が FAIL を返したら maker に差し戻す。

```javascript
pipeline(steps,
  step => agent(maker_prompt(step), {label: `build:${step.name}`, schema: OUTPUT_SCHEMA}),
  (result, step) => agent(checker_prompt(result), {label: `review:${step.name}`, schema: VERDICT_SCHEMA})
    .then(v => v.pass ? result : {...result, rework: v.findings})
)
```

**複雑（Workflow parallel + pipeline）**:

並列ブランチ・複数チェッカー・動的分岐を組み合わせる。

```javascript
phase('Research')
const evidence = await parallel(sources.map(s => () =>
  agent(research_prompt(s), {label: `research:${s.name}`, schema: EVIDENCE_SCHEMA})))

phase('Build')
const output = await agent(build_prompt(evidence.filter(Boolean)), {schema: OUTPUT_SCHEMA})

phase('Review')
const reviews = await parallel(reviewers.map(r => () =>
  agent(review_prompt(output, r), {label: `review:${r.name}`, schema: VERDICT_SCHEMA})))

const confirmed = reviews.filter(Boolean).every(r => r.pass)
```

### Step 3-2: 動的グラフ変異

実行中の結果に基づいてグラフを書き換える。

| 条件 | 変異 |
|---|---|
| チェッカーの信頼度が低い | レビュアーを追加（adversarial-verifier で多角的検証） |
| タスクが予想より小さい | グラフを 1 エージェントに縮退（Skill 直接委任に切り替え） |
| 予算が逼迫 | 安いモデルにルーティング（agent の model オプションを変更） |
| 進捗なし（同じエラー 2 回連続） | ループ停止。brain に再計画を依頼 |
| 新しい依存関係が判明 | リサーチャーを追加して調査ブランチを分岐 |

### Step 3-3: 進捗追跡

各ノードの実行を追跡し、完了シグナルとの照合を実施する。

- TaskCreate で全ノードをタスク登録する
- ノード完了ごとに TaskUpdate で状態を更新する
- 完了シグナルの充足度を報告する

### Step 3-4: 先回り検知

実行中に以下を検知して先回りで対応する:

- 計画ファイルがあるがレビュー未実行 → managing-review-sets を先に起動
- 未コミット変更があるが当該ノードのフローが完了 → コミット・Pull Request 作成を提案
- 並走 Pull Request が存在する → 競合の可能性を報告
- ユーザーが「毎回」「何度も」「繰り返し」と言及 → managing-agent-configs でのスキル・hook 化を推奨
- 完了シグナル未達のまま次のノードに進もうとしている → block して完了シグナルを確認

### Step 3-5: 追加タスクの受付

実行中にユーザーから追加の指示を受けた場合、以下の 3 択で判定する:

| 判定 | 条件 | 動作 |
|---|---|---|
| 統合 | 主ゴールに関連する（同じ画面・同じ機能・同じ Pull Request に含めるべき） | 現在のグラフにノードを追加して統合する |
| 払い出し | 主ゴールと無関係かつ独立して実行可能 | タスクボードに登録する（下記コマンド）。別セッションが拾って実行する |
| 保留 | 主ゴールと無関係かつ軽量（主ゴール完了後に 5 分で終わる） | タスクボードに priority low で登録し、主ゴール完了後の Phase 4 で着手を提案する |

タスクボードへの登録:

```bash
node ~/agent-home/tools/harness/scripts/task-board.mjs add \
  --id <内容要約のケバブケース> \
  --goal "<ゴールの 1 文>" \
  --condition "<完了条件>" \
  --priority <high|normal|low> \
  --project <対象リポジトリの絶対パス>
```

id は内容を要約した意味語キー（連番禁止）。登録後は「タスクボードに登録しました。主ゴールに戻ります」と宣言して主ゴールの実行を再開する。

**完了**: 全ノードが実行され、完了シグナルを満たしている

## Phase 4: 完了判定

### Step 4-1: 完了条件の照合

Phase 1 で合意した完了条件と、実行結果を照合する。

- 全条件を満たし、各条件の実測証拠がある → 完了を宣言する
- 未充足条件がある → 具体的に何が残っているか報告し、Phase 3 に戻る

テスト・レビュー・commit・push・publication・公開後確認を条件に含む場合、コマンド結果・commit SHA・remote ref・公開先の再取得結果が揃うまで Goal を complete にしない。予定や自己申告は実測証拠として扱わない。

### Step 4-2: 完了報告とスキル化確認

完了条件の全充足を確認後、完了報告をユーザーに提示する。報告の直後に以下を確認する:

1. Phase 2 Step 2-2 で「該当スキルなし」と判断していた場合:
   - 「今回の対応をスキルとして作成しますか？」と AskUserQuestion で確認する
   - 「はい」→ Skill("managing-agent-configs") でスキル作成フローに入る
   - 「いいえ」→ セッション終了
2. セッション中に繰り返した手順がある場合:
   - 「この手順を hook・スキルとして自動化しますか？」と確認する
3. コミット・Pull Request の作成が必要な場合（未完了のとき）:
   - コミット・Pull Request 作成を提案する

**完了**: 完了条件が満たされ、ユーザーに報告済み。スキル化の確認も完了

## 起動方法

SessionStart hook（scripts/suggest-session-workflow.sh）が advisory を注入する。hook からは Skill() を呼べないため、Claude が注入を受けて Skill("managing-session-workflow") を自発的に呼ぶ。SESSION-WORKFLOW-GATE hook が実作業（Write/Edit/Bash）を block することで起動を強制する。手動起動（/managing-session-workflow）も可能。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | ゴールと完了条件がユーザーと合意されている |
| Phase 2 | ループ型・グラフ・完了シグナルがユーザーと合意されている |
| Phase 3 | 全ノードが実行され、完了シグナルを満たしている |
| Phase 4 | 完了条件が満たされ、ユーザーに報告済み |
| **Goal** | ユーザーのゴールが達成され、品質が保証された状態でセッションを終了できる |

## サブエージェント委任仕様

Phase 1・2 のゴール設定とグラフ設計はメイン自身が実行する（ユーザーとの対話が必要なため委任不適）。Phase 3 はランタイムに存在する Skill・Agent 系ツールへ委任する。Codex では利用可能な agent 定義を列挙し、選んだ定義の本文を全文読込してから `spawn_agent` へ渡す。役割別定義が無い場合は存在しない固定名を想定せず、`spawn_agent` の既定を使う。

allowed-tools に Write / Edit を含めていない理由: 本スキルは管理者であり、ファイルの作成・編集はすべて実行系サブエージェント（worker-sonnet）または委任先スキルが担う。管理者自身が成果物を直接編集しないことで、判断と反映の分離を構造的に保証する。

## ループ設計

本スキル自体は「セッション単位の 1 回実行」。Phase 3 → Phase 4 → Phase 3 のループは完了条件未充足時のみ発生する。Phase 3 で起動した先のスキルがそれぞれ独自のループを持つ。

## 実行方式

main-session（Skill / TaskCreate / AskUserQuestion を使用）。

## 完了報告

~/agent-home/skills/managing-agent-configs/references/skills/completion-report-format.md の共通骨格に従う。固有の検証行: ゴール・完了条件・ループ型・グラフ複雑度・ノード数・完了シグナル充足状況・自動化推奨の有無。
