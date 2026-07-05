# サブエージェント静的レビュー手順

## Phase 一覧

| Phase | 内容 |
|---|---|
| 1 | 対象発見 |
| 2 | 静的解析（観点 A〜D） |
| 3 | 実体検証 |
| 4 | レポート |
| 5 | 自動修正承認 |

## Phase 1: 対象発見

```bash
find ~/.claude/agents/ -name "*.md" -not -path "*/references/*" | sort
```

レビュー対象を特定し、一覧表示する。ユーザーが対象を指定済みなら省略。

## Phase 2: 静的解析

### 観点 A: frontmatter / メタデータ（5 項目）

| ID | 観点 | 重大度 | 検証方法 |
|---|---|---|---|
| A1 | `name` が kebab-case かつ dir 名・file 名と一致 | CRITICAL | `basename` と `dirname` を突合 |
| A2 | `description` に TRIGGER when + SKIP が存在 | CRITICAL | `grep -c "TRIGGER when" && grep -c "SKIP:"` |
| A3 | `description` 1 行目が 50 字以内 | WARN | 文字数カウント |
| A4 | `model` が明示モデル ID（`claude-opus-4-8` / `claude-sonnet-5` / `claude-haiku-4-5-20251001` 等）。エイリアス（`opus` / `sonnet` / `haiku`）は禁止 | CRITICAL | 値の突合 |
| A5 | `tools` に禁止ツールが含まれていない | CRITICAL | conventions.md のツール選択基準と突合 |

### 観点 B: 本文品質（4 項目）

| ID | 観点 | 重大度 | 検証方法 |
|---|---|---|---|
| B1 | 本文 100 行以内 | WARN | `wc -l` |
| B2 | 出力フォーマットが定義されている | WARN | `grep -i "出力"` |
| B3 | セクション数が 2〜4 | INFO | `grep -c "^##"` |
| B4 | 見出しが日本語統一 | INFO | 目視確認 |

### 観点 C: 単一責任（3 項目）

| ID | 観点 | 重大度 | 検証方法 |
|---|---|---|---|
| C1 | 責務が 1 つに集中している | CRITICAL | description 1 行目の述語数 |
| C2 | 他 subagent との責務境界が明確 | WARN | SKIP の代替先と全 subagent の TRIGGER を突合 |
| C3 | 計画者が実装を兼ねていない / 調査者が修正を兼ねていない | CRITICAL | tools の Write/Edit 有無で判定 |

### 観点 D: references 健全性（3 項目）

| ID | 観点 | 重大度 | 検証方法 |
|---|---|---|---|
| D1 | references に可変データが置かれていない | CRITICAL | ファイル内容の目視 |
| D2 | references が subagent 固有の知識である | WARN | 汎用パターンは skill/rules に属する |
| D3 | 本文から references への参照が適切 | INFO | 本文内の言及確認 |

## Phase 3: 実体検証

- frontmatter の `tools` に列挙されたツールが実在するか
- `model` の値が有効か
- references/ 内のファイルが存在し、空でないか

## Phase 4: レポート

```
## レビュー結果: <subagent-name>

| 重大度 | 件数 |
|---|---|
| CRITICAL | N |
| WARN | N |
| INFO | N |

### 検出事項
- [CRITICAL] A1: name が dir 名と不一致 ...
- [WARN] B1: 本文 120 行（上限 100 行）...

### 健全性判定
- CRITICAL = 0 → PASS（test 連鎖可）
- CRITICAL > 0 → FAIL（修正必須）
```

## Phase 5: 自動修正承認

CRITICAL / WARN の検出事項に対して修正案を提示し、`AskUserQuestion` で承認を得てから適用する。

修正可能なもの:
- frontmatter のフィールド修正（name 不一致、tools 過剰）
- 本文の行数削減（references への分離）
- 見出しの日本語統一

修正不可能なもの（設計判断が必要）:
- 責務の分割
- 役割パターンの変更
- references の構造変更
