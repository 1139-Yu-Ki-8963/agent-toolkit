# agent-toolkit

Claude Code のスキルとフックを「ライフサイクル」として管理する meta スキル集。新しい PC への初期設定と、既存環境の更新を `scripts/install.mjs` 1 コマンドで完結させる配布キット。

## クイックスタート

```bash
git clone https://github.com/1139-Yu-Ki-8963/agent-toolkit.git
cd agent-toolkit && claude
```

Claude Code が起動したら「CLAUDE.md の初回設定を実行して」と依頼してください。

---

## payload 構成と設置マッピング

```
payload/
├── agent-home/          → ~/agent-home/    （ディレクトリ全体をミラー）
│   ├── ai-management-portal/
│   ├── sessions/
│   └── skills/
│       ├── generating-screen-list-for-reverse-docs/
│       ├── managing-agent-configs/
│       ├── rebuilding-code-from-docs/
│       └── syncing-reverse-env/
└── claude-config/       → ~/.claude/       （ファイル単位で設置）
    ├── CLAUDE.md                            （既存があれば上書きしない）
    └── settings-hooks.json                  （既存 settings.json へ merge）
```

`scripts/install.mjs --doctor / --diff / --apply` が設置・更新を担う。詳細は `CLAUDE.md` を参照。

---

## 同梱スキル

| スキル | 担当 |
|---|---|
| [`generating-screen-list-for-reverse-docs`](payload/agent-home/skills/generating-screen-list-for-reverse-docs/SKILL.md) | レガシーコードベースをスタック調査→検出戦略宣言→抽出→整合検証の4 Phaseで画面単位にグルーピングし、画面一覧.HTML を生成する。抽出は「組み込み検出器（Next.js/React Router・useRoutes 2段階追跡対応）」と「カスタム抽出パス（未知のルーティング方式にプロジェクト専用手順で対応）」の2経路で、どちらも `validate-manifest.sh` が抽出者非依存で整合性を機械検証する（戦略未承認・重複キー・entryFile不在をFAIL）。共有クラスタ・埋め込みビュー・画面ID・診断警告を可視化。仕事は画面一覧.HTMLの作成のみで、設計書の雛形展開・生成は行わない。validate/build は jq に依存。スキルガイドを [`references/generating-screen-list-for-reverse-docs-guide.html`](payload/agent-home/skills/generating-screen-list-for-reverse-docs/references/generating-screen-list-for-reverse-docs-guide.html) に同梱 |
| [`managing-agent-configs`](payload/agent-home/skills/managing-agent-configs/SKILL.md) | エージェント構成 5 種（スキル・フック・ルール・ルーティン・サブエージェント）のライフサイクル管理（作成・観点ベース静的レビュー・実機検証）。スキルガイドを [`references/managing-agent-configs-guide.html`](payload/agent-home/skills/managing-agent-configs/references/managing-agent-configs-guide.html) に同梱 |
| [`rebuilding-code-from-docs`](payload/agent-home/skills/rebuilding-code-from-docs/SKILL.md) | リバース済み画面基本設計書だけからコードを再生成し、元コードと機械突合して設計書の欠落を発見する往復検証スキル。環境同期・比較エンジンは `syncing-reverse-env` に全面委譲。**注意**: 対象テンプレート（`~/agent-home/templates/reverse-docs/02_画面基本設計/`）は本リポジトリに未同梱のため別途用意が必要。スキルガイドを [`references/rebuilding-code-from-docs-guide.html`](payload/agent-home/skills/rebuilding-code-from-docs/references/rebuilding-code-from-docs-guide.html) に同梱 |
| [`syncing-reverse-env`](payload/agent-home/skills/syncing-reverse-env/SKILL.md) | ポート番号だけが違う 2 つの検証環境を用意・同期し、完全一致の証明を基準タグとして確立。スキルガイドを [`references/syncing-reverse-env-guide.html`](payload/agent-home/skills/syncing-reverse-env/references/syncing-reverse-env-guide.html) に同梱 |

---

## 設計仕様（人間用）

`payload/agent-home/ai-management-portal/` に、同梱スキルと設計ガイドを俯瞰できるポータルを同梱しています。設置後は `node payload/agent-home/skills/managing-agent-configs/scripts/manage-portal.mjs serve` でローカルサーバーを起動するか、`payload/agent-home/ai-management-portal/index.html` をブラウザで直接開いてください。

| ドキュメント | 内容 |
|---|---|
| [`ai-management-portal/design/config-placement.html`](payload/agent-home/ai-management-portal/design/config-placement.html) | 設定層 配置判定ガイド — 「どこに書くか」を決定木で判定する横断ガイド。7 層の使い分けを一枚で参照 |
| [`ai-management-portal/design/claude-md.html`](payload/agent-home/ai-management-portal/design/claude-md.html) | CLAUDE.md 設計ガイド — ロードタイミング・サイズ制約・書く/書かない判定フロー |
| [`ai-management-portal/design/rules.html`](payload/agent-home/ai-management-portal/design/rules.html) | Rules 設計ガイド — eager/lazy 注入戦略・カテゴリ分類・hook script 同居原則 |
| [`ai-management-portal/design/skill.html`](payload/agent-home/ai-management-portal/design/skill.html) | Skill 設計ガイド — 定義 / 判定 / 分類 / 起動モデル / 命名 / description 規律 / ツール選択 / フォルダ構造 |
| [`ai-management-portal/design/hooks.html`](payload/agent-home/ai-management-portal/design/hooks.html) | Hooks 設計ガイド — 基本原則 / 禁止配置 / 配置決定 2 軸 / 4 象限 / 機械強制 / 命名・設計判断 |
| [`ai-management-portal/design/subagent.html`](payload/agent-home/ai-management-portal/design/subagent.html) | Subagent 設計ガイド — 4 役割アーキテクチャ・frontmatter 仕様・references 構造・品質基準 |
| [`ai-management-portal/design/loop.html`](payload/agent-home/ai-management-portal/design/loop.html) | Loop 設計ガイド — 繰り返し実行の設計原則・5 アクション・6 パーツ・評価役の分離 |

同梱スキルの実体一覧は [`ai-management-portal/catalog/skills.html`](payload/agent-home/ai-management-portal/catalog/skills.html) から参照できます。

### 人 / AI の住み分け（重要）

| 読み手 | 参照先 | 理由 |
|---|---|---|
| **人間** | `ai-management-portal/design/skill.html` / `hooks.html` 等 | スタイル付きで設計思想・rationale 込みで読める正本 |
| **AI（スキル実行時）** | `payload/agent-home/skills/managing-agent-configs/references/<type>/conventions.md` | 自己完結した縮約版。Stage 3 で追加 Read せずに作業材料が揃う |

`<type>` は `skills` / `hooks` / `rules` / `routines` / `subagents` のいずれか。

---

## 設計思想

- **作りっぱなしを許さない**: 書いた直後に静的監査・実機検証まで連鎖
- **共通規約の単一正本化**: フロントマター / Type / TAG / event 別パターン / timeout 目安 / 配置 4 象限は種別ごとの `references/<type>/conventions.md` に集約
- **段階的開示 (Progressive Disclosure)**: ハブ本体は種別判定・モード判定・ロード指示のみ。各モードの詳細は `references/<type>/` に分離し必要時のみロード

## 自動連鎖

```
create モード ──→ review モード ──→ test モード
   ↑                  ↑                  ↑
   独立起動も可        独立起動も可        独立起動も可
```

- `create` 完了時に **自動で `review` へ**
- `review` 完了時に **自動で `test` へ**
- 連鎖を止めたい場合は `AskUserQuestion` で明示中断

---

## 機械強制フック

`payload/agent-home/skills/managing-agent-configs/scripts/` に gate hook 2 本を同梱しています。
`payload/claude-config/settings-hooks.json` を `~/.claude/settings.json` へ merge することで有効になります（`--apply` が自動実行）。

- `managing-review-gate.sh` — PostToolUse(Write\|Edit\|MultiEdit)。managed ファイル編集時に `[MANAGING-REVIEW-REQUIRED]` を advisory 注入
- `managing-commit-gate.sh` — PreToolUse(Bash)。テスト完了マーカーが無い状態での `git commit` を exit 2 で block

`scripts/lib/marker-path.sh` はマーカーの配置先（worktree 内 `.claude/markers/<session>/` または `${TMPDIR:-/tmp}/claude-hooks/<session>/`）を解決する共有ヘルパーで、2 本の hook から自動的に読み込まれます。

---

## ディレクトリ構成

```
agent-toolkit/
├── README.md
├── CLAUDE.md                                # AI 向け手順書（二役分離）
├── .claude/
│   └── settings.json                        # AT リポジトリ開発用 gate hook 登録済み
├── payload/
│   ├── agent-home/                          # ~/agent-home/ へ設置
│   │   ├── ai-management-portal/            # 人間用ポータル
│   │   │   ├── index.html
│   │   │   ├── style.css
│   │   │   ├── design/                      # 設計ガイド 7 件
│   │   │   ├── catalog/
│   │   │   │   └── skills.html
│   │   │   ├── src/
│   │   │   └── data/
│   │   ├── sessions/
│   │   │   └── .skill-log/
│   │   └── skills/
│   │       ├── generating-screen-list-for-reverse-docs/
│   │       │   ├── SKILL.md
│   │       │   ├── scripts/
│   │       │   │   ├── detect-screens.sh
│   │       │   │   ├── validate-manifest.sh
│   │       │   │   └── build-screen-list.sh
│   │       │   ├── assets/
│   │       │   │   └── screen-list-template.html
│   │       │   └── references/
│   │       │       └── generating-screen-list-for-reverse-docs-guide.html
│   │       ├── managing-agent-configs/
│   │       │   ├── SKILL.md
│   │       │   ├── references/
│   │       │   │   ├── managing-agent-configs-guide.html
│   │       │   │   ├── skills/ hooks/ rules/ routines/ subagents/
│   │       │   │   └── related-and-external.md
│   │       │   └── scripts/
│   │       │       ├── manage-portal.mjs    # generate / check / verify / serve
│   │       │       ├── managing-review-gate.sh
│   │       │       ├── managing-commit-gate.sh
│   │       │       └── lib/marker-path.sh
│   │       ├── rebuilding-code-from-docs/
│   │       │   ├── SKILL.md
│   │       │   ├── references/
│   │       │   │   ├── rebuilding-code-from-docs-guide.html
│   │       │   │   ├── phase-details.md
│   │       │   │   ├── ng-classification.md
│   │       │   │   ├── test-item-patterns.md
│   │       │   │   └── report-format.md
│   │       │   └── scripts/
│   │       │       ├── audit-consistency.sh
│   │       │       └── check-freeze.sh
│   │       └── syncing-reverse-env/
│   │           ├── SKILL.md
│   │           ├── config.yml
│   │           └── references/
│   │               ├── syncing-reverse-env-guide.html
│   │               └── syncing-reverse-env-concept.html
│   └── claude-config/                       # ~/.claude/ へ設置
│       ├── CLAUDE.md                        # 新 PC 向け初期値
│       └── settings-hooks.json              # settings.json merge 断片
└── scripts/
    └── install.mjs                          # --doctor / --diff / --apply / --target
```

## 要件

- [Claude Code](https://docs.claude.com/en/docs/claude-code)（skill ローダー）
- Node.js 18 以上（`scripts/install.mjs` の実行に必要）
- bash / jq / python3（review モードの検出式が依存）
