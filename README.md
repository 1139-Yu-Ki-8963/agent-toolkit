# agent-toolkit

Claude Code のスキルとフックを「ライフサイクル」として管理する meta スキル集。

スキルやフックを作るだけで終わらせない。**作成 → 観点ベース静的レビュー → 白紙状態サブエージェントによる実機検証** までを 1 動線で連鎖させる。

## 同梱スキル

| スキル | 担当 |
|---|---|
| [`managing-skills`](skills/managing-skills/SKILL.md) | SKILL.md のライフサイクル（作成・観点ベース静的レビュー・発火実機検証） |
| [`managing-hooks`](skills/managing-hooks/SKILL.md) | settings.json hooks のライフサイクル（作成・公式仕様準拠＋設計健全性監査・実機 bash 発火検証） |

## 設計仕様（人間用）

| ドキュメント | 内容 |
|---|---|
| [`docs/skill-design.html`](docs/skill-design.html) | Skill 設計ガイド（§1〜§12: 定義 / 判定 / 分類 / 起動モデル / 命名 / description 規律 / ツール選択 / フォルダ構造 / 本文ルール / セットアップ・記憶・on-demand フック / テンプレート方針 / frontmatter テンプレート） |
| [`docs/hooks-design.html`](docs/hooks-design.html) | Hooks 設計ガイド（§1〜§9: 基本原則 / 禁止配置 / 配置決定 2 軸 / 4 象限 / 既存 hook 配置例 / 一覧化 / 機械強制 / legacy 扱い / 命名・ADR） |

ローカルに clone してブラウザで開くとスタイル付きで読めます（`docs/style.css` 同梱）。

### 人 / AI の住み分け（重要）

| 読み手 | 参照先 | 理由 |
|---|---|---|
| **人間** | `docs/skill-design.html` / `docs/hooks-design.html` | スタイル付きで設計思想・rationale 込みで読める正本 |
| **AI（スキル実行時）** | `skills/managing-skills/references/conventions.md` / `skills/managing-hooks/references/conventions.md` | 自己完結した縮約版。Stage 3 で追加 Read せずに作業材料が揃う |

**意図的に同じ内容を 2 フォーマットで保持** しています。AI に docs/ を Read させると Stage 3 ロードが増えて遅くなるため、AI 用は conventions.md に self-contained で持たせています。設計内容の正本は docs/ HTML 側、conventions.md は AI 用の縮約。齟齬が出たら docs/ が優先。

## 設計思想

- **作りっぱなしを許さない**: 書いた直後に静的監査・実機検証まで連鎖
- **共通規約の単一正本化**: フロントマター / Type / TAG / event 別パターン / timeout 目安 / 配置 4 象限は `references/conventions.md` に集約
- **段階的開示 (Progressive Disclosure)**: ハブ本体は 100〜150 行の振り分けのみ。各モードの詳細は `references/` に分離し必要時のみロード
- **diagnose を review に吸収**: 設計面 5 観点（複雑度・無限ループ・解釈曖昧さ・コンテキスト直書き・カテゴリ整合性）は review モードの dry-run で実行

## 自動連鎖

```
create モード ──→ review モード ──→ test モード
   ↑                  ↑                  ↑
   独立起動も可        独立起動も可        独立起動も可
```

- `create` 完了時に **自動で `review` へ**
- `review` 完了時に **自動で `test` へ**
- 連鎖を止めたい場合は `AskUserQuestion` で明示中断

## インストール

リポジトリを clone し、各スキルディレクトリを Claude Code の `~/.claude/skills/` 配下にコピーまたはリンク:

```bash
git clone https://github.com/1139-Yu-Ki-8963/agent-toolkit.git
cp -R agent-toolkit/skills/managing-skills ~/.claude/skills/
cp -R agent-toolkit/skills/managing-hooks ~/.claude/skills/
```

または symlink:

```bash
ln -s "$(pwd)/agent-toolkit/skills/managing-skills" ~/.claude/skills/managing-skills
ln -s "$(pwd)/agent-toolkit/skills/managing-hooks" ~/.claude/skills/managing-hooks
```

プロジェクト固有で使う場合は `<repo>/.claude/skills/` に配置。

## 使い方

### スキルを作る

```
> 新しいスキルを作りたい
```

`managing-skills` の create モードが起動し、`conventions.md` の規約をロード → SKILL.md を Write → 自動的に review → test まで連鎖。

### フックを作る

```
> PreToolUse の hook を作って
```

`managing-hooks` の create モードが起動し、配置 4 象限を判定 → hook script を Write → ADR 作成 → settings.json 登録 → 自動 review → test。

### 既存スキル / hook をレビュー

```
> このスキルをレビューして
> hooks をレビューして
```

観点 A〜G（managing-skills は 26 項目）または観点 A〜H + I〜M（managing-hooks は 43 項目）で静的解析 → CRITICAL / WARN / INFO を分類 → ユーザー承認のうえ自動修正 → test モードへ連鎖。

### 読み取り専用診断（hooks のみ）

```
> hooks の無限ループリスクを見て
> hooks を診断したい
```

`managing-hooks` の review モードが **dry-run** で起動し、設計面 5 観点（I〜M）のみで読み取り専用診断。

## ディレクトリ構成

```
agent-toolkit/
├── README.md
├── docs/                              # 人間用：設計仕様（HTML + CSS）
│   ├── skill-design.html
│   ├── hooks-design.html
│   └── style.css
└── skills/
    ├── managing-skills/
    │   ├── SKILL.md                 # ハブ
    │   ├── references/
    │   │   ├── conventions.md       # 共通規約の単一正本
    │   │   ├── creating.md          # create モード手順
    │   │   ├── reviewing.md         # review モード観点 A〜G
    │   │   ├── testing.md           # test モードのワークフロー
    │   │   ├── check-items.md       # 観点別 grep / python 検出式
    │   │   ├── folder-structure.md
    │   │   ├── description-examples.md
    │   │   ├── anti-patterns.md
    │   │   └── advanced-techniques.md
    │   └── assets/
    │       └── template-{手順型,条件付き知識型,強制型}.md
    └── managing-hooks/
        ├── SKILL.md
        └── references/
            ├── conventions.md       # JSON スキーマ / TAG / 8 event / timeout / 配置 4 象限
            ├── creating.md
            ├── reviewing.md         # 観点 A〜H（公式仕様） + I〜M（設計健全性）
            ├── testing.md
            ├── check-items.md       # jq / grep 検出式
            ├── event-recipes.md
            ├── examples.md
            └── output-schema.md
```

## 要件

- [Claude Code](https://docs.claude.com/en/docs/claude-code) （skill ローダー）
- bash / jq / python3 （review モードの検出式が依存）
