# サブエージェント委任規約（SUBAGENT-SELECTION）

Claude が重い作業を自分で抱え込まず、適切なサブエージェントに委任するための行動規範。

## サブエージェント体系（4 分類の定義）

全サブエージェントは次の 4 分類のいずれかに属する。**合否（PASS / FAIL・承認 / 差し戻し）を宣言できるのは判定系のみ**。他の分類が合否を宣言すること、判定系が作業・計画を行うことを禁止する。

| 分類 | エージェント | 役割 | 合否宣言 |
|---|---|---|---|
| 計画系 | brain | 計画立案・タスク分解・作業指示の組み立て・発散時の再計画 | 不可 |
| 実行系 | worker-sonnet / worker-haiku | ファイルの作成・修正 ／ コマンド実行と結果報告 | 不可 |
| 調査系 | investigator / researcher / plan-comprehension-prober | ローカルの事実収集 ／ 外部情報の収集 ／ 計画文の初見読解の言語化。証拠付きの事実を返す | 不可 |
| 判定系 | code-reviewer / document-reviewer / report-reviewer | 成果物（コード／文書）を rules に照合 ／ 調査報告の事実性を検証。**唯一、合否を宣言できる** | 可 |

- 判定系の内訳は「何を判定するか」と 1 対 1（コード・文書は `~/.claude/rules/scoped/review-checklist/` のドメインフォルダと対応、報告は report-reviewer）
- 既知の例外: orchestrating-dev-flow の 3 レビューゲートは worker-sonnet にプロジェクトの人格ファイルを注入する独自方式が残っている（体系違反。判定系への移行対象）

## 判断と反映の分離（委任の基本原則）

「内容を決める」と「決めた内容を反映する」を分離する。決めるのはメインセッション（大規模な分解・複数案比較は brain）、反映は実行系。

| 工程 | 担当 | 内容 |
|---|---|---|
| 決める | メインセッション（大規模な分解・複数案比較は brain） | 何をどう変えるかの決定・設計判断・文言/コードの起草・修正方針の確定 |
| 反映する | worker-sonnet / worker-haiku | 確定済み内容のファイルへの書き込み・一括適用・コマンド実行 |
| 確かめる | 判定系・調査系 | 反映結果の照合・裏取り（合否宣言は判定系のみ） |

- **委任の条件は「内容が確定していること」**。worker への委任プロンプトには、確定済みの実体（新規ファイルは全文、編集は変更前後の対、置換は仕様）をベタ書きで埋め込む。「考えて直して」と内容の決定ごと丸投げしない
- **逆も禁止**: 内容が確定した後の反映をメインが直接 Write / Edit しない。hook（MAIN-AGENT-DIRECT-WORK-BLOCK）の「設定管理は例外」は block しないという意味であり、委任原則の免除ではない。設定資産（rules / skills / agents / hooks）の編集も、内容確定後の反映は worker-sonnet に委任する
- worker-sonnet に許される「判断」は、渡された確定内容をファイルへ正しく当てるための局所判断（適用位置の特定・周辺コードへの馴染ませ・確定方針から機械的に導ける派生修正）に限る。方針の変更が必要になったら自分で決めず、止まって委任元に差し戻す

## 委任判定フロー

タスクを受け取ったら、実行前に以下を判定する。

```
Q0. `~/Projects/` 配下のファイル編集を伴う委任か？
    YES → orchestrating-dev-flow の route 確定（Phase 1 完了・worktree 作成済み）を確認する。
          未完了なら先に `Skill(orchestrating-dev-flow)` を起動して route 確定まで完走させ、
          確立された worktree パスを委任プロンプトにベタ書きで渡す。
    NO  → Q1 へ

Q1. タスク分解・計画立案・複数案の比較を要する設計判断が必要か？
    YES → brain に委任（計画のみ。実行結果・成果物の合否判定は判定系へ）
    NO  → Q2

Q1b. 成果物・報告の合否判定が必要か？
    成果物（コード・文書）→ Skill(reviewing-against-rules) 経由で code-reviewer / document-reviewer
    調査報告 → report-reviewer
    NO  → Q2

Q2. 外部情報（Web 検索・API ドキュメント・ライブラリ仕様・ニュース）が必要か？
    YES → researcher に委任
    NO  → Q3

Q3. 調査・分析・レビュー・根本原因特定が必要か？
    （ログ解析・transcript 読解・セッション横断の実態把握・設計整合性の検証・プロジェクト構成レビュー等）
    YES → 調査チェックリストパイプライン（後述）を実行
    NO  → Q4

Q4. 修正方針が確定しており、反映に文脈を読む局所判断を伴うか？
    （確定方針に基づく影響範囲分析・規約チェック・リファクタリング・PR 差分の分析）
    YES → worker-sonnet に委任（確定済み方針・対象・完了条件をベタ書きで渡す。
          方針が未確定なら先にメイン（大規模なら brain）で確定させる。「判断と反映の分離」参照）
    NO  → Q5

Q5. ユーザーとの対話・質問応答か？
    YES → 自分で実行
    NO  → Q6

Q6. ファイルの作成・編集を伴うか？
    YES → worker-sonnet に委任（確定済み内容をベタ書きで渡す。機械的な一括編集も含む。
          worker-haiku はファイルを変更できない）
    NO  → worker-haiku に委任（コマンド実行と結果報告のみ）
```

## 委任すべき作業の具体例

| 作業 | 委任先 | 理由 |
|---|---|---|
| ログ・transcript の解析 | investigator | 文字列出現と実発火の区別など高精度な判断が必要 |
| 根本原因の特定・仮説検証 | investigator | 複数データソースの突合と論理的推論 |
| セッション横断の実態調査 | investigator | 大量データから正確にパターン抽出 |
| 設計の整合性検証・レビュー | investigator | 仕様と実装の齟齬を見抜く |
| 計画の暗黙知抽出（初見読解プローブ） | plan-comprehension-prober | コンテキストゼロの弱モデルが計画の省略前提を顕在化する（Skill(eliciting-plan-tacit-knowledge) 経由で呼ぶ） |
| 影響範囲分析・呼び出し元追跡 | worker-sonnet | 複数ファイルを横断する調査 |
| 規約チェック・整合性確認 | worker-sonnet | パターンマッチと判断の組合せ |
| 方針確定済みの修正・リファクタリングの反映 | worker-sonnet | 確定した方針の範囲内で文脈を読んで適用（方針の決定はメイン / brain） |
| 設定資産（rules / skills / agents / hooks）の確定済み編集の反映 | worker-sonnet | hook の設定管理例外は block 免除であり、委任原則は適用される |
| PR 差分の分析 | worker-sonnet | 変更意図の読解と判断 |
| 変数名・import パスの一括リネーム | worker-sonnet | ファイル編集は sonnet 以上が担う（haiku は編集ツールを持たない） |
| テスト・ビルド・lint の実行と結果報告 | worker-haiku | 判断不要の実行と収集 |
| コミット・PR 作成など git 操作 | worker-haiku | 判断不要の定型 git 操作 |
| 判断不要な小規模修正（typo・定型パッチ） | worker-sonnet | ファイル編集は sonnet 以上が担う（haiku は編集ツールを持たない） |
| ライブラリ仕様・最新 API の調査 | researcher | MCP ツールによる外部検索 |
| エラー解決策の検索 | researcher | Web 検索と情報突合 |
| ニュース収集・トレンド調査 | researcher | tavily-search による外部情報収集 |
| OSS リポジトリの設計・仕組み調査 | researcher | deepwiki による構造理解 |
| 大規模タスクの計画・分解 | brain | タスク分解と worker 配布（計画のみ。合否判定はしない） |
| worker 実行結果の合否判定 | 判定系（成果物→code/document-reviewer、報告→report-reviewer）または委任元が成功条件と突合 | 合否宣言は判定系のみ。brain には戻さない |
| 複雑な分析・設計判断 | brain | 複数案の比較と計画としての意思決定 |

## 自分で実行すべき作業

- ユーザーとの対話・質問応答
- 単一ファイルの読み取りと説明
- 修正内容の決定・設計判断・文言/コードの起草（「決める」工程。確定後の反映は worker へ委任する）
- 委任プロンプトの組み立て（確定済み実体の埋め込み・完了条件の設計）

## 委任先別プロンプトルール

### investigator（調査・分析）

- **出力制限を必ず指定する**: 「N行以内で」「出力形式（厳守）」を必ず含める
- **判定基準を明示する**: 「X が Y なら A、そうでなければ B」のように曖昧さを排除
- **推測禁止を明記する**: 「ログに証拠がない場合は『証拠なし』と報告」
- **出力形式テンプレを渡す**: 自由記述ではなく、埋めるべき項目を指定する

### worker-sonnet（確定済み修正の反映）

- **確定済み内容を実体で渡す**: 新規ファイルは全文、編集は変更前後の対、置換は仕様をベタ書きする。「適切に直して」と方針の決定を委ねない
- **変更対象ファイルを明示する**: パスを具体的に指定。「関連ファイルを探して」は禁止
- **変更の意図を 1 文で伝える**: 何をなぜ変えるか
- **スコープ外変更を禁止する**: 「指定ファイル以外を変更しない」を明記
- **完了条件を明示する**: grep やテストで確認できる基準を渡す

### worker-haiku（コマンド実行専用）

- **ファイル編集を渡さない**: worker-haiku は Write / Edit ツールを持たない。ファイルの作成・編集・削除を伴う作業は worker-sonnet に渡す
- **実行コマンドをベタ書きで渡す**: 「調査して」「修正して」は禁止。「このコマンドを実行しろ」
- **判断を求めない**: 「問題があれば報告して止まれ。自分で修正するな」
- **出力はコマンド結果のみ**: 「N行以内で結果を報告」

### 全委任先共通

- **スコープを明示する**: 「このファイルだけ」「このディレクトリだけ」
- **禁止事項を明記する**: 「指示外のファイルを変更しない」「自己判断で追加作業をしない」
- **文脈依存語を禁止する**: 「直前の」「先ほどの」「例の」でメイン側の文脈を参照しない。サブエージェントはメインの会話を見られないため、diff・決定事項・前提データは**実体を prompt に埋め込む**（2026-07-05 実測: diff 実体の未受け渡しによる実行拒否が発生）
- **出力形式を必ず指定する**: すべての委任で出力の項目構成と行数上限を渡す（2026-07-05 実測: 形式指定ありの委任は不十分率が約半分。1.2% vs 2.2%）

## サブエージェントの呼称

サブエージェントを「子」、メインエージェントを「親」と呼ぶことを禁止する（ユーザー向け出力・ドキュメント・プロンプトすべて）。役割が伝わる呼称を使う。

- サブエージェント → 担当者・実装者・レビュー担当・調査担当（役割で呼ぶ）
- メインエージェント → 呼び出し元・メインセッション

出典: 2026-07 のユーザー指摘（「子という名称で呼ぶのも禁止」）。「子/親」は関係しか表さず、初見の読み手に役割が伝わらないため。

## 調査チェックリストパイプライン

Q3 に該当するタスク（調査・分析・レビュー）は、以下のパイプラインで実行する。

### パイプライン

```
Step 1: Skill(subagent-investigation-checklist) でチェックリストを作成
         → worktree 内に .investigation-checklist.md を配置
Step 2: Agent(subagent_type: "investigator", prompt にチェックリスト全文を埋め込み) で調査実行
         → 読み取り専用の調査エージェントがチェックリスト項目を 1 つずつ実行し、証拠付きで報告
         → 汎用エージェント + model 指定での代用は禁止（Write/Edit を持ったまま調査させない）
Step 3: Agent(subagent_type: "report-reviewer", prompt にチェックリスト + 調査結果を渡す) でレビュー
         → レビュアーがチェックリスト照合 + 事実性検証を実施し PASS / FAIL を返す
Step 4: FAIL なら Step 2 に戻る（最大 2 回）。PASS ならユーザーに報告
Step 5: .investigation-checklist.md は worktree 削除時に自動消滅（手動 rm 不要）
```

### 例外（パイプライン不要）

- worker-haiku へのコマンド実行委任（テスト実行等）、および worker-sonnet への置換仕様指示済みの一括編集委任
- routine-worker への定型実行
- 単一ファイルの grep / Read（1 コマンドで完結する簡易調査）
- prompt に `[CHECKLIST-EXEMPT]` を明示した場合

## 結果検証義務

調査チェックリストパイプラインを経由した場合、レビュアーの PASS 判定が結果検証を兼ねる。パイプラインを経由していない場合は以下の手動検証を実施する。

サブエージェントの報告をユーザーに伝える前に、main 自身が以下を検証する。

1. **事実の裏取り**: 報告された数値（「N 件」「N 回」）を別の経路で確認する
2. **推測と事実の区別**: 報告に「可能性がある」「と考えられる」が含まれる場合、事実部分と推測部分を分離してからユーザーに伝える
3. **再現性の確認**: 「X が原因」と報告された場合、X を実際に確認してから伝える

検証せずにサブエージェントの報告をそのまま伝えることを禁止する。

## 並列委任

独立した作業が複数ある場合は、サブエージェントを **並列で起動** する。順次実行は無駄な待ち時間を生む。

```
# ✗ 順次（遅い）
result1 = Agent(subagent_type: "worker-sonnet", prompt: "ファイル A を調査")
result2 = Agent(subagent_type: "worker-sonnet", prompt: "ファイル B を調査")

# ✓ 並列（1 メッセージで複数 Agent 呼び出し）
result1, result2 = [
  Agent(subagent_type: "worker-sonnet", prompt: "ファイル A を調査"),
  Agent(subagent_type: "worker-sonnet", prompt: "ファイル B を調査"),
]
```

## 並列委任時の worktree 統制

`~/Projects/` 配下のリポジトリで並列委任する場合、メインセッションが `parallel-dev-worktree` で worktree を 1 本だけ作成し、そのパスを全サブエージェントの委任プロンプトに渡す。各サブエージェントが個別に worktree を作成することを禁止する（変更が分散し、managing-agent-configs のマーカー機構が断絶するため）。

## バックグラウンド起動（必須）

サブエージェントは **必ず `run_in_background: true` で起動する**。フォアグラウンド（デフォルト）で起動するとメインエージェントが応答不能になり、ユーザーとの会話が中断する。

```
# ✗ フォアグラウンド（禁止）
Agent(subagent_type: "worker-sonnet", prompt: "...")

# ✓ バックグラウンド（必須）
Agent(subagent_type: "worker-sonnet", run_in_background: true, prompt: "...")
```

唯一の例外: サブエージェントの結果がないと次の処理に進めない場合（結果を待つ必要がある調査で、かつユーザーが応答を待っていない場合）。

## ループ協議

メインエージェント・サブエージェント共通で、各タスクは「直線」ではなく「ループ」として走らせる。

### ループ手順

1. 変更を書く
2. チェックを走らせる: テスト + linter + 型チェック
3. 失敗した場合 → エラーを読み、原因を特定し、直して、2 に戻る
4. ループは最大 5 回まで

### 停止条件

- 全チェック通過 → 「完了」と報告。通過した出力を証拠として添える
- 5 回使い切った → 止まって、何が残っているか報告する
- 同じエラーが 2 回連続 → ループを止め、呼び出し元に差し戻す（計画の見直しが必要なら brain に再計画を委任する。brain は再計画のみを返し、合否判定はしない）

### 禁止事項

- チェック出力なしで「完了」と報告すること
- アサーション削除やテスト弱体化で通すこと。直すのはコードであり、スコアボードではない

## 機械強制

| timing | hook | 注入タグ | 挙動 |
|---|---|---|---|
| UserPromptSubmit | `suggest-subagent.sh` | `[SUBAGENT-DELEGATION-HINT]` | ユーザー発話にキーワードを検出し委任検討を促す（block しない） |
| PreToolUse(Write\|Edit\|MultiEdit\|Bash) | `check-main-agent-direct-work.sh` | `[MAIN-AGENT-DIRECT-WORK-BLOCK]` | メインエージェントの直接作業を exit 2 で block。サブエージェント・Read 系・設定管理は例外。同一セッション 3 回連続で自動解除 |
| PreToolUse(Agent) | `check-evidence-checklist.sh` | `[CHECKLIST-MISSING]` | 調査・レビュー系の Agent 委任で prompt 内に `## 調査チェックリスト` がなければ exit 2 で block。例外: worker-haiku / routine-worker / Explore / researcher / claude-code-guide / `[CHECKLIST-EXEMPT]` 明示（2026-07-05: 過去 14 日の実測で block の大半が Explore / researcher への過剰適用だったため例外化。investigator / brain / report-reviewer には常時適用） |
| PreToolUse(Agent) | `check-subagent-choice.sh` | `[SUBAGENT-CHOICE-BLOCK]` | subagent_type が general-purpose/claude で、調査・レビュー・PR差分等に分類できるタスクなら名前付きサブエージェントへの変更を要求。分類できない残余タスクは model 未指定なら明示指定を要求。いずれも exit 2 で block。同一セッション4回連続で自動解除 |
| PreToolUse(Bash) | `check-worker-haiku-file-change.sh` | `[WORKER-HAIKU-FILE-CHANGE-BLOCK]` | worker-haiku（`agent_type` で判定）のファイル変更コマンド（リダイレクト・touch・mkdir・sed -i 等）を exit 2 で block。git コマンドセグメントは例外。自動解除なし。引用文字列内は走査対象外（`<email>` 等の誤検出防止。引用内の実リダイレクトは検出不能の既知の限界） |

## 違反検知時の手順

### `[SUBAGENT-DELEGATION-HINT]` 受信

1. 注入メッセージ内のキーワードと委任判定フローを突合する
2. 該当する委任先がある場合は `Agent(subagent_type: "<name>")` で委任する
3. 委任不要と判断した場合は理由を 1 文でユーザーに伝えてから自分で実行する

### `[MAIN-AGENT-DIRECT-WORK-BLOCK]` 受信

1. block された操作の内容を確認する
2. 委任判定フロー（本ファイル冒頭）に従い適切なサブエージェントを選ぶ
3. `Agent(subagent_type: "<name>")` で委任する
4. 3 回連続 block で自動解除される。解除後もサブエージェント活用を優先する

### `[CHECKLIST-MISSING]` 受信

1. block された Agent 委任の prompt 内容を確認する
2. Skill(subagent-investigation-checklist) を実行してチェックリストを作成する
3. チェックリスト全文を prompt に埋め込んで Agent を再呼び出しする

### `[SUBAGENT-CHOICE-BLOCK]` 受信

1. 注入メッセージの分類結果を確認する
2. 分類が示された場合: 該当する名前付きサブエージェント（model固定済み）に subagent_type を変更して再実行する
3. 分類なし（残余タスク）の場合: `model` パラメータを明示指定して再実行する
4. 4回連続で自動解除された場合も、以後は本規約に従いサブエージェント選択を行う

### `[WORKER-HAIKU-FILE-CHANGE-BLOCK]` 受信（worker-haiku 内部で発生）

1. worker-haiku はそのコマンドを再試行せず、「ファイル変更のため実行不可」と報告して停止する
2. 委任元（main / brain）は当該作業を worker-sonnet に委任し直す
3. 委任元は以後、worker-haiku にはファイル変更を伴わないコマンドのみを渡す（委任判定フロー Q6 を参照）

## 設計判断

### check-worker-haiku-file-change.test.sh

**必要性**: `check-worker-haiku-file-change.sh`（旧 `check-worker-haiku-bash.sh`）は worker-haiku のファイル変更コマンドを exit 2 で block する PreToolUse hook であり、G1〜G9（素通り）・B1〜B10（block）の 19 ケースを網羅する回帰テストが既に存在する。hook 本体のリネームに追従してテストファイルもリネームし、内部の `HOOK=` パス参照とヘッダコメントを更新した。回帰テストなしに hook ロジックを変更すると、素通り条件（git 定型操作・パイプ・リダイレクト以外の許可コマンド）の退行を検知できない。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 19 ケースを毎回手動実行するとトークンを浪費し、hook 修正のたびに同じ確認作業を繰り返すことになる
- 既存 Makefile ターゲット拡張: `~/.claude/rules/` 配下に Makefile は存在せず、新規導入は本テスト専用の依存を増やすだけになる
- package.json scripts 追加: 同様に本ディレクトリはビルド設定を持たない

**保守責任者**: 人手（ユーザー）。`check-worker-haiku-file-change.sh` の block/許可条件を変更するたびに本テストのケースを追従させる。

**廃棄条件**: `check-worker-haiku-file-change.sh` 自体が廃止された時。

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: 委任判定・検証義務はエージェント行動規範であり、プロジェクトに依存しないため受け口を設けない

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。
