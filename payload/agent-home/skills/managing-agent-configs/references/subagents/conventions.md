# サブエージェント規約（正本）

全モード（create / review / test）で最初に読む単一正本。

## 配置先

```
~/.claude/agents/<name>/<name>.md
```

1 サブエージェント = 1 ディレクトリ。ディレクトリ名・ファイル名・frontmatter `name` の 3 つが完全一致すること。

## frontmatter 必須フィールド

| フィールド | 型 | 制約 |
|---|---|---|
| `name` | string | kebab-case, 64 字以内, dir 名・file 名と一致 |
| `description` | multiline | 1 行目 50 字以内 + `TRIGGER when:` + `SKIP:` |
| `tools` | comma-separated | 最小権限。使用するツールのみ |
| `model` | string | 明示モデル ID を指定する（例: `claude-opus-4-8` / `claude-sonnet-5` / `claude-haiku-4-5-20251001`）。エイリアス（`opus` / `sonnet` / `haiku`）は CLI の更新で解決先が黙って変わるため禁止 |

`TRIGGER when:` / `SKIP:` は固定英語キーワード。`Use when:` や `使用時:` はシステムが認識しない。

## 4 役割判定フロー

```
Q1. タスクの分解・計画・結果検証が必要か？
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

新規役割を追加するのは、既存 6 役割で不足する専門性がある場合のみ。

## ツール選択基準

| 役割パターン | 推奨ツール | 禁止ツール |
|---|---|---|
| 計画・検証系 (brain) | Read, Grep, Glob, Bash | Write, Edit |
| 調査・分析系 (investigator) | Read, Grep, Glob, Bash | Write, Edit |
| 調査・修正系 (worker-sonnet) | Read, Write, Edit, Bash, Grep, Glob | Agent |
| 実行専用系 (worker-haiku) | Bash, Read | Write, Edit, Grep, Glob, Agent |
| 外部調査系 (researcher) | MCP 各種, WebSearch, WebFetch, Read, Grep, Glob | Write, Edit |
| 事実性検証系 (reviewer) | Read, Bash, Grep, Glob | Write, Edit |

- `Agent` ツールを subagent に付与すると再帰呼び出しが発生する。原則禁止
- 計画者（brain）に Write/Edit を与えない理由: 計画と実装を分離して品質管理する
- 実行専用系（worker-haiku）に Write/Edit を与えない理由: 低コストモデルにファイル変更をさせない。編集の品質判断は sonnet 以上が担い、haiku は「指示にベタ書きされたコマンドの実行と結果報告」に限定する。Bash 経由のファイル変更（`sed -i`・リダイレクト等）は本文の禁止事項に加え、`worker-haiku-bash-guard.sh`（PreToolUse(Bash)、`agent_type` で判定）が機械的に block する。プロンプトの禁止事項だけでは haiku の遵守が不安定なことが実機検証で確認済み
- **注意（実測）**: エージェント定義はセッション開始時（または初回ディスパッチ時）に読み込まれ、セッション中の定義編集は既存セッションのディスパッチに反映されない。定義変更のテストは新しいセッションで行うこと

## 本文構成ルール

| 制約 | 上限 |
|---|---|
| 本文行数 | 100 行以内 |
| セクション数 | 2〜4 |
| 見出し言語 | 日本語統一 |
| 絶対パス | 禁止（`~/` 形式を使う） |

本文は「人格と専門性」を定義する。手順書ではない。詳細な手順は `references/` に分離する。

MCP ツールに依存する subagent は、定義 md 内に前提 MCP サーバーの節を書く（例: `researcher` の「前提 MCP サーバー」節）。

## references ディレクトリ

- 必要な場合のみ作成。全 subagent に必要なわけではない
- 本文が 50 行を超えそうな詳細を逃がす先
- subagent 固有の知識のみ。汎用パターンは skill や rules に置く
- 可変データ（ログ・状態）は `~/.claude/agents/` 配下に置かない

## 既存エージェントの一覧

既存エージェントの一覧と分類（reviewer を含む）は `~/agent-home/ai-management-portal/catalog/subagents.html` を参照。reviewer は「他者の調査報告の事実性検証（チェックリスト照合・裏取り）」を担う事実性検証系で、4 役割判定フローには登場しないが `investigator` / `brain` の結果検証ステップから呼ばれる。
