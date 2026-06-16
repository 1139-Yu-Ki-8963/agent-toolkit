# スキル設計のアンチパターン

スキル作成時にやってはいけないこと（アンチパターン）をまとめます。
これらを避けることで、保守性が高く効率的なスキルを作成できます。

---

## 1. 公式ドキュメントのコピー

### やってはいけないこと

```
creating-skills/
├── SKILL.md
└── references/
    └── skills.md  ← ❌ /docs/skills.md のコピー
```

**問題点**:
- `/docs/skills.md` と内容が重複
- 更新時に2箇所を同期する必要がある
- 片方だけ更新され、情報が乖離するリスク
- ストレージの無駄遣い

### 正しい方法

```markdown
## 参照資料

Claude Skills の全体仕様については `/docs/skills.md` を参照してください。
```

**ポイント**: コピーせず、参照リンクで済ませる

---

## 2. 巨大な SKILL.md

### やってはいけないこと

```markdown
# My Skill

（1000行以上の巨大なドキュメント）
- すべての例
- すべてのパターン
- すべてのトラブルシューティング
- すべての詳細仕様
```

**問題点**:
- トリガー発動のたびに大量のトークンを消費
- 応答が遅くなる
- 必要な情報を見つけにくい
- Progressive Disclosure の利点を活かせない

### 正しい方法

```
my-skill/
├── SKILL.md              # 500行以下: コア仕様のみ
└── references/
    ├── examples.md       # 詳細な例
    ├── patterns.md       # パターン集
    └── troubleshooting.md # トラブルシューティング
```

**目安**:
- SKILL.md: 500行 / 5000トークン以下
- 詳細は references/ に分離

---

## 3. 汎用的な内容を references/ に配置

### やってはいけないこと

```
my-skill/
└── references/
    ├── git-basics.md      ← ❌ 汎用的な Git の基礎
    ├── markdown-guide.md  ← ❌ 汎用的な Markdown ガイド
    └── coding-standards.md ← ❌ 全プロジェクト共通のコーディング規約
```

**問題点**:
- 他のスキルでも使える内容が特定スキルに閉じ込められる
- 同じ内容が複数スキルに重複する可能性
- references/ の本来の役割（スキル固有の詳細）から逸脱

### 正しい方法

```
docs/
├── git-basics.md          # 汎用的な情報は /docs/ に
├── markdown-guide.md
└── coding-standards.md

skills/my-skill/
└── references/
    └── my-skill-specific.md  # このスキル固有の情報のみ
```

**判断基準**: 「この情報は他のスキルでも使うか？」
- YES → `/docs/` に配置
- NO → `references/` に配置

---

## 4. 曖昧な description

### やってはいけないこと

```yaml
# ❌ 悪い例
description: プロジェクトを管理するスキル
description: 開発を支援するツール
description: 便利な機能を提供
```

**問題点**:
- いつ発動するか不明
- Claude がマッチングできない
- 手動で呼び出す必要がある（自動発動の利点を活かせない）

### 正しい方法

```yaml
# ✅ 良い例
description: プロジェクト作成時、新規リポジトリ初期化時、ディレクトリ構成を決める際に使用。テンプレートに基づいた標準構成を自動生成し、必須ファイルの作成漏れを防止。
```

**必須要素**: 「何をするか」+「いつ使うか」

---

## 5. 1つの巨大スキルに全部詰め込む

### やってはいけないこと

```
super-skill/
├── SKILL.md  ← 2000行: Git + デプロイ + テスト + ドキュメント + ...
```

**問題点**:
- 関係ない機能もすべてロードされる
- トークン消費が増大
- 保守が困難
- 一部の機能を更新すると全体に影響

### 正しい方法

```
skills/
├── git-workflow/
│   └── SKILL.md
├── deployment/
│   └── SKILL.md
├── testing/
│   └── SKILL.md
└── documentation/
    └── SKILL.md
```

**原則**: 1スキル = 1機能（Single Responsibility Principle）

---

## 6. スクリプトを SKILL.md に直接書く

### やってはいけないこと

```markdown
# My Skill

以下のスクリプトを実行:

```bash
#!/bin/bash
# 100行以上の複雑なスクリプト
for file in $(find . -name "*.md"); do
    # 複雑な処理
done
```
```

**問題点**:
- SKILL.md が肥大化
- スクリプトの再利用が困難
- バージョン管理が難しい

### 正しい方法

```
my-skill/
├── SKILL.md
└── scripts/
    └── process-files.sh  # スクリプトは分離
```

```markdown
# My Skill

以下のスクリプトを実行:

```bash
~/.claude/skills/my-skill/scripts/process-files.sh
```
```

---

## 7. `!` 構文の使用

### やってはいけないこと

```markdown
!~/.claude/scripts/my-script.sh
```

**問題点**:
- Claude Code でのみ動作
- Cursor では実行されない

### 正しい方法

```markdown
```bash
~/.claude/scripts/my-script.sh
```
```

**理由**: Bash コードブロックは両方で動作する

---

## 8. AI の動作に依存する設計

### やってはいけないこと

```markdown
## ルール

- この SKILL.md を読んだら、必ず〇〇を実行すること
- AI は常にこの指針に従うこと
```

**問題点**:
- AI の動作は100%保証されない
- ルールを破る可能性がある

### 正しい方法

```markdown
## ワークフロー

1. まず以下のスクリプトを実行:
   ```bash
   ~/.claude/scripts/check-prerequisites.sh
   ```

2. スクリプトの出力に基づいて判断
```

**原則**: 仕組みとして確実に動作する設計を優先

---

## 9. 長すぎる description

### やってはいけないこと

```yaml
# ❌ 悪い例（432文字）
description: |
  スキルの新規作成・追加・設計・実装・計画立案を行う時に必ず使用するガイド。
  TRIGGER when: 「スキルを作る/作成/追加/書く/実装/設計」「skillsを作る/作成/追加/書く/実装/設計」
  「新しいスキル」「SKILL.mdを作る/作成/書く」「スキルを考えて/ドラフト/計画」
  「skillsの作成/設計/計画を立てて」「~/.claude/skills/に追加」「skillsフォルダ」
  「create/make/add/build/write a skill」「create/add/build/write skills」「new skill(s)」
  「skill creation/design/plan」など、スキル新規作成に関わるあらゆる要求時。
  SKIP: 既存スキルを実行・呼び出す時; スキルの説明や一覧を確認するだけの時。
```

**問題点**:
- 全スキルの description 合計には **8,000文字の予算**がある
- 1スキルが長いほど他のスキルの description がドロップされるリスクが上がる
- Claude Code 起動時に「N skill descriptions dropped」が発生し、後ろのスキルが自動選択不能になる

### 正しい方法

```yaml
# ✅ 良い例（207文字）
description: |
  スキル（SKILL.md）の新規作成・追加・設計・リファクタリング時に必ず使用するガイド。
  TRIGGER when: 「スキルを作る/作成/追加/設計」「新しいスキル」「SKILL.mdを作る」「create/add a skill」など新規作成に関わる要求時。既存スキルの改善・リファクタリング時も含む。
  SKIP: 既存スキルの実行・呼び出し、一覧確認のみの時。
```

**ルール**:
- 1スキルあたり: 説明文（TRIGGER 行より前）は**50字以内**
- 全スキル合計: **2,000文字以内**
- TRIGGER when の例示は代表的なキーワード 3〜5 語に絞る

---

## チェックリスト

スキル作成前に確認:

- [ ] description の説明文（TRIGGER 行より前）が **50字以内**か
- [ ] 追加後も全スキル合計が **2,000文字以内**か
- [ ] 公式ドキュメントをコピーしていないか
- [ ] SKILL.md が500行以下か
- [ ] references/ にはスキル固有の内容のみか
- [ ] description が具体的か（トリガー条件を含むか）
- [ ] 1スキル = 1機能になっているか
- [ ] スクリプトは scripts/ に分離しているか
- [ ] `!` 構文を使っていないか
- [ ] AI の動作に依存していないか
