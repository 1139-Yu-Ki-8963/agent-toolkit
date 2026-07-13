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
├── claudecode-global-setup/     → PC 全体の Claude Code 環境セットアップ
│   ├── agent-home/              → ~/agent-home/    （ディレクトリ全体をミラー）
│   │   ├── ai-management-portal/
│   │   ├── sessions/
│   │   ├── templates/
│   │   │   └── project-docs/
│   │   ├── tools/
│   │   │   └── linter/
│   │   └── skills/
│   │       └── managing-agent-configs/
│   └── claude-config/           → ~/.claude/       （ファイル単位で設置）
│       ├── CLAUDE.md                            （既存があれば上書きしない）
│       ├── settings-hooks.json                  （既存 settings.json へ merge）
│       └── agents/                              （サブエージェント6体をそのままコピー）
└── reverse-docs-skills/     → ~/reverse-docs-skills/   （ディレクトリ全体をミラー。6スキルはどれも単独起動可・スキル間フォルダ依存なし）
    ├── .claude/skills/
    │   ├── generating-screen-list-for-reverse-docs/
    │   ├── orchestrating-reverse-docs-flow/    （オーケストレーター。他5スキルをargs解決して呼び出す）
    │   ├── rebuilding-screen-unit-from-docs/
    │   ├── syncing-reverse-env/
    │   ├── unlocking-reverse-target-screens/
    │   └── rebuilding-code-from-docs/
    └── shared/                                 （テンプレート・章対応表・監査スクリプト。全6スキル共通）
        ├── templates/リバース検証/
        ├── references/chapter-map.md
        └── scripts/audit-consistency.sh
```

`scripts/install.mjs --doctor / --diff / --apply` が設置・更新を担う。詳細は `CLAUDE.md` を参照。

---

## 同梱スキル

| スキル | 担当 |
|---|---|
| [`managing-agent-configs`](payload/claudecode-global-setup/agent-home/skills/managing-agent-configs/SKILL.md) | エージェント構成 5 種（スキル・フック・ルール・ルーティン・サブエージェント）のライフサイクル管理（作成・観点ベース静的レビュー・実機検証）。スキルガイドを [`references/managing-agent-configs-guide.html`](payload/claudecode-global-setup/agent-home/skills/managing-agent-configs/references/managing-agent-configs-guide.html) に同梱 |
| [`running-headless-batch`](payload/claudecode-global-setup/agent-home/skills/running-headless-batch/SKILL.md) | `claude -p`（対話画面を介さず1回の呼び出しで完結する実行方式）による無人バッチループの構築・起動。数十件以上の対象に1件=1呼び出しで処理し、マーカー冪等性・limit耐性・残ゼロまで継続する3要件を満たす。スキルガイドを [`references/running-headless-batch-guide.html`](payload/claudecode-global-setup/agent-home/skills/running-headless-batch/references/running-headless-batch-guide.html) に同梱 |

サブエージェント 6 体（`brain` / `researcher` / `reviewer` / `worker-sonnet` / `worker-haiku` / `investigator`）を `payload/claudecode-global-setup/claude-config/agents/` に、画面基本設計テンプレート一式を `payload/claudecode-global-setup/agent-home/templates/project-docs/` に、textlint 設定と link-checker の仕組みを `payload/claudecode-global-setup/agent-home/tools/linter/` に同梱しています。

### reverse-docs-skills（リバース設計書の往復検証フロー、6スキル）

`payload/reverse-docs-skills/` は独立したスキル集で、`~/reverse-docs-skills/` へミラーされます。各スキルは他スキルのフォルダに依存せず単独起動でき、共有資産（テンプレート・章対応表・監査スクリプト）は `shared/` に同梱済みです（別途用意する必要はありません）。

| スキル | 担当 |
|---|---|
| [`generating-screen-list-for-reverse-docs`](payload/reverse-docs-skills/.claude/skills/generating-screen-list-for-reverse-docs/SKILL.md) | レガシーコードベースをスタック調査→検出戦略宣言→抽出→整合検証の4 Phaseで画面単位にグルーピングし、画面一覧.HTML を生成する。抽出は「組み込み検出器（Next.js/React Router・useRoutes 2段階追跡対応）」と「カスタム抽出パス（未知のルーティング方式にプロジェクト専用手順で対応）」の2経路で、どちらも `validate-manifest.sh` が抽出者非依存で整合性を機械検証する（戦略未承認・重複キー・entryFile不在をFAIL）。共有クラスタ・埋め込みビュー・画面ID・診断警告を可視化。仕事は画面一覧.HTMLの作成のみで、設計書の雛形展開・生成は行わない。validate/build は jq に依存。スキルガイドを [`references/generating-screen-list-for-reverse-docs-guide.html`](payload/reverse-docs-skills/.claude/skills/generating-screen-list-for-reverse-docs/references/generating-screen-list-for-reverse-docs-guide.html) に同梱 |
| [`orchestrating-reverse-docs-flow`](payload/reverse-docs-skills/.claude/skills/orchestrating-reverse-docs-flow/SKILL.md) | オーケストレーター。画面の状態（未開通/開通済み/基準確立済み）を判定し、他5スキルのargsを事前解決して呼び出し、画面一覧から基準確立までの工程を統括する。スキルガイドを [`references/orchestrating-reverse-docs-flow-guide.html`](payload/reverse-docs-skills/.claude/skills/orchestrating-reverse-docs-flow/references/orchestrating-reverse-docs-flow-guide.html) に同梱 |
| [`unlocking-reverse-target-screens`](payload/reverse-docs-skills/.claude/skills/unlocking-reverse-target-screens/SKILL.md) | 設計書が無い画面をモックAPIでログイン後まで開通させ、動作確認可能な状態にする。スキルガイドを [`references/unlocking-reverse-target-screens-guide.html`](payload/reverse-docs-skills/.claude/skills/unlocking-reverse-target-screens/references/unlocking-reverse-target-screens-guide.html) に同梱 |
| [`syncing-reverse-env`](payload/reverse-docs-skills/.claude/skills/syncing-reverse-env/SKILL.md) | ポート番号だけが違う 2 つの検証環境を用意・同期し、完全一致の証明を基準タグとして確立。スキルガイドを [`references/syncing-reverse-env-guide.html`](payload/reverse-docs-skills/.claude/skills/syncing-reverse-env/references/syncing-reverse-env-guide.html) に同梱 |
| [`rebuilding-screen-unit-from-docs`](payload/reverse-docs-skills/.claude/skills/rebuilding-screen-unit-from-docs/SKILL.md) | 画面詳細設計書だけから単体テスト観点で1ファイルを再生成し、原本と5計測（import diff・style diff・全体diff・実質diff・単体テスト仕様検査）で軽量突合する stage1 スキル。カンニング防止を git rm 白紙化＋サブエージェント隔離の二層で構造化。合格後は `rebuilding-code-from-docs`（画面単位・結合観点）へ引き継ぐ。テンプレート一式は `shared/templates/` に同梱済み。スキルガイドを [`references/rebuilding-screen-unit-from-docs-guide.html`](payload/reverse-docs-skills/.claude/skills/rebuilding-screen-unit-from-docs/references/rebuilding-screen-unit-from-docs-guide.html) に同梱 |
| [`rebuilding-code-from-docs`](payload/reverse-docs-skills/.claude/skills/rebuilding-code-from-docs/SKILL.md) | リバース済み画面基本設計書だけからコードを再生成し、元コードと機械突合して設計書の欠落を発見する往復検証スキル。環境同期・比較エンジンは `syncing-reverse-env` に全面委譲。テンプレート一式は `shared/templates/` に同梱済み。スキルガイドを [`references/rebuilding-code-from-docs-guide.html`](payload/reverse-docs-skills/.claude/skills/rebuilding-code-from-docs/references/rebuilding-code-from-docs-guide.html) に同梱 |

---

## 設計仕様（人間用）

`payload/claudecode-global-setup/agent-home/ai-management-portal/` に、同梱スキルと設計ガイドを俯瞰できるポータルを同梱しています。設置後は `node payload/claudecode-global-setup/agent-home/skills/managing-agent-configs/scripts/manage-portal.mjs serve` でローカルサーバーを起動するか、`payload/claudecode-global-setup/agent-home/ai-management-portal/index.html` をブラウザで直接開いてください。

| ドキュメント | 内容 |
|---|---|
| [`ai-management-portal/design/config-placement.html`](payload/claudecode-global-setup/agent-home/ai-management-portal/design/config-placement.html) | 設定層 配置判定ガイド — 「どこに書くか」を決定木で判定する横断ガイド。7 層の使い分けを一枚で参照 |
| [`ai-management-portal/design/claude-md.html`](payload/claudecode-global-setup/agent-home/ai-management-portal/design/claude-md.html) | CLAUDE.md 設計ガイド — ロードタイミング・サイズ制約・書く/書かない判定フロー |
| [`ai-management-portal/design/rules.html`](payload/claudecode-global-setup/agent-home/ai-management-portal/design/rules.html) | Rules 設計ガイド — eager/lazy 注入戦略・カテゴリ分類・hook script 同居原則 |
| [`ai-management-portal/design/skill.html`](payload/claudecode-global-setup/agent-home/ai-management-portal/design/skill.html) | Skill 設計ガイド — 定義 / 判定 / 分類 / 起動モデル / 命名 / description 規律 / ツール選択 / フォルダ構造 |
| [`ai-management-portal/design/hooks.html`](payload/claudecode-global-setup/agent-home/ai-management-portal/design/hooks.html) | Hooks 設計ガイド — 基本原則 / 禁止配置 / 配置決定 2 軸 / 4 象限 / 機械強制 / 命名・設計判断 |
| [`ai-management-portal/design/subagent.html`](payload/claudecode-global-setup/agent-home/ai-management-portal/design/subagent.html) | Subagent 設計ガイド — 4 役割アーキテクチャ・frontmatter 仕様・references 構造・品質基準 |
| [`ai-management-portal/design/loop.html`](payload/claudecode-global-setup/agent-home/ai-management-portal/design/loop.html) | Loop 設計ガイド — 繰り返し実行の設計原則・5 アクション・6 パーツ・評価役の分離 |

同梱スキルの実体一覧は [`ai-management-portal/catalog/skills.html`](payload/claudecode-global-setup/agent-home/ai-management-portal/catalog/skills.html) から参照できます。

### 人 / AI の住み分け（重要）

| 読み手 | 参照先 | 理由 |
|---|---|---|
| **人間** | `ai-management-portal/design/skill.html` / `hooks.html` 等 | スタイル付きで設計思想・rationale 込みで読める正本 |
| **AI（スキル実行時）** | `payload/claudecode-global-setup/agent-home/skills/managing-agent-configs/references/<type>/conventions.md` | 自己完結した縮約版。Stage 3 で追加 Read せずに作業材料が揃う |

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

`payload/claudecode-global-setup/agent-home/skills/managing-agent-configs/scripts/` に gate hook 2 本を同梱しています。
`payload/claudecode-global-setup/claude-config/settings-hooks.json` を `~/.claude/settings.json` へ merge することで有効になります（`--apply` が自動実行）。

- `managing-review-gate.sh` — PostToolUse(Write\|Edit\|MultiEdit)。managed ファイル編集時に `[MANAGING-REVIEW-REQUIRED]` を advisory 注入
- `managing-commit-gate.sh` — PreToolUse(Bash)。テスト完了マーカーが無い状態での `git commit` を exit 2 で block

`scripts/lib/marker-path.sh` はマーカーの配置先（worktree 内 `.claude/markers/<session>/` または `${TMPDIR:-/tmp}/claude-hooks/<session>/`）を解決する共有ヘルパーで、2 本の hook から自動的に読み込まれます。

---

## 更新（payload の同期）

`payload/` の一部ファイル（managing-agent-configs の gate スクリプト等）は private リポジトリ agent-home の正本コピーです。`scripts/sync-manifest.json` の対応表に基づき `scripts/sync-payload.mjs --check` / `--apply` で乖離検知・同期を行います。`git commit` 時には `scripts/check-payload-sync.sh` が乖離を検知して block します。詳細は `CLAUDE.md` の「payload 同期機構」を参照してください。

---

## ディレクトリ構成

```
agent-toolkit/
├── README.md
├── CLAUDE.md                                # AI 向け手順書（二役分離）
├── .claude/
│   └── settings.json                        # AT リポジトリ開発用 gate hook 登録済み
├── payload/
│   ├── claudecode-global-setup/             # PC 全体の Claude Code 環境セットアップ
│   │   ├── README.md                        # ユーザー向け設置手順
│   │   ├── CLAUDE.md                        # AI 向け説明
│   │   ├── agent-home/                      # ~/agent-home/ へ設置
│   │   │   ├── ai-management-portal/        # 人間用ポータル
│   │   │   │   ├── index.html
│   │   │   │   ├── style.css
│   │   │   │   ├── design/                  # 設計ガイド 7 件
│   │   │   │   ├── catalog/
│   │   │   │   │   └── skills.html
│   │   │   │   ├── src/
│   │   │   │   └── data/
│   │   │   ├── sessions/
│   │   │   │   └── .skill-log/
│   │   │   └── skills/
│   │   │       └── managing-agent-configs/
│   │   │           ├── SKILL.md
│   │   │           ├── references/
│   │   │           │   ├── managing-agent-configs-guide.html
│   │   │           │   ├── skills/ hooks/ rules/ routines/ subagents/
│   │   │           │   └── related-and-external.md
│   │   │           └── scripts/
│   │   │               ├── manage-portal.mjs    # generate / check / verify / serve
│   │   │               ├── managing-review-gate.sh
│   │   │               ├── managing-commit-gate.sh
│   │   │               └── lib/marker-path.sh
│   │   └── claude-config/                   # ~/.claude/ へ設置
│   │       ├── CLAUDE.md                    # 新 PC 向け初期値
│   │       └── settings-hooks.json          # settings.json merge 断片
│   └── reverse-docs-skills/                     # ~/reverse-docs-skills/ へ設置
│       ├── .claude/
│       │   └── skills/
│       │       ├── generating-screen-list-for-reverse-docs/
│       │       │   ├── SKILL.md
│       │       │   ├── assets/screen-list-template.html
│       │       │   ├── references/generating-screen-list-for-reverse-docs-guide.html
│       │       │   └── scripts/
│       │       │       ├── build-screen-list.sh
│       │       │       ├── detect-screens.sh
│       │       │       └── validate-manifest.sh
│       │       ├── orchestrating-reverse-docs-flow/
│       │       │   ├── SKILL.md
│       │       │   └── references/
│       │       │       ├── contract.md
│       │       │       └── orchestrating-reverse-docs-flow-guide.html
│       │       ├── rebuilding-screen-unit-from-docs/
│       │       │   ├── SKILL.md
│       │       │   ├── references/
│       │       │   │   ├── rebuilding-screen-unit-from-docs-guide.html
│       │       │   │   ├── phase-details.md
│       │       │   │   └── ng-classification.md
│       │       │   └── scripts/
│       │       │       ├── scaffold-screen.sh
│       │       │       ├── measure-file-diff.sh
│       │       │       └── check-viewpoint-coverage.sh
│       │       ├── syncing-reverse-env/
│       │       │   ├── SKILL.md
│       │       │   ├── config.yml
│       │       │   ├── references/
│       │       │   │   ├── syncing-reverse-env-guide.html
│       │       │   │   └── syncing-reverse-env-concept.html
│       │       │   └── scripts/
│       │       │       └── audit-doc-consistency.sh
│       │       ├── unlocking-reverse-target-screens/
│       │       │   ├── SKILL.md
│       │       │   └── references/unlocking-reverse-target-screens-guide.html
│       │       └── rebuilding-code-from-docs/
│       │           ├── SKILL.md
│       │           ├── references/
│       │           │   ├── rebuilding-code-from-docs-guide.html
│       │           │   ├── phase-details.md
│       │           │   ├── ng-classification.md
│       │           │   ├── test-item-patterns.md
│       │           │   └── report-format.md
│       │           └── scripts/
│       │               └── check-freeze.sh
│       └── shared/                              # 6スキル共通の共有資産（依存フォルダなし）
│           ├── templates/リバース検証/          # 画面詳細設計書・共通規約等16テンプレート
│           ├── references/chapter-map.md
│           └── scripts/audit-consistency.sh
└── scripts/
    └── install.mjs                          # --doctor / --diff / --apply / --target
```

## 要件

- [Claude Code](https://docs.claude.com/en/docs/claude-code)（skill ローダー）
- Node.js 18 以上（`scripts/install.mjs` の実行に必要）
- bash / jq / python3（review モードの検出式が依存）
