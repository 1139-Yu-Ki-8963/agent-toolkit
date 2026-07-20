# サブエージェント規約（正本）

全モード（create / review / test）で最初に読む単一正本。

## 配置先

```
~/.claude/agents/<name>/<name>.md
```

- `~/.claude/agents` は `~/agent-home/agents` への symlink（正本は agent-home リポジトリ）
- 1 サブエージェント = 1 ディレクトリ。ディレクトリ名・ファイル名・frontmatter `name` の 3 つが完全一致すること
- 公式仕様では `.claude/agents/` 配下のサブフォルダも走査対象になる。`references/` 内の md には frontmatter（特に `name:`）を書かないこと（エージェント定義と誤認識されるリスクを避ける）
- 配置 3 層の優先順位（公式）: managed > project（`<repo>/.claude/agents/`）> user（`~/.claude/agents/`）

## frontmatter フィールド（公式サポート一覧と本環境の規約）

公式ドキュメント（https://code.claude.com/docs/en/sub-agents）がサポートするフィールドと、本環境での使用規約。**この表に無いフィールドは typo か公式廃止の疑い**として review 観点 A6 で検出する。

| フィールド | 公式 | 本環境の規約 |
|---|---|---|
| `name` | 必須 | kebab-case, 64 字以内, dir 名・file 名と一致 |
| `description` | 必須 | 1 行目 50 字以内 + `TRIGGER when:` + `SKIP:`（後述） |
| `tools` | 任意（省略時: 親の全ツールを継承） | **明示必須**。省略は全ツール継承となり最小権限違反（観点 A7 で CRITICAL） |
| `model` | 任意（省略時: 親を継承。エイリアス可） | **明示モデル ID 必須**（例: `claude-opus-4-8` / `claude-sonnet-5` / `claude-haiku-4-5-20251001`）。エイリアス（`opus` / `sonnet` / `haiku`）は CLI の更新で解決先が黙って変わるため禁止 |
| `disallowedTools` | 任意（拒否リスト方式） | 原則不使用。`tools`（許可リスト）との併用不可（公式仕様: 許可リスト優先）。使う場合は理由を本文に明記 |
| `permissionMode` | 任意 | 原則不使用（親の継承に任せる）。使用時は理由を本文に明記 |
| `mcpServers` | 任意（インライン MCP 接続） | MCP 依存エージェント（researcher 等）で検討可。定義 md 内に前提 MCP サーバー節を書く |
| `skills` | 任意（起動時プリロード） | 使用可。プリロード対象スキルの実在を review で確認 |
| `memory` | 任意（永続メモリディレクトリ） | 原則不使用（可変データを agents/ 配下に置かない方針と整合させる。導入時は設計判断を記録） |
| `background` | 任意 | 原則不使用（バックグラウンド起動は呼び出し側の subagent-selection 規約が制御） |
| `hooks` | 任意（活動中のみ有効な hook） | 原則不使用。使用時は managing-agent-configs の hooks 種別レビューを併用 |
| `isolation` | 任意（`worktree`） | 並列ファイル変更を伴う場合のみ検討 |

### description の書き方

`TRIGGER when:` / `SKIP:` は**本環境のローカル慣行**（呼び出し元 Claude が委任判定に使う書式統一）であり、公式の予約語ではない。公式は description 全文を自動委任のマッチング材料として使い、「use proactively」等の書き方を推奨している。本環境で書式を統一する理由は、subagent-selection 規約の委任判定フローとレビュー観点 C（責務境界）が TRIGGER / SKIP の構造を前提に機械照合するため。

## 役割体系（11 エージェント・4 分類）

subagent-selection 規約（`~/.claude/rules/always/agent/subagent-selection/rule.md`）の 4 分類と対応する。

| 分類 | エージェント | model |
|---|---|---|
| 計画系 | brain | claude-opus-4-8 |
| 実行系 | worker-sonnet / worker-haiku | claude-sonnet-5 / claude-haiku-4-5-20251001 |
| 調査系 | investigator / researcher / plan-comprehension-prober / adversarial-verifier | claude-sonnet-5 / claude-sonnet-5 / claude-haiku-4-5-20251001 / claude-fable-5 |
| 判定系 | code-reviewer / document-reviewer / business-content-reviewer / report-reviewer | claude-sonnet-5 / claude-sonnet-5 / claude-sonnet-5 / claude-opus-4-8 |

### 役割判定フロー（委任先の選定）

Q1〜Q4 は「作業を誰に委任するか」の判定であり、到達役割は 5 種（brain / researcher / investigator / worker-sonnet / worker-haiku）。判定系 4 体はこのフローでは選ばず、成果物・報告の合否判定という後段の工程で reviewing-against-rules / report-reviewer 経由で呼ばれる。plan-comprehension-prober は eliciting-plan-tacit-knowledge スキル専用の読み手、adversarial-verifier は adversarial-verification スキル専用の反証役で、いずれもこのフローには登場しない。

```
Q1. タスクの分解・計画立案が必要か？（結果検証は判定系へ。brain は合否判定をしない）
    YES → brain (model: claude-opus-4-8)
    NO  → Q2

Q2. 外部情報（Web・API・ライブラリ仕様）が必要か？
    YES → researcher (model: claude-sonnet-5)
    NO  → Q3

Q3. 変更を伴わない調査・分析・根本原因特定か？
    YES → investigator (model: claude-sonnet-5)
          （読み取り専用。調査チェックリストの実行はここ）
    NO  → Q4

Q4. ファイルの作成・編集、または文脈判断が必要か？
    YES → worker-sonnet (model: claude-sonnet-5)
    NO  → worker-haiku (model: claude-haiku-4-5-20251001)
          （コマンド実行と結果報告のみ。ファイル変更は一切させない）
```

新規役割を追加するのは、既存 11 体で不足する専門性がある場合のみ。組み込みエージェント（Plan / Explore / claude-code-guide / general-purpose）と責務が重なる場合は、重複を許容する理由（model 固定・ツール制限・出力形式の統一等）を定義本文に書く。

## ツール選択基準

| 役割パターン | 推奨ツール | 禁止ツール |
|---|---|---|
| 計画系 (brain) | Read, Grep, Glob, Bash | Write, Edit |
| 調査・分析系 (investigator) | Read, Grep, Glob, Bash | Write, Edit |
| 調査・修正系 (worker-sonnet) | Read, Write, Edit, Bash, Grep, Glob | Agent |
| 実行専用系 (worker-haiku) | Bash, Read | Write, Edit, Grep, Glob, Agent |
| 外部調査系 (researcher) | MCP 各種, WebSearch, WebFetch, Read, Grep, Glob | Write, Edit |
| 判定系 (code-reviewer / document-reviewer / business-content-reviewer / report-reviewer) | Read, Bash, Grep, Glob | Write, Edit |
| 初見読解系 (plan-comprehension-prober) | Read | Read 以外すべて |

- `Agent` ツールを subagent に付与すると再帰呼び出しが発生する。原則禁止
- 計画者（brain）に Write/Edit を与えない理由: 計画と実装を分離して品質管理する
- 実行専用系（worker-haiku）に Write/Edit を与えない理由: 低コストモデルにファイル変更をさせない。編集の品質判断は sonnet 以上が担い、haiku は「指示にベタ書きされたコマンドの実行と結果報告」に限定する。Bash 経由のファイル変更（`sed -i`・リダイレクト等）は本文の禁止事項に加え、`check-worker-haiku-file-change.sh`（PreToolUse(Bash)、`agent_type` で判定）が機械的に block する。プロンプトの禁止事項だけでは haiku の遵守が不安定なことが実機検証で確認済み
- **注意（実測）**: エージェント定義はセッション開始時（または初回ディスパッチ時）に読み込まれ、セッション中の定義編集は既存セッションのディスパッチに反映されない。定義変更のテストは新しいセッションで行うこと

## 本文構成ルール

| 制約 | 上限 |
|---|---|
| 本文行数 | 100 行以内 |
| セクション数 | 2〜4 |
| 見出し言語 | 日本語統一 |
| 絶対パス | 禁止（`~/` 形式を使う） |

本文は「人格と専門性」を定義する。手順書ではない。詳細な手順は `references/` に分離する。

### 行動制約設計（レビュー観点 E の正本）

本文には次の 5 要素を含める。テスト設計事例（Zenn 記事 be13a2395a5d2a のスキル設計知見）からの転用。

1. **やらないことの明記**: 禁止事項・越権防止の制約を本文に書く（制約が無いと AI は越権・でっち上げをする）
2. **出力の厳格固定**: 出力フォーマットは項目構成・行数上限まで固定する
3. **不明の明示**: 未確認事項を推測で埋めず「不明」「証拠なし」と明示させる指示を含める
4. **根拠の要求**: 報告にファイルパス・実行コマンド・引用等の根拠を要求する
5. **合否権限の整合**: 合否（PASS / FAIL）を宣言できるのは判定系のみ。他分類の本文に合否宣言の記述を置かない

MCP ツールに依存する subagent は、定義 md 内に前提 MCP サーバーの節を書く（例: `researcher` の「前提 MCP サーバー」節）。

## references ディレクトリ

- 必要な場合のみ作成。全 subagent に必要なわけではない
- 本文が 50 行を超えそうな詳細を逃がす先
- subagent 固有の知識のみ。汎用パターンは skill や rules に置く
- 可変データ（ログ・状態）は `~/.claude/agents/` 配下に置かない
- references/ 内の md に frontmatter（特に `name:`）を書かない（配置先の節を参照）

## 既存エージェントの一覧

既存 11 体の一覧と分類は本ファイル「役割体系」節が一次情報。カタログ表示は `~/agent-home/ai-management-portal/catalog/subagents.html` を参照（正本 4 点突合の対象。レビュー観点 C7）。
