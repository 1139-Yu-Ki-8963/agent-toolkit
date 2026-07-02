# サブエージェント作成手順

## 前提チェック（作成前）

1. 既存 4 役割（brain / worker-sonnet / worker-haiku / researcher）で対応できないか確認
2. `conventions.md` の 4 役割判定フローで、既存に該当しないことを確認
3. 新規役割が必要な理由を 1 文で説明できるか確認

## 作成手順

### Step 1: 役割の決定

- 既存 4 役割の拡張か、完全新規かを判断
- 完全新規の場合: 判定フローに当てはまらない専門性を明文化
- name を kebab-case で決定（`conventions.md` の命名規約に従う）

### Step 2: frontmatter の記述

```yaml
---
name: <kebab-case-name>
description: |
  <50 字以内の責務説明。能動文で 1 文>
  TRIGGER when: <具体的なキーワード・操作名を列挙>
  SKIP: <非対象条件と代替 subagent を明示>
tools: <comma-separated list>
model: <opus | sonnet | haiku>
---
```

チェック:
- `name` = ディレクトリ名 = ファイル名（拡張子除く）
- `tools` は最小権限（`conventions.md` のツール選択基準を参照）
- `model` は役割パターンに適合

### Step 3: 本文の記述

```markdown
# <Name>: <役割の要約>

<1-2 文の責務説明>

## <モード or 得意な作業>

<具体的な作業項目のリスト>

## 出力フォーマット

<返却する結果の構造>
```

制約:
- 100 行以内
- 2〜4 セクション
- 見出し日本語統一
- 「人格と専門性」を定義する。手順書にしない

### Step 4: references の作成（必要な場合のみ）

- 本文が 50 行を超えそうな詳細があるとき
- subagent 固有の知識を分離するとき
- `~/.claude/agents/<name>/references/<topic>.md` に配置

### Step 5: ディレクトリの作成と配置

```bash
mkdir -p ~/.claude/agents/<name>/references  # references 不要なら省略
```

ファイル配置:
```
~/.claude/agents/<name>/
├── <name>.md
└── references/        # 必要な場合のみ
    └── <topic>.md
```

## 作成後チェックリスト

| # | 項目 | 検証 |
|---|---|---|
| 1 | `name` が kebab-case かつ dir/file と一致 | `ls ~/.claude/agents/<name>/` |
| 2 | `description` に TRIGGER when + SKIP | `grep "TRIGGER when" <file>` |
| 3 | `tools` が最小権限 | conventions.md と突合 |
| 4 | `model` が役割に適合 | conventions.md と突合 |
| 5 | 本文 100 行以内 | `wc -l <file>` |
| 6 | 出力フォーマットが定義されている | `grep "出力" <file>` |
| 7 | 既存 subagent との責務境界が明確 | SKIP の代替先確認 |
| 8 | references に可変データがない | 目視確認 |
