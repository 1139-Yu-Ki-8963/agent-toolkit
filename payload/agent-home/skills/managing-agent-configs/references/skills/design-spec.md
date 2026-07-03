# スキル設計仕様

## 1. スキルとは

skill とは、トリガー駆動で起動する拡張であり、起動したときに限り、Claude がデフォルトでは出せない手順・条件付き知識・強制のいずれかを提供するもの。

skill フォルダ（読み取り専用・配布物）には SKILL.md、スクリプト、テンプレート、リファレンスといった不変の部品だけを置く。

## 2. skill 判定フロー

### Q1. それは「常に」必要か？
- YES → context / rules に書く（skill にしない）
- NO（特定のときだけ要る）→ Q2 へ

### Q2. その合図が来たとき、次のどれかを提供するか？
a. 多段の手順・フロー（デプロイ、調査、雛形生成 など）
b. その領域を触るときだけ要る参照知識・落とし穴
c. スクリプト/フックで機械的に効かせたい強制

- どれにも当たらない → skill にしない
- どれかに当たる → Q3 へ

### Q3. それは Claude がデフォルトでやることの言い換えにすぎないか？
- YES → 作らない（無駄なコストと誤発火を足すだけ）
- NO（デフォルトから押し出す中身がある）→ ✅ skill にする

### 除外則（ここに当たったら即・非 skill）
- 常に効く固定ルール → rules ＋ CI/フック
- 「スクリプトを同梱したい」だけ → 普通のフォルダで足りる

## 3. 業務領域（Category, 9 分類）

スキルが「何を扱うか」を表す軸。

ライブラリ参照 / 検証 / データ取得 / 業務自動化 / 雛形 / 品質・レビュー / CI-CD / Runbook / インフラ運用

**1 スキル＝1 分類**

## 4. 振る舞い型（Type, 9 種類）

業務領域（Category）が「何を扱うか」を表すのに対し、振る舞い型（Type）はスキルが「どう動くか」を表す独立軸。第 3 章の Category と直交して扱い、frontmatter には両方を必須宣言する。

### 9 種類の定義

- **`orchestration`（フロー本体型）**
  - 定義: Phase/Step で順序を強制し、複数下位スキルを束ねる中核フロー
  - 判定: Step 順序を縛り、下位スキルを 2 つ以上呼ぶか?
- **`gateway`（入口型）**
  - 定義: フロー本体に入る前に「素材・対象・環境」を確定し、確定後にフローへ橋渡しする前置スキル
  - 判定: フロー本体の前段で対象物を fix し、終わったらフロー起動を期待するか?
- **`gate`（関門型）**
  - 定義: フロー内 Phase から呼ばれ、go/no-go 判定を返す内部審査
  - 判定: 親フローの Phase 内部から呼ばれ、合否を返すか?
- **`audit`（静的監査型）**
  - 定義: 既存物を読み取り、観点ベースで点検レポートを返す（任意で修正）
  - 判定: 読み取り中心で診断 → 任意で修正、か?
- **`verification`（実機検証型）**
  - 定義: 実機シナリオでスキル・フックを動かし、発火精度・副作用を検証
  - 判定: 実機で動かして観察するか?
- **`reactive`（反応型）**
  - 定義: hook 注入タグ（`[TEXTLINT]` `[AMBIGUITY-AUTO-FIX]` `[PUBLISH-*]` 等）を契機にユーザー発話なしで自動起動
  - 判定: タグだけで起動し、修正 patch を返すか?
- **`reference`（規範型）**
  - 定義: 他スキル・直接編集の前に「ロードして従う」対象になる横串のルール・ガイド集
  - 判定: 他スキルから参照されるだけで、それ自身は何もしないか?
- **`transform`（生成・変換型）**
  - 定義: 既存資産から別形式の成果物を生成する
  - 判定: 入力 → 別形式の出力、か?
- **`action`（単発操作型）**
  - 定義: 1 アクションで外部リソース（DB / API / Git）に副作用を残して完了する
  - 判定: 1 ステップ完結で副作用ありか?

### Type 判定の決定木

新規 skill の Type は次の順序で必ず 1 つに確定させる。グレーゾーンを許容しない。

```
Q1. 親フローの Phase 内部から呼ばれ go/no-go を返すか?
  YES → gate
  NO  → Q2

Q2. hook 注入タグでユーザー発話なしに自動起動するか?
  YES → reactive
  NO  → Q3

Q3. Phase/Step で順序を強制し、下位スキルを 2 つ以上呼ぶか?
  YES → orchestration
  NO  → Q4

Q4. フロー本体の前段で素材・対象・環境を確定し、終わったらフロー起動を期待するか?
  YES → gateway
  NO  → Q5

Q5. 実機シナリオでスキル・フックを動かして観察するか?
  YES → verification
  NO  → Q6

Q6. 既存物を読み取り観点ベースで点検レポートを返すか?
  YES → audit
  NO  → Q7

Q7. 入力 → 別形式の出力（生成・整形・変換）か?
  YES → transform
  NO  → Q8

Q8. 他スキル・直接編集の前に「ロードして従う」対象になる横串のルール集か?
  YES → reference
  NO  → action
```

### 軸の独立性

- Category（3 章）と Type（本章）は直交する独立軸
- 同じスキルが「Category: 業務自動化 / Type: orchestration」のように 2 軸で位置付けられる
- 型の重なりは `alt_type:` で吸収する。例: `writing-quality` は規範と反応の両方で動くため `type: reference, alt_type: reactive`
- frontmatter には `category:` と `type:` の両方を必須宣言する（13 章のテンプレート参照）

## 5. ツール選択ロジック

### Step1. skill の Type を判定（= なぜ skill か）
第 4 章の 9 種類（orchestration / gateway / gate / audit / verification / reactive / reference / transform / action）から 1 つに確定。決定木 Q1〜Q8 で必ず収束させる。

### Step2. Type ごとの「基本ツールセット」を採る
9 Type を性質で 3 グループにまとめたマッピング（第 6 章）に従う。

### Step3. 横断ツールを必要時だけ足す
- 起動時にユーザーの選択が要る → AskUserQuestion
- 他の skill を呼ぶ → Skill
- 外部サービスに触る → MCP 系（要 MCP 接続）
- 定期・遅延実行が要る → Cron 系 / ScheduleWakeup
- 何かを監視し続ける → Monitor

### Step4. 最小権限に絞り allowed-tools に固定
- 不要な Write/Bash は渡さない（特に `reference` 型）
- 「常に・決定論的に」強制したい挙動はツールではなく hook（= skill の外の設定）

## 6. 目的 → 最適ツール マッピング

9 Type は性質で 3 グループに集約できる。各グループ内の Type は基本ツールセットを共有する。

### グループ A: 読むのが主（reference）

該当 Type: `reference`

例: ライブラリ / API リファレンス、命名規約、デザイン規範

- 基本: Read, Grep, Glob
- 必要なら: WebFetch / MCP 系（外部参照のとき）
- 原則: Write・Bash は原則渡さない（`reference` 型に実行権は危険）

### グループ B: 実行と編成が主（orchestration / gateway / transform / action）

該当 Type と典型用途:
- `orchestration`: フロー本体（デプロイ、複合ワークフロー）
- `gateway`: フロー前段の素材確定（モック・worktree 準備）
- `transform`: 入力 → 別形式の生成（PR 本文生成、形式変換）
- `action`: 単発操作（コミット、登録、起動）

- 基本: Bash, Read, Write, Edit
- よく足す:
  - Monitor … CI / ログ / エラー率を監視（CI-CD, Runbook, インフラ運用）
  - Agent … 並列調査や重い下請け（Runbook）
  - Skill … 他 skill を合成（`orchestration` で多用）
  - Task 系 … 多段手順の進行管理（`orchestration` 必須）
  - AskUserQuestion … セットアップ / 投稿先選択（`gateway` で多用）
  - Cron 系 … soak 期間・定期実行（インフラ運用）

### グループ C: 検査して介入する（gate / audit / verification / reactive）

該当 Type と典型用途:
- `gate`: 親フロー Phase 内部の go/no-go 判定
- `audit`: 既存物の静的監査・点検レポート
- `verification`: 実機シナリオでの発火・副作用検証
- `reactive`: hook 注入タグ起動の自動修正

- 基本: Agent（第三者視点の批評）, Read, Grep, LSP, Bash（linter）
- 介入するなら: Edit（修正を適用）
- 注意: 「毎回必ず弾く」はツールでなく hook の領域。skill のツールは「起動時に検査する」ところまで

## 7. skill 命名規約

### 最優先
名前だけで「何をするか」が一意に伝わる
- 短さより曖昧さ排除。64 字まで使え、長くてよい
- 二人が別解釈しうるなら語を足して潰す

### 語形
action-oriented（動詞-目的語）で確定
- create- / verify- / deploy- など動詞始まり

### 語彙
平易な一般語
- 略語・隠語を避ける
- バージョン表記は入れない（version はメタデータで管理）
- 亜種は番号でなく差分を語で（create-skill-minimal 等）

### 一貫性
同じ動作は同じ動詞で固定

### 衝突チェック（必須）
1. 自分の skill / slash コマンドと重複しない
2. Anthropic 公式 skill と重複しない（参照元: anthropics/skills）
   例: frontend-design, pdf, docx, pptx, xlsx …
3. 予約語 anthropic / claude を含めない

### 硬い制約（公式）
小文字 / 数字 / ハイフン、最大 64 字

## 8. skill フォルダ構造規約

### 共通スケルトン

```
<skill>/
├── SKILL.md          # 概要 + 目次（= 型ごとの分割単位）＋ 全体ルール ＋ Gotchas（必須）
├── <分割ディレクトリ> # 型で単位が決まる（下記）。1 単位 = 1 ファイル
├── scripts/          # 実行スクリプト
└── assets/           # テンプレート
```

### 共通ルール
- 状態・ログはセッションフォルダへ出力。skill フォルダには絶対置かない
- 参照は SKILL.md から 1 階層まで（深いネスト禁止）
- ファイル名は内容が分かる名前（doc2.md ✗ / form_validation_rules.md ○）
- 100 行超のファイルは冒頭に目次
- 型が決まれば分割単位は自動で決まる（判断の余地を残さない）

### orchestration / gateway （フロー型）→ 単位 = Phase

```
phases/
├── 01-<phase 名>.md
├── 02-<phase 名>.md
└── ...
```

必須:
- Phase と Step を必ず明記
- Phase ごとに 1 ファイル（番号をファイル名先頭に＝順序が一意）
- 各ファイル冒頭: `# Phase N: 名前`
- 各操作: `## Step N` 連番
- SKILL.md に Phase 一覧（目次）＋ 進捗チェックリスト（Claude がコピーして 1 つずつ消す）

### reference （参照）→ 単位 = ドメイン / トピック

```
reference/
└── <ドメイン or トピック>.md   # 1 トピック = 1 ファイル（索引構造、フロー化しない）
```

必須:
- SKILL.md は「どのトピックがどのファイルか」のナビ表
- 各ファイル 100 行超なら冒頭に目次
- Gotchas は該当トピックのファイル内に置く

### gate / audit / verification / reactive （検査・反応型）→ 単位 = ルールカテゴリ

```
rules/
└── <ルールカテゴリ>.md       # 1 カテゴリ = 1 ファイル（該当時だけ読む）
scripts/
└── <検査スクリプト>           # 決定論的チェックはコード化
```

必須:
- 検査は feedback loop を Step 化（検査 → 修正 → 再検査 → 合格まで）
- 機械的に効かせるなら on-demand フックを併用

### action / transform （単発型）→ 分割なし

該当 Type: `action` / `transform`

単発で完結するため `phases/` `reference/` `rules/` のような分割ディレクトリは不要。SKILL.md 1 ファイルに手順を全部書ききる（100 行超なら冒頭目次を追加）。

必須:
- 副作用がある場合は冒頭に明示（DB / API / Git への書き込み）
- `transform` は入出力ペアを 1 例だけ載せる

### 配置規約

- **パス**: `~/agent-home/skills/<name>/SKILL.md` 形式で配置する
- **絶対パス禁止**: 本文に `/Users/...` のような絶対パスを書かない。`~/agent-home/skills/<name>/` からの相対パスで参照する
- **ポータル catalog 登録（必須）**: skill 作成後、`~/agent-home/ai-management-portal/catalog/skills.html` の `SKILLS` 配列に 1 エントリを追加する
  - 適切な `cat`（カテゴリ）に配置（なければ `CATEGORIES` に新規カテゴリを追加）
  - `summary`: 一行説明
  - `trigger`: 発火トリガー語を箇条書き相当で記載

## 9. description 規律

- 合計上限: 約 2,000 文字（窓の 1% / 日本語 ≒ 1 字 1 tok の保守見積）
- 1 件あたり: ≤ 50 文字
  - 「何をするか」を三人称で 1 文。トリガー語の作り込みは不要（明示呼び出し前提）
  - 50 字なら 2,000 ÷ 50 ＝ 約 40 個 の説明が全文ロードされる

### 40 個を超えそうなら（優先順位の付け方）
1. 説明をさらに削る（30 字台へ）
2. `skillListingBudgetFraction: 0.02` で枠を倍（≒ 80 個）
3. よく使うものは自動で説明が残る（低頻度から落ちる）
4. 名前は常時載るので /name 呼び出しは個数無制限

### 監視
`/doctor` で溢れ確認

### TRIGGER when: / SKIP: 固定キーワード

description には次の 2 つの **固定英語キーワード** を必ず含める。`Use when:` / `使用時:` 等の別表記は非標準で解析されない。

- **`TRIGGER when:`** に続けて発動条件を **具体キーワード・操作名** で列挙する
- **`SKIP:`** に続けて非発動条件を記述し、可能なら境界スキルへの誘導（→ 別スキル名）を含める

良い例:

```yaml
description: |
  ブランチ作成・worktree 管理を行うスキル。
  TRIGGER when: ブランチ作成時、git checkout 時、worktree 作成時。
  SKIP: 既存ブランチの読み取り・確認のみの時（→ git-status）。
```

悪い例（「〜用」等の抽象短文、SKIP / TRIGGER 不在、誘導なし）:

```yaml
description: Git worktree 管理用スキル
```

### description 品質の追加基準

- 「〜用」等の抽象短文を避け、反応すべき語を列挙する
- TRIGGER 範囲が広すぎ誤発火リスクがある場合は範囲を絞り SKIP を補強する
- SKIP には可能な限り境界スキル名を `→ skill-name` 形式で明示する

## 10. Progressive Disclosure（段階的開示）

Claude は skill を 3 段階に分けてロードする。各段階で「何が」「いつ」「どれだけ」ロードされるかを把握して、SKILL.md のサイズと配置を設計する。

### Stage 1: メタデータ（常時ロード）
- 内容: `name` / `description` / frontmatter
- タイミング: Claude Code 起動時に全 skill 分まとめてロード
- 制限: 1 skill あたり 100 トークン以下が目安。description 説明文は 50 字以内（第 9 章参照）

### Stage 2: SKILL.md 本体（トリガー時）
- 内容: SKILL.md の本文全体
- タイミング: description にマッチしたとき、または明示呼び出し時
- 制限: **500 行 / 5000 トークン以下**。超えたら `references/` へ分離

### Stage 3: バンドルリソース（参照時のみ）
- 内容: `references/*.md` / `scripts/*` / `assets/*`
- タイミング: SKILL.md 本体に参照が記載されているファイルを Claude が必要と判断して読むとき
- 制限: 制限なし

### 設計指針
- Stage 1 の予算を強く守る（全 skill 合計 2,000 字以内、第 9 章参照）
- Stage 2 が肥大したら Stage 3 へ詳細を移譲する（目次 + 最小手順だけ残す）
- Stage 3 はスキル固有の内容のみ。公式ドキュメントのコピーは置かない

## 11. SKILL.md 本文ルール

### 自己宣言は frontmatter で行う

`category:` と `type:` は frontmatter の必須項目（13 章テンプレート参照）。本文冒頭は skill 名の `# <skill 名>` のみで、本文中に `> Category: ...` `> Type: ...` の宣言は書かない。frontmatter が正本ソース。

### 必須セクション
- Gotchas（定義は下）
- 重要指示は冒頭付近に置く（溢れ時は先頭が残る＝ truncation 対策）

### 書く / 書かない
- 当たり前を書かない（Claude が既に知ることは省く）
- デフォルトから押し出す情報・社内固有知識だけ書く

### 自由度をタスクの脆さに合わせる
- 高自由度＝文章指示（複数の道が正解 / 文脈依存）
- 低自由度＝手順・スクリプト指定（脆い・破壊的・一意手順必須）

### 一貫性・鮮度
- 用語は 1 概念 1 語で統一
- 時限情報は避け、必要なら "old patterns" 節へ隔離

### 選択肢（やり方の提示）
- 手段を並べない。既定を 1 つ ＋ 特定条件の代替を 1 つだけ
- 例: pdfplumber を使う。スキャン PDF の OCR 時のみ pdf2image

### 品質パターン（必要時）
- 例示（入出力ペア）／テンプレ（厳格さは要件次第）／フィードバックループ（検査 → 修正 → 再検査）

### Gotchas 定義
その skill で Claude が繰り返す「直感に反する罠」を蓄積する節（最高シグナル）。

形式:

```markdown
## Gotchas
- <罠 / 直感に反する点>: <実際はこう> → <だからこうする>
```

例:
- subscriptions は追記専用。最新行は created_at 最大でなく version 最大
- gateway は @request_id、billing は trace_id（同じ値）
- staging は webhook 未処理でも 200 を返す → payment_events で真の状態確認

1 個から始め、失敗のたびに足して育てる

### 行数・トークン制限
- SKILL.md 本体は **500 行 / 5000 トークン以下**
- 200 行を超えたら詳細を `references/` へ分離し、本体は目次＋最小手順だけ残す
- 500 行超は CRITICAL（必ず分離する）

### セクション見出しの日本語統一
章タイトル・節タイトルは日本語で揃える。`## Setup` / `## Workflow` のような英語見出しは使わない。

### 公式ドキュメントのコピー禁止
- 公式ドキュメントは本文にコピーしない。**参照リンクで済ませる**
- `references/` には **そのスキル固有** の詳細情報のみ置く（パターン集、例、トラブルシューティング）
- 汎用情報・公式情報は `references/` ではなく `/docs/` 等の共有領域に置く

## 12. 単一責務と副作用安全性

### 単一責務（1 スキル = 1 機能）
- 1 スキルに複数責務を詰め込まない。責務単位で分割する
- 共通手順を他スキルからコピペしない。参照元スキルへ一本化する
- 亜種は番号でなく差分を語で区別する（第 7 章参照）

### 副作用安全性
- 取り消し困難な操作（push / merge / deploy / `rm -rf` / `DROP TABLE` / force-push 等）はオート発火させない。`AskUserQuestion` で承認要求するか、手動発火に限定する
- スクリプトは SKILL.md に直書きせず `scripts/` へ分離する
- 標準 Markdown 記法を使う（他クライアント非互換となる `!` 構文は避ける）
- 副作用がある skill の frontmatter は `disable-model-invocation: true` を付与する（第 15 章参照）

## 13. ツール活用（フロー系限定）

`orchestration` 型・`gateway` 型などの **フロー系スキル**（`## Phase N` / `### Phase N` 見出しを 3 つ以上含む、他スキルを Skill ツール起動する、複数 PR/issue/並列タスクを統制する、のいずれかを満たすもの）は、Claude 標準ツールを能動的に活用する。

- **Phase 分割**: 複数ステップは `## Phase N` / `### Phase N` で段階化する
- **Agent 委譲**: 重い調査・並列処理は `Agent`（サブエージェント）に委譲する
- **進捗管理**: 多段・長時間タスクは `TaskCreate` / `TaskUpdate` で可視化する
- **プラン承認**: 非自明な実装フローは `ExitPlanMode`（プラン承認）を取る
- **承認・選択**: 取り消し困難な操作・分岐は `AskUserQuestion` で承認する
- **他スキル明示呼び出し**: 他スキルを呼ぶときは手順記述だけでなく `Skill` ツール起動を明記する
- **仕組み化**: 「AI の挙動頼み」を避け、ツール呼び出しによる仕組み化を選ぶ

## 14. セットアップ・記憶・on-demand フック

### 共通原則
- 可変データ（設定・記憶）は skill フォルダに置かない（フォルダは不変）
- 置き場: セッションフォルダ / 永続が要るなら `${CLAUDE_PLUGIN_DATA}`

### セットアップとは
その skill が「ユーザー / 環境ごとに違う値」を知らないと動けない場合に、その値を一度だけ埋めて記憶すること。

対象 = コードに埋め込めない（人ごとに違う）が、毎回聞くのも無駄な、一度決めたら変わらない値。

例:
- Slack 投稿先チャンネル
- 社内 API のエンドポイント・トークン
- BigQuery のプロジェクト ID
- デプロイ対象環境

非対象 = 毎回変わる入力（その時の PR 番号・対象ファイル）= 実行時引数

手順:
- 未設定なら AskUserQuestion で聞く（自由文で聞かない）
- 機密（トークン等）は userConfig の sensitive (keychain) へ
- 非機密は `${CLAUDE_PLUGIN_DATA}/config.json` に保存し、次回は聞かない
- skill フォルダ内 config は禁止

### 記憶
- 形式: 追記ログ / JSON / SQLite
- 置き場: セッションフォルダ / 永続は `${CLAUDE_PLUGIN_DATA}`
- 使い方: 自分の履歴を読み、差分や一貫性に使う（例: standups.log）

### on-demand フック（※ツールでなく設定機構・skill の hooks 設定に置く）

原則: 「この skill の実行中だけ効かせたい決定論的なガード / 検査」に使う。常時・全セッションで効かせたいものは CI か常時フックへ（ここではない）。

カテゴリ:
- ブロック系 (PreToolUse): 危険操作・範囲外編集を弾く
  - 例: /careful = rm -rf / DROP TABLE / force-push を止める
  - 例: /freeze = 指定ディレクトリ外の Edit / Write を止める
- 検証系 (PostToolUse): 編集のたびに linter / formatter / 型チェック / テストを走らせ、結果を Claude に返して直させる（＝フィードバックループの強制）

記述レベル: 設計ルールは「いつ使うか＋カテゴリ＋例」まで。個別のフックコマンドは各 skill が書く（列挙しない）。

## 15. 執筆言語・起動モデル・テンプレート方針

### 執筆言語
日本語

### 起動モデル
- 既定: 自動＋明示の両方を許可（`disable-model-invocation` は付けない）
- 例外: 副作用・破壊的な skill（deploy / commit / 送信 / 削除 等）のみ `disable-model-invocation: true`（Claude が勝手に発火しないように）
- description に「いつ使うか」のトリガー語を 1 つ含める（日本語 50 字以内）

### テンプレート（Type ごとの要否のみ・中身は定義しない）
- `orchestration` / `gateway` / `transform` / `action`: 定型アウトプットがあれば `assets/` にテンプレートを用意（必須）
- `reference`: テンプレート不要
- `gate` / `audit` / `verification` / `reactive`: レポート / 修正の定型があれば `assets/` にテンプレートを用意
- 中身は各 skill が作る。設計ルールは「用意するか否か」まで

## 16. skill frontmatter テンプレート

```yaml
---
name: <動詞-目的語・小文字 / 数字 / ハイフン・最大 64 字>
description: <三人称・日本語 50 字以内・「何をするか」＋トリガー語 1 つ>
category: <第 3 章の 9 分類のいずれか 1 つ>
  # ライブラリ参照 / 検証 / データ取得 / 業務自動化 / 雛形 /
  # 品質・レビュー / CI-CD / Runbook / インフラ運用
type: <第 4 章の 9 種類のいずれか 1 つ>
  # orchestration / gateway / gate / audit / verification /
  # reactive / reference / transform / action
alt_type: <type の重なりがある場合のみ・第 4 章の 9 種類のいずれか>
  # 例: writing-quality は type: reference, alt_type: reactive
allowed-tools: <型ごとの最小セット>
  # 例 reference: Read, Grep, Glob
  # 例 orchestration / action / gateway / transform: Bash, Read, Write, Edit
  # 例 reactive / gate / audit / verification: Agent, Read, Grep, Bash

# 以下は該当時のみ付ける（既定はどちらも付けない＝自動＋明示の両方可）
disable-model-invocation: true   # 副作用・破壊的 skill（deploy / commit / 送信 / 削除）のみ
user-invocable: false            # reference 型の純粋背景知識のみ（コマンドの意味がないもの）
---
```

必須項目:
- `name` / `description` / `category` / `type` / `allowed-tools` の 5 項目

任意項目:
- `alt_type`: 振る舞いが 2 つの Type に跨る場合のみ
- `disable-model-invocation`: 副作用・破壊的 skill のみ
- `user-invocable`: reference 型の純粋背景知識のみ

注:
- 既定（無印）= 自動・明示の両方から呼べる
- `disable-model-invocation` と `user-invocable` は同時に付けない（排他）
- `paths` は不具合報告があるため当面使わない
- `category` と `type` は直交軸。同じスキルが両方を 1 つずつ持つ
