# agent-toolkit

Claude Code のスキルとフックを「ライフサイクル」として管理する meta スキル集。

スキルやフックを作るだけで終わらせない。**作成 → 観点ベース静的レビュー → 白紙状態サブエージェントによる実機検証** までを 1 動線で連鎖させる。

## 同梱スキル

| スキル | 担当 |
|---|---|
| [`managing-agent-configs`](skills/managing-agent-configs/SKILL.md) | エージェント構成 6 種（スキル・フック・ルール・ルーティン・サブエージェント・ワークフロー文書）のライフサイクル管理（作成・観点ベース静的レビュー・実機検証）。仕様書 HTML を [references/](skills/managing-agent-configs/references/managing-agent-configs-spec.html) に同梱 |
| [`syncing-reverse-env`](skills/syncing-reverse-env/SKILL.md) | ポート番号だけが違う 2 つの検証環境（固定 9100 / 9110 番台）を用意・同期し、完全一致の証明を基準タグ `reverse-baseline/{system}` として確立（git reset でいつでも復帰）。仕様書 HTML を [references/](skills/syncing-reverse-env/references/syncing-reverse-env-spec.html) に同梱 |

## 設計仕様（人間用）

`ai-management-portal/` に、本リポジトリに同梱しているスキルと設計ガイドだけを俯瞰できるポータルを同梱しています。ローカルに clone して `ai-management-portal/index.html` をブラウザで開くとスタイル付きで読めます。

| ドキュメント | 内容 |
|---|---|
| [`ai-management-portal/design/config-placement.html`](ai-management-portal/design/config-placement.html) | 設定層 配置判定ガイド — 「どこに書くか」を決定木で判定する横断ガイド。7 層の使い分けを一枚で参照 |
| [`ai-management-portal/design/claude-md.html`](ai-management-portal/design/claude-md.html) | CLAUDE.md 設計ガイド — ロードタイミング・サイズ制約・書く/書かない判定フロー |
| [`ai-management-portal/design/rules.html`](ai-management-portal/design/rules.html) | Rules 設計ガイド — eager/lazy 注入戦略・カテゴリ分類・hook script 同居原則 |
| [`ai-management-portal/design/skill.html`](ai-management-portal/design/skill.html) | Skill 設計ガイド — 定義 / 判定 / 分類 / 起動モデル / 命名 / description 規律 / ツール選択 / フォルダ構造 |
| [`ai-management-portal/design/hooks.html`](ai-management-portal/design/hooks.html) | Hooks 設計ガイド — 基本原則 / 禁止配置 / 配置決定 2 軸 / 4 象限 / 機械強制 / 命名・設計判断 |
| [`ai-management-portal/design/subagent.html`](ai-management-portal/design/subagent.html) | Subagent 設計ガイド — 4 役割アーキテクチャ・frontmatter 仕様・references 構造・品質基準 |
| [`ai-management-portal/design/loop.html`](ai-management-portal/design/loop.html) | Loop 設計ガイド — 繰り返し実行の設計原則・5 アクション・6 パーツ・評価役の分離 |

同梱スキルの実体一覧は [`ai-management-portal/catalog/skills.html`](ai-management-portal/catalog/skills.html) から参照できます。

### 人 / AI の住み分け（重要）

| 読み手 | 参照先 | 理由 |
|---|---|---|
| **人間** | `ai-management-portal/design/skill.html` / `ai-management-portal/design/hooks.html` | スタイル付きで設計思想・rationale 込みで読める正本 |
| **AI（スキル実行時）** | `skills/managing-agent-configs/references/skills/conventions.md` / `skills/managing-agent-configs/references/hooks/conventions.md`（他の種別は `references/<type>/conventions.md`、`<type>` は skills / hooks / rules / routines / subagents / workflows） | 自己完結した縮約版。Stage 3 で追加 Read せずに作業材料が揃う |

**意図的に同じ内容を 2 フォーマットで保持** しています。AI に design/ を Read させると Stage 3 ロードが増えて遅くなるため、AI 用は conventions.md に self-contained で持たせています。設計内容の正本は design/ HTML 側、conventions.md は AI 用の縮約。齟齬が出たら design/ が優先。

## 設計思想

- **作りっぱなしを許さない**: 書いた直後に静的監査・実機検証まで連鎖
- **共通規約の単一正本化**: フロントマター / Type / TAG / event 別パターン / timeout 目安 / 配置 4 象限は種別ごとの `references/<type>/conventions.md` に集約
- **段階的開示 (Progressive Disclosure)**: ハブ本体は種別判定・モード判定・ロード指示のみ。各モードの詳細は `references/<type>/` に分離し必要時のみロード
- **diagnose を review に吸収**: 設計面 5 観点（複雑度・無限ループ・解釈曖昧さ・コンテキスト直書き・カテゴリ整合性）は review モードの dry-run で実行

## 自動連鎖

```
create モード ──→ review モード ──→ test モード
   ↑                  ↑                  ↑
   独立起動も可        独立起動も可        独立起動も可
```

- `create` 完了時に **自動で `review` へ**（`workflows` 種別のみ単発で連鎖なし）
- `review` 完了時に **自動で `test` へ**
- 連鎖を止めたい場合は `AskUserQuestion` で明示中断

## インストール

リポジトリを clone し、スキルディレクトリを Claude Code の `~/.claude/skills/` 配下にコピーまたはリンク:

```bash
git clone https://github.com/1139-Yu-Ki-8963/agent-toolkit.git
cp -R agent-toolkit/skills/managing-agent-configs ~/.claude/skills/
```

または symlink:

```bash
ln -s "$(pwd)/agent-toolkit/skills/managing-agent-configs" ~/.claude/skills/managing-agent-configs
```

プロジェクト固有で使う場合は `<repo>/.claude/skills/` に配置。

### 機械強制フック（任意）

`skills/managing-agent-configs/scripts/` に、managed ファイル（`skills/*/SKILL.md` / `.claude/rules/*/rule.md` / `routines/*/ルーティン設計書.md` / `tools/hooks/*.sh`）の編集を検知して `managing-agent-configs` の実行を促し、テスト未完了のまま commit するのを block する hook 2 本を同梱しています。

- `managing-review-gate.sh` — PostToolUse(Write\|Edit\|MultiEdit)。managed ファイル編集時に `[MANAGING-REVIEW-REQUIRED]` を advisory 注入
- `managing-commit-gate.sh` — PreToolUse(Bash)。テスト完了マーカーが無い状態での `git commit` を exit 2 で block

有効化するには `~/.claude/settings.json`（または `<repo>/.claude/settings.json`）に登録する:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [{ "type": "command", "command": "~/.claude/skills/managing-agent-configs/scripts/managing-review-gate.sh" }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "~/.claude/skills/managing-agent-configs/scripts/managing-commit-gate.sh" }]
      }
    ]
  }
}
```

`scripts/lib/marker-path.sh` はマーカーの配置先（worktree 内 `.claude/markers/<session>/` または `${TMPDIR:-/tmp}/claude-hooks/<session>/`）を解決する共有ヘルパーで、2 本の hook から自動的に読み込まれる。設定不要。

登録しなくても `managing-agent-configs` スキル自体は手動呼び出し（自然文での起動）だけで動作する。この hook 2 本は「編集したら自動的にレビュー・テストへ誘導し、未テストの commit を防ぐ」機械強制を追加するものであり必須ではない。

## 使い方

### スキルを作る

```
> 新しいスキルを作りたい
```

`managing-agent-configs` が対象種別を `skills` と判定して create モードが起動し、`references/skills/conventions.md` の規約をロード → SKILL.md を Write → 自動的に review → test まで連鎖。

### フックを作る

```
> PreToolUse の hook を作って
```

`managing-agent-configs` が対象種別を `hooks` と判定して create モードが起動し、配置 4 象限を判定 → hook script を Write → ADR 作成 → settings.json 登録 → 自動 review → test。

### 既存スキル / hook をレビュー

```
> このスキルをレビューして
> hooks をレビューして
```

対象種別ごとの観点（skills は A〜G・26 項目、hooks は A〜H + I〜M・43 項目）で静的解析 → CRITICAL / WARN / INFO を分類 → ユーザー承認のうえ自動修正 → test モードへ連鎖。

### 読み取り専用診断（hooks / rules のみ）

```
> hooks の無限ループリスクを見て
> rules を診断したい
```

`hooks` / `rules` 種別のみ review モードが **dry-run** で起動できる。dry-run では設計面の観点のみを読み取り専用で診断し、`Edit` は発行せず連鎖もしない。他の種別（skills / routines / subagents / workflows）には dry-run はなく、review は常に修正ありの full モードになる。

## ディレクトリ構成

```
agent-toolkit/
├── README.md
├── ai-management-portal/               # 人間用：設計ガイド + スキルの俯瞰ポータル
│   ├── index.html                      # 入口（規模サマリ・カテゴリカード）
│   ├── style.css
│   ├── design/                         # 設計ガイド 7 件（design.css 同居）
│   │   ├── config-placement.html
│   │   ├── claude-md.html
│   │   ├── rules.html
│   │   ├── skill.html
│   │   ├── hooks.html
│   │   ├── subagent.html
│   │   ├── loop.html
│   │   └── design.css
│   ├── catalog/
│   │   └── skills.html                 # 同梱スキル一覧（現状 2 件）
│   ├── src/                            # vanilla JS（ビルド不要）
│   │   ├── main.js
│   │   ├── dom.js
│   │   ├── top.js
│   │   ├── category-view.js
│   │   └── common/                     # テーマ切替・TOC・MD書き出し等の共通機能
│   └── data/
│       ├── manifest.js                 # カテゴリ・ツール定義
│       └── skill-categories.js         # スキル→カテゴリ対応表
└── skills/
    ├── managing-agent-configs/
    │   ├── SKILL.md                    # ハブ（種別判定・モード判定・連鎖制御）
    │   ├── references/
    │   │   ├── related-and-external.md # 外部正本・関連スキル一覧
    │   │   ├── managing-agent-configs-spec.html
    │   │   ├── skills/
    │   │   │   ├── conventions.md
    │   │   │   ├── creating.md
    │   │   │   ├── reviewing.md
    │   │   │   ├── check-items.md
    │   │   │   ├── testing.md
    │   │   │   ├── folder-structure.md
    │   │   │   ├── description-examples.md
    │   │   │   ├── anti-patterns.md
    │   │   │   └── advanced-techniques.md
    │   │   ├── hooks/
    │   │   │   ├── conventions.md
    │   │   │   ├── creating.md
    │   │   │   ├── reviewing.md
    │   │   │   ├── check-items.md
    │   │   │   ├── testing.md
    │   │   │   ├── event-recipes.md
    │   │   │   ├── examples.md
    │   │   │   └── output-schema.md
    │   │   ├── routines/
    │   │   │   ├── conventions.md
    │   │   │   ├── creating.md
    │   │   │   ├── reviewing.md
    │   │   │   ├── testing.md
    │   │   │   └── cloud-operations.md
    │   │   ├── rules/
    │   │   │   ├── conventions.md
    │   │   │   ├── creating.md
    │   │   │   ├── reviewing.md
    │   │   │   ├── check-items.md
    │   │   │   └── testing.md
    │   │   ├── subagents/
    │   │   │   ├── conventions.md
    │   │   │   ├── creating.md
    │   │   │   ├── reviewing.md
    │   │   │   └── testing.md
    │   │   └── workflows/
    │   │       └── workflow-documentation.md
    │   ├── assets/
    │   │   └── template-{手順型,条件付き知識型,強制型}.md
    │   └── scripts/                    # 機械強制フック（任意・README「機械強制フック」参照）
    │       ├── managing-review-gate.sh
    │       ├── managing-commit-gate.sh
    │       └── lib/
    │           └── marker-path.sh
    └── syncing-reverse-env/
        ├── SKILL.md
        ├── config.yml
        └── references/
            └── syncing-reverse-env-spec.html
```

## 要件

- [Claude Code](https://docs.claude.com/en/docs/claude-code) （skill ローダー）
- bash / jq / python3 （review モードの検出式が依存）
