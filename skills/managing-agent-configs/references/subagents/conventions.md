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
| `model` | string | `opus` / `sonnet` / `haiku` のいずれか |

`TRIGGER when:` / `SKIP:` は固定英語キーワード。`Use when:` や `使用時:` はシステムが認識しない。

## 4 役割判定フロー

```
Q1. タスクの分解・計画・結果検証が必要か？
    YES → brain (model: opus)
    NO  → Q2

Q2. 外部情報（Web・API・ライブラリ仕様）が必要か？
    YES → researcher (model: sonnet)
    NO  → Q3

Q3. 作業に判断が必要か？
    YES → worker-sonnet (model: sonnet)
    NO  → worker-haiku (model: haiku)
```

新規役割を追加するのは、既存 4 役割で不足する専門性がある場合のみ。

## ツール選択基準

| 役割パターン | 推奨ツール | 禁止ツール |
|---|---|---|
| 計画・検証系 (brain) | Read, Grep, Glob, Bash | Write, Edit |
| 調査・修正系 (worker-sonnet) | Read, Write, Edit, Bash, Grep, Glob | Agent |
| 機械的実行系 (worker-haiku) | Read, Write, Edit, Bash, Grep, Glob | Agent |
| 外部調査系 (researcher) | MCP 各種, WebSearch, WebFetch, Read, Grep, Glob | Write, Edit |

- `Agent` ツールを subagent に付与すると再帰呼び出しが発生する。原則禁止
- 計画者（brain）に Write/Edit を与えない理由: 計画と実装を分離して品質管理する

## 本文構成ルール

| 制約 | 上限 |
|---|---|
| 本文行数 | 100 行以内 |
| セクション数 | 2〜4 |
| 見出し言語 | 日本語統一 |
| 絶対パス | 禁止（`~/` 形式を使う） |

本文は「人格と専門性」を定義する。手順書ではない。詳細な手順は `references/` に分離する。

## references ディレクトリ

- 必要な場合のみ作成。全 subagent に必要なわけではない
- 本文が 50 行を超えそうな詳細を逃がす先
- subagent 固有の知識のみ。汎用パターンは skill や rules に置く
- 可変データ（ログ・状態）は `~/.claude/agents/` 配下に置かない

## 既存 4 役割一覧

| name | model | 責務 | references |
|---|---|---|---|
| brain | opus | 計画・判断・検証 | planning.md, reviewing.md |
| worker-sonnet | sonnet | 文脈を読んで調査・修正 | patterns.md |
| worker-haiku | haiku | 機械的タスクの高速実行 | なし |
| researcher | sonnet | MCP で外部情報収集 | なし |
