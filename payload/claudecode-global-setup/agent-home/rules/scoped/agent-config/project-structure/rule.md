---
paths:
  - "**/.claude/rules/**"
  - "**/.claude/skills/flow-config/**"
---

# プロジェクト標準構成規約（PROJECT-STRUCTURE）

`~/Projects/` 配下の全リポジトリに適用する `.claude/rules/` の標準体系。グローバルと同じ scope 体系（always / scoped）に統一し、定義コンテキスト（project-context）を必須化する。旧 `.claude/skills/flow-config/flow-context.yml` は本体系の `flow-values.yml` に吸収済み（互換レイヤなし）。

## 3 層構成

| 層 | 実体 | 役割 |
|---|---|---|
| グローバル | `~/agent-home/rules/`（`~/.claude/rules` は symlink） | 枠組み・機械強制・既定値。上書き可否と受け口形式を各 rule が宣言 |
| agent-home | グローバル資産（rules/skills/routines/tools）のホスト | 実装フロー対象外のため project-context は不要。必須は `.claude/rules/always/project-context/rule.md` 1 枚（許可リスト節含む・flow-values なし） |
| 各プロジェクト | `<repo>/.claude/rules/`（実体ディレクトリ） | 本規約の標準体系（下記） |

## プロジェクト標準体系

定義は `<repo>/.claude/rules/` に実体ディレクトリとして置く。

```
<repo>/
└── .claude/rules/                       ← 実体ディレクトリ（定義）
    ├── always/                          ← セッション開始時に常時注入
    │   ├── project-context/             ★必須
    │   │   ├── rule.md                  プロジェクト概要・技術スタック・設定索引・ルート直下許可リスト節（80 行以内 + 許可リスト節）
    │   │   └── flow-values.yml          実装フロー設定値（機械可読サイドカー・非注入）
    │   ├── naming/commit-branch/
    │   │   └── naming-values.txt        任意（命名値の上書き）
    │   └── review-checklist/text-dictionary/
    │       └── prh.yml                  任意（プロジェクト辞書）
    └── scoped/                          ← 該当ファイルを触る時だけ注入
        ├── review-checklist/<domain>/<name>/rule.md   任意（domain は code / document / report 限定）
        └── <自由ドメイン>/<topic>/rule.md              任意（frontend / backend / db 等）
```

## 必須 2 ファイルの根拠

1. `always/project-context/rule.md`（`## ルート直下許可ディレクトリ` 節を含む） — 無いとプロジェクトの前提・索引・mkdir 許可リストがセッションに載らない
2. `always/project-context/flow-values.yml` — 無いと実装フロー（orchestrating-dev-flow）の Phase ゲートで block される

旧来の専用ファイル（`always/placement/directory-structure/rule.md`）は許可リスト節として project-context/rule.md に統合済み。既存の専用ファイルが残っている場合は移行互換フォールバックとして解決される（`~/.claude/rules/always/placement/directory-structure/rule.md` のプロジェクト上書き節を参照）。

## 制約

1. **`scoped/review-checklist/` 配下は既存ドメイン（code / document / report）限定**。担当専門家は `<domain>-reviewer` としてフォルダ名から機械導出されるため、専門家が存在しないドメイン（frontend 等）を review-checklist 配下に作ると委任先不在になる。プロジェクト固有の実装規約は review-checklist の外（自由ドメイン）に置く
2. **project-context/rule.md の概要・技術スタック・索引部分は 80 行以内**（許可リスト節は予算対象外。旧専用ファイルからの統合分のため）。常時注入されるため、概要・技術スタック・索引に絞る。詳細は flow-values.yml と docs/ へ
3. **paths glob はリポジトリルートからの相対パスに照合される**（canary 実測済み）。プロジェクト scoped rule の paths はリポジトリ内相対で書く。祖先ディレクトリ名（リポジトリ自身の名前）を glob に含めても一致しない
4. **受け口の形式は各グローバル規約の「プロジェクト上書き」節が定義**。本規約は場所の索引のみを持ち、形式・合成規則を再定義しない
5. **paths glob・受け口・hook の解決はすべて `.claude/rules/` パス経由で行われる**

## flow-values.yml スキーマ（定義）

```yaml
# プロジェクト実装フロー設定（スキーマ定義: 本 rule.md）
domain_glossary: null      # ドメイン用語集のパス
design_system: null        # デザインシステム / DESIGN.md のパス
test_conventions: null     # テスト規約のパス
adr_dir: null              # ADR ディレクトリ
design_docs: null          # 設計書ディレクトリ（旧 source.design_docs）
portal_dir: null           # 画面一覧・ポータル（旧 source.portal_dir）
review_gates: {}           # レビューゲート設定（pre_impl / impl_quality / pre_push / e2e）
review_agents: {}          # ゲート別レビュー人格ファイル（任意）
pr: {}                     # PR 設定（template / required_sections / critical_globs / skip_globs）
classify: {}               # 規模判定（quick_max_files / quick_excludes）
preflight: {}              # preflight 設定（skip_tools）
```

- 旧スキーマからの変更: `source.design_docs` / `source.portal_dir` はトップレベルへ平坦化。文書だけが参照していた `test_conventions` / `review_agents` / `pr.skip_globs` を正式キーとして採録（既定 null / 空）
- プロジェクト独自の拡張キーを追加してよい（例: oradora-battle-base の context_a / context_b）。消費者はプロジェクト内の文書・スキルに限る

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| Write/Edit（コードファイル） | `scoped/dev-flow/gate/check-dev-flow-phase-gate.sh` | `[DEV-FLOW-PHASE-GATE-BLOCK]` | flow-values.yml 不在のプロジェクトでコード書き込みを block |
| PreToolUse(Bash git commit) | `always/placement/flow-context-guard/check-flow-context-guard.sh` | `[FLOW-CONTEXT-GUARD]` | flow-values.yml 不在を advisory 注入 |
| PostToolUse(Bash clone/init/worktree) | `always/placement/flow-context-guard/generate-flow-context.sh` | `[FLOW-CONTEXT-GENERATED]` | 必須ファイルの雛形を自動生成 |

## 違反検知時の手順

1. `.claude/rules` が実体ディレクトリでない（symlink 等）場合、既存内容を `.claude/rules/` 直下に実体として移設する
2. 必須ファイル不在の指摘を受けたら、`Skill(creating-new-project)` の生成手順、または flow-context-guard の雛形テンプレートで必須 2 ファイルを作成する
3. 旧配置（`.claude/skills/flow-config/flow-context.yml`）が残っている場合: 中身を `always/project-context/flow-values.yml` へ移し（source.* は平坦化）、flow-config/ ディレクトリを削除する

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: 本規約は「プロジェクトが何を上書きできるか」を定める枠組みそのものであり、受け口の対象外

## 設計判断

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 関連

- `~/.claude/rules/always/placement/directory-structure/rule.md` — 許可リストの枠組みと受け口宣言
- `~/.claude/rules/always/naming/commit-branch/rule.md` — 命名値の受け口宣言
- `~/.claude/rules/always/review-checklist/text-dictionary/rule.md` — プロジェクト辞書の受け口宣言
- `~/.claude/rules/scoped/agent-config/review-checklist/rule.md` — レビュー観点フォルダの統治（ドメイン 1 対 1）
- `~/agent-home/skills/orchestrating-dev-flow/SKILL.md` — flow-values.yml の主要な消費者
- `~/agent-home/skills/creating-new-project/SKILL.md` — 本体系の生成者
