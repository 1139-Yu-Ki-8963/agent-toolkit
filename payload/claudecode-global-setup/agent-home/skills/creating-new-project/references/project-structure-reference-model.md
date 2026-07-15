# プロジェクト構成リファレンスモデル

`<project>` の実プロジェクト構造を分析し、汎化したリファレンスモデル。
creating-new-project スキルが新規プロジェクト生成時に参照する。

---

## 1. ディレクトリツリー

```
~/Projects/<project-name>/
├── .claude/
│   ├── settings.json                          # プロジェクト固有 hook・permission
│   └── rules/                                 # 実体ディレクトリ（正本）
│       ├── always/                            # プロジェクト標準構成規約（必須）
│       │   └── project-context/
│       │       ├── rule.md                    # プロジェクト概要・設定索引・ルート直下許可リスト節
│       │       ├── flow-values.yml            # 実装フロー設定値（orchestrating-dev-flow 連携）
│       │       └── layers.yml                 # レイヤー別コマンド体系
│       ├── domain/                            # ドメイン固有ルール
│       │   ├── dictionary/
│       │   │   └── rule.md                    # 用語辞書（UI 表記統一）
│       │   └── domain-constraints/
│       │       └── rule.md                    # ドメイン制約（ビジネスルール等）
│       └── project/                           # プロジェクト全域ルール
│           ├── context-scope/
│           │   ├── rule.md                    # 全域制約（コミット・識別子・依存方向）
│           │   ├── frontend/
│           │   │   ├── rule.md                # paths: "src/**"
│           │   │   └── check-frontend-on-commit.sh
│           │   ├── test/
│           │   │   ├── rule.md                # paths: "e2e/**" or "tests/**"
│           │   │   └── check-test-on-commit.sh
│           │   └── <layer>/                   # backend, db 等（スタックに応じて追加）
│           │       ├── rule.md
│           │       └── check-<layer>-on-commit.sh
│           └── codebase-boundary/
│               └── rule.md                    # コードベース境界制約
├── .config/
│   ├── gitleaks.toml                          # シークレット検知設定
│   └── lychee.toml                            # リンク切れ検査設定
├── .github/
│   ├── dependabot.yml                         # 依存更新（月次）
│   ├── workflows/
│   │   └── ci.yml                             # PR 時の自動テスト
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug-report.md
│   │   ├── feature-request.md
│   │   ├── problem-statement.md
│   │   └── config.yml                         # blank_issues_enabled: false
│   ├── pull_request_template.md
│   └── pull_request_guide.md
├── .husky/
│   ├── pre-commit                             # lint-staged + gitleaks + markers guard
│   └── pre-push                               # author 検証 + テスト + lint
├── docs/
│   ├── 設計書レビュー観点.md                    # templates/project-docs/ からコピー
│   ├── 01_機能基本設計/                         # 機能別設計書（3 ファイル）
│   │   └── <機能名>/
│   │       ├── 機能基本設計書.md
│   │       ├── 単体テスト観点表.md
│   │       └── 結合テスト観点表.md
│   ├── 02_画面基本設計/                         # 画面別設計書（4 ファイルセット）
│   │   ├── _共通/
│   │   │   ├── DESIGN.md
│   │   │   ├── メッセージ定義書.md
│   │   │   └── 画面共通仕様.md
│   │   └── <画面名>/
│   │       ├── 画面基本設計書.md
│   │       ├── DESIGN.md
│   │       ├── 単体テスト観点表.md
│   │       └── 結合テスト観点表.md
│   ├── 03_操作フロー設計/                       # ユーザー操作フロー
│   │   └── <フロー名>/
│   │       ├── 操作フロー設計書.md
│   │       └── E2Eテスト観点表.md
│   └── 04_開発プロセス設計/                     # 開発手順・ADR・設計メモ
│       └── プロジェクト地図.md
├── logs/                                       # ルーティン出力（.gitignore 対象）
├── project-portal/                             # プロジェクト管理ポータル
│   ├── index.html
│   ├── style.css
│   ├── src/
│   │   ├── main.js                            # ハッシュルーター
│   │   ├── top.js                             # カードグリッド
│   │   ├── category-view.js
│   │   ├── master-table-detail.js
│   │   └── common/                            # 共有モジュール
│   ├── data/
│   │   ├── manifest.js                        # カテゴリ・ツール定義
│   │   ├── design-docs.js                     # docs/*.md → ポータルカテゴリ対応
│   │   ├── search-index.js
│   │   ├── page-graph.js
│   │   ├── release-notes.js
│   │   ├── mocks.js
│   │   └── master-tables/
│   │       ├── index.js
│   │       ├── features.js
│   │       ├── screens.js
│   │       ├── techstack.js
│   │       └── project-index.js
│   ├── sites/
│   │   ├── rules/                             # ルール HTML（hook から参照）
│   │   │   ├── 01-project/
│   │   │   ├── 02-design/
│   │   │   ├── 03-naming/
│   │   │   ├── 04-code/
│   │   │   ├── 05-test/
│   │   │   ├── 06-design/
│   │   │   └── 08-auto/                       # 自動化 hook スクリプト群
│   │   ├── design-system/
│   │   ├── design-patterns/
│   │   └── operation-flow/
│   ├── mocks-archive/
│   │   └── .gitkeep
│   └── tools/
│       └── serve.py                           # 開発サーバー
├── qa/
│   ├── user-stories.md                        # Given-When-Then 形式
│   └── qa-tracking.tsv
├── src/                                        # ソースコード（構成はスタック依存）
├── CLAUDE.md
├── README.md
├── Makefile
├── .gitignore
├── .gitattributes
└── package.json
```

### ディレクトリ階層の設計原則

| 原則 | 説明 |
|---|---|
| ルート直下は許可リスト方式 | `.claude/rules/always/project-context/rule.md` の `## ルート直下許可ディレクトリ` 節で管理 |
| hook スクリプトは rule.md と同居 | `.claude/rules/<category>/<rule-name>/` 配下に配置 |
| skill は SKILL.md + references/ + scripts/ | 3 サブディレクトリのパターン |
| docs/ は番号付き 4 カテゴリ | 01_機能 / 02_画面 / 03_操作フロー / 04_開発プロセス |
| logs/ は全て .gitignore | ルーティン出力の蓄積場所 |
| project-portal/ は vanilla JS SPA | ビルドツール不要、ES modules + hash routing |

---

## 2. 設定ファイル一覧

### 2-1. CLAUDE.md テンプレート

```markdown
# <project-name>

<目的を 1 文で>

## 技術スタック

| レイヤー | 技術 |
|---------|------|
| フロントエンド | <framework> + TypeScript |
| FE テスト / Lint | <test-runner> / <linter> |
| バックエンド | <framework>（該当する場合） |
| BE テスト / Lint | <test-runner> / <linter>（該当する場合） |
| DB | <database>（該当する場合） |

## コマンド

| 目的 | コマンド |
|------|---------|
| FE テスト | `<command>` |
| FE Lint | `<command>` |
| 開発サーバー | `<command>` |

## ディレクトリ構造

詳細は「プロジェクト索引」（`project-portal/data/master-tables/project-index.js`）を参照。

## 行動原則

- ルール正本は `project-portal/sites/rules/` 配下。hook が `[...-BLOCK]` / `[...-REQUIRED]` を注入したら該当 rule を Read して PROCEDURE に従う
- コード変更は対応する `docs/` の設計書更新を同一 PR に含めること必須
- 先送り禁止。hook が先送り表現を検出して block する
- セッション肥大早期警告: `[SESSION-CONTEXT-LARGE]` が通知されたら区切りの良いところで `/clear`
```

設計方針:
- 200 行以内を厳守（config-placement-rules の CLAUDE.md 制限）
- 機械強制が必要な制約は hook/rules に閉じ、CLAUDE.md は概要とポインタのみ
- プロジェクト固有のドメイン制約（用語辞書等）は `.claude/rules/domain/` に分離

### 2-2. .gitignore テンプレート

```gitignore
# Dependencies
node_modules/
.venv/

# Build
dist/
coverage/
.next/

# Environment
.env
.env.local
.env.*.local

# Claude Code
.claude/markers/
.flow-progress.json
.port-slot
.investigation-checklist.md
.status.json

# IDE
.DS_Store
*.sw[mnop]
.idea/
.vscode/

# Playwright
.playwright-mcp/
test-results/

# Logs (routine outputs)
logs/**/*.json
logs/**/*.jsonl
logs/**/*.txt
logs/**/*.log
logs/**/*.tsv
logs/**/*.gz
logs/**/*.md
logs/**/*.stderr
!logs/**/.gitkeep

# Misc
MEMO.md
.backups/
.dev-launch-cache/
```

### 2-3. .gitattributes テンプレート

```gitattributes
# ポータル自動生成ファイルのマージ競合回避
# project-portal/sites/rules/index.html merge=portal-ours
```

### 2-4. Makefile テンプレート構造

```makefile
# プロジェクト自動化ハブ
# -include .worktree-ports.env（worktree ポートオフセット対応）

.PHONY: dev test lint typecheck coverage \
        project-portal hooks-test

# === 開発 ===
dev:
	# ポート管理規約に準拠した起動コマンド

# === 品質 ===
test:
	# FE + BE テスト並列実行

lint:
	# FE + BE lint 並列実行

typecheck:
	# 型チェック

coverage:
	# カバレッジ計測

# === ポータル ===
project-portal:
	# python3 -m http.server <portal-port> --directory project-portal

# === Hook テスト ===
hooks-test:
	# hook .test.sh の一括実行
```

設計方針:
- `-include .worktree-ports.env` で worktree スロット別ポートを注入
- DB 操作は Makefile target 経由に限定（直接コマンド禁止を rule で強制）
- `backend-up` target にはポート占有プロセスの stale kill を含める

---

## 3. .claude/ 基盤

### 3-1. rules のカテゴリ体系

**正本**: domain/project カテゴリは `~/agent-home/templates/project-claude-rules/`。本書にテンプレート本文は複写しない（正の一意性）。always カテゴリ（project-context。ルート直下許可リストは project-context/rule.md の節として統合済み）はプロジェクト標準構成規約（`~/.claude/rules/scoped/agent-config/project-structure/rule.md`）が正本で、テンプレート内容は本書 §7 に記載する。

実体は `.claude/rules/` に直接置く。

```
.claude/rules/
├── always/          # プロジェクト標準構成規約（必須ファイルのみ）
│   └── project-context/
│       ├── rule.md                # プロジェクト概要・設定索引・ルート直下許可リスト節
│       └── flow-values.yml        # 実装フロー設定値
├── domain/          # ドメイン固有（用語辞書・ビジネス制約）
│   ├── dictionary/
│   │   └── rule.md
│   └── domain-constraints/
│       └── rule.md
└── project/         # プロジェクト全域（コンテキストスコープ・コードベース境界）
    ├── context-scope/
    │   ├── rule.md                    # 全域制約の親ルール
    │   ├── frontend/
    │   │   ├── rule.md                # paths: "<fe-src>/**"
    │   │   └── check-frontend-on-commit.sh
    │   ├── test/
    │   │   ├── rule.md                # paths: "<test-dir>/**"
    │   │   ├── check-test-on-commit.sh
    │   │   └── diff-test-on-commit.sh
    │   └── <layer>/                   # スタックに応じて追加
    │       ├── rule.md
    │       └── check-<layer>-on-commit.sh
    └── codebase-boundary/
        └── rule.md
```

カテゴリ体系の設計原則:

| カテゴリ | 内容 | 例 |
|---|---|---|
| always/ | プロジェクト標準構成規約の必須ファイル。セッション開始時に常時注入 | プロジェクトコンテキスト（project-context。ルート直下許可リスト節を含む） |
| domain/ | ドメイン固有の用語・制約。他プロジェクトで再利用しない | 用語辞書、ビジネスルール、ドメイン制約 |
| project/ | プロジェクト全域の技術制約。スタック依存 | コンテキストスコープ、コードベース境界 |

**注**: flow 系 rules（loop-commit / session-context）は scaffold しない。フロー進行の管理は orchestrating-dev-flow とグローバル層の管轄。任意受け口（naming-values.txt・prh.yml・scoped/review-checklist）も scaffold 時点では生成せず、`always/project-context/rule.md` の設定索引に案内のみを記載する。

### プレースホルダ置換・スタック別削除の対応表

コピー後に以下のプレースホルダを Phase 1 のヒアリング値で置換し、スタックに存在しないスコープのファイルを削除する。

| ファイル | プレースホルダ | 置換値 |
|---|---|---|
| always/project-context/rule.md | `<プロジェクト名>` 等 | Phase 1 の値（§7 のテンプレートを参照） |
| always/project-context/rule.md（`## ルート直下許可ディレクトリ` 節） | （行追加・削除） | スタック別構成に調整 |
| always/project-context/flow-values.yml | `<プロジェクト名>` 等 | Phase 1 の値（§7 のテンプレートを参照） |
| domain/dictionary/rule.md | `<プロジェクト名>` | `project_name` |
| domain/dictionary/rule.md | `<domain-term-N>` | Phase 1 の機能名・画面名 |
| domain/domain-constraints/rule.md | `<プロジェクト名>` | `project_name` |
| project/context-scope/*/rule.md | `<プロジェクト名>` | `project_name` |
| project/context-scope/frontend/rule.md | `<fe-src>` | `src`（FE のみ）/ `frontend/src`（フルスタック） |
| project/codebase-boundary/rule.md | `<プロジェクト名>` | `project_name` |

| スタック | 削除するスコープ |
|---|---|
| FE のみ | context-scope/backend/・context-scope/db/ |
| フルスタック | 削除なし |

context-scope/ の paths 付き lazy rule パターン:
- `frontend/rule.md` に `paths: "src/**"` を指定すると、FE ファイル編集時のみルールがロードされる
- レイヤーごとの lint/test コマンド・依存方向・禁止パターンを分離できる
- hook スクリプト（`check-*-on-commit.sh`）は rule.md と同居させる

### 3-2. skills の初期セット

新規プロジェクトで最初に配置すべき skill はない（`.claude/skills/` は空のまま作成しない）。
プロジェクト固有 skill は開発が進んでから追加する。orchestrating-dev-flow 連携設定は `.claude/rules/always/project-context/flow-values.yml`・`layers.yml`（§7 参照）が担う。

skill を追加する際の構造パターン:

```
.claude/skills/<skill-name>/
├── SKILL.md                 # 必須: frontmatter + 手順
├── references/              # 任意: 参照ドキュメント
│   └── <name>.md
├── scripts/                 # 任意: 自動化スクリプト (.sh/.py/.mjs)
│   ├── <name>.sh
│   └── <name>.test.sh       # スクリプトには .test.sh を同居
└── assets/                  # 任意: 静的ファイル (HTML テンプレ等)
    └── <name>.html
```

SKILL.md frontmatter の必須フィールド:

```yaml
---
name: <skill-name>
description: |
  <1 行説明>
  TRIGGER when: <発火条件キーワード>
  SKIP: <スキップ条件>
invocation: <skill-name>
type: <gateway|orchestration|action|reference|transform|verification>
category: <任意: game, ui, flow, pr, test, ...>
---
```

### 3-3. settings.json テンプレート

```json
{
  "worktree": {
    "baseRef": "fresh"
  },
  "hooks": {
    "UserPromptSubmit": [],
    "PreToolUse": [],
    "PostToolUse": [],
    "Stop": [],
    "SessionEnd": [],
    "SubagentStop": []
  },
  "permissions": {
    "defaultMode": "auto",
    "allow": [
      "Agent",
      "Skill",
      "Bash(git *)",
      "Bash(make *)",
      "Bash(npm run *)",
      "Bash(npm install *)",
      "Bash(npx *)",
      "Bash(gh pr list*)",
      "Bash(gh pr view*)",
      "Bash(gh pr diff*)",
      "Bash(gh pr comment*)",
      "Bash(gh pr review*)",
      "Bash(gh issue create*)",
      "Bash(gh issue list*)",
      "Bash(gh api*)",
      "Bash(curl -s http://127.0.0.1:*)"
    ]
  },
  "outputStyle": "Proactive"
}
```

段階的に hook を追加する順序:

| 段階 | hook | timing | 目的 |
|---|---|---|---|
| FE 追加時 | check-frontend-on-commit | PreToolUse(Bash) | FE lint/type/test 強制 |
| BE 追加時 | check-backend-on-commit | PreToolUse(Bash) | BE lint/type/test 強制 |
| DB 追加時 | check-db-on-commit | PreToolUse(Bash) | migration 整合性チェック |
| ポータル追加時 | design-compliance | PostToolUse(Edit\|Write) | デザイン規約準拠 |
| 成熟期 | commit-unit | PreToolUse(Bash) | FE/BE/DB 混在 commit 防止 |
| 成熟期 | file-placement | PreToolUse(Bash) | ファイル配置ガード |
| 成熟期 | naming-on-commit | PreToolUse(Bash) | 命名規則強制 |

---

## 4. docs/ 体系

**正本**: `~/agent-home/templates/project-docs/`。本書にテンプレート本文は複写しない（正の一意性）。

### 4-1. カテゴリ構成

| カテゴリ | 内容 | ファイル構造 |
|---|---|---|
| 01_機能基本設計 | 機能単位の設計書（3 ファイル） | `<機能名>/{機能基本設計書.md, 単体テスト観点表.md, 結合テスト観点表.md}` |
| 02_画面基本設計 | 画面単位の設計書（4 ファイルセット）+ _共通 3 ファイル | `<画面名>/{画面基本設計書.md, DESIGN.md, 単体テスト観点表.md, 結合テスト観点表.md}` |
| 03_操作フロー設計 | ユーザー操作フロー（2 ファイル） | `<フロー名>/{操作フロー設計書.md, E2Eテスト観点表.md}` |
| 04_開発プロセス設計 | 開発手順・ADR・設計メモ | `プロジェクト地図.md` ほかフラット `.md` |

`docs/` 直下に `設計書レビュー観点.md` を 1 枚配置する（`templates/project-docs/設計書レビュー観点.md` からコピー）.

### 4-2. プレースホルダ置換対応表

コピー後に以下のプレースホルダを Phase 1 のヒアリング値で置換する。`<機能名>`・`<画面名>`・`<フロー名>` はすべてディレクトリ名と同値の日本語名を使う。

| プレースホルダ | 置換値 | ヒアリング項目 |
|---|---|---|
| `<doc_id>` | ファイル種別に応じて使い分ける（下表参照） | — |
| `<機能名>` | 機能の識別名（ディレクトリ名と同値の日本語名） | `features[]` |
| `<feature_name>` | 機能の識別名（ディレクトリ名と同値の日本語名） | `features[]` |
| `<画面名>` | 画面の識別名（ディレクトリ名と同値の日本語名） | `screens[]` |
| `<target_screen>` | 対象画面名 | `screens[]` |
| `<route>` | 画面の URL パス | Phase 1 で確認 |
| `<フロー名>` | 操作フローの識別名（ディレクトリ名と同値の日本語名） | `features[]` または別途定義 |
| `<flow_name>` | フローの識別名（ディレクトリ名と同値の日本語名） | `features[]` または別途定義 |
| `<プロジェクト名>` | Phase 1 の `project_name`（`_共通/DESIGN.md` 等の本文にも出現する） | `project_name` |
| `<YYYY-MM-DD>` | 作成日 | 自動入力 |

#### doc_id 形式早見表

| ファイル | doc_id 形式 |
|---|---|
| `01_機能基本設計/<機能名>/機能基本設計書.md` | `feature-<機能名>` |
| `01_機能基本設計/<機能名>/単体テスト観点表.md` | `unit-test-<機能名>` |
| `01_機能基本設計/<機能名>/結合テスト観点表.md` | `integration-test-<機能名>` |
| `02_画面基本設計/<画面名>/画面基本設計書.md` | `screen-<画面名>` |
| `02_画面基本設計/<画面名>/DESIGN.md` | `design-<画面名>` |
| `02_画面基本設計/<画面名>/単体テスト観点表.md` | `unit-test-<画面名>` |
| `02_画面基本設計/<画面名>/結合テスト観点表.md` | `integration-test-<画面名>` |
| `03_操作フロー設計/<フロー名>/操作フロー設計書.md` | `flow-<フロー名>` |
| `03_操作フロー設計/<フロー名>/E2Eテスト観点表.md` | `e2e-test-<フロー名>` |

---

## 5. project-portal/ 構成

### 5-1. アーキテクチャ

- vanilla JS SPA（ビルドツール不要）
- ES modules + `<script type="module">`
- ハッシュルーティング（`#/`, `#/category/<id>`, `#/table/<id>`）
- 全データはベタ書き JS（自動生成ではなく手動メンテナンス）

### 5-2. 初期ファイル構成

```
project-portal/
├── index.html                    # SPA エントリポイント
├── style.css                     # 共通スタイル
├── src/
│   ├── main.js                   # ハッシュルーター
│   ├── top.js                    # TOPページ（カードグリッド）
│   ├── category-view.js          # カテゴリ詳細
│   ├── master-table-detail.js    # マスタテーブル表示
│   ├── master-util.js            # テーブルユーティリティ
│   ├── dom.js                    # DOM ヘルパー
│   └── common/                   # 共有モジュール
│       ├── header.js
│       ├── theme.js
│       ├── search-ui.js
│       ├── search-index.js
│       ├── toc.js
│       └── shortcuts.js
├── data/
│   ├── manifest.js               # カテゴリ定義
│   ├── design-docs.js            # docs/ → カテゴリ対応表
│   ├── search-index.js           # 検索インデックス
│   ├── page-graph.js             # ページ間リンク
│   ├── release-notes.js          # リリースノート
│   ├── mocks.js                  # mock 一覧
│   └── master-tables/
│       ├── index.js              # テーブル一覧
│       ├── features.js           # 機能マスタ
│       ├── screens.js            # 画面マスタ
│       ├── techstack.js          # 技術スタック
│       └── project-index.js      # プロジェクト索引
├── sites/
│   └── rules/                    # ルール HTML + 自動化 hook
│       ├── 01-project/           # プロジェクト概要・環境
│       ├── 02-design/            # アーキテクチャ・設計
│       ├── 03-naming/            # 命名規則
│       ├── 04-code/              # コーディング標準
│       ├── 05-test/              # テストポリシー
│       ├── 06-design/            # UI デザインパターン
│       └── 08-auto/              # 自動化 hook スクリプト群
├── mocks-archive/
│   └── .gitkeep
└── tools/
    └── serve.py                  # 開発サーバー
```

### 5-3. data/ ファイルテンプレート

#### manifest.js

```javascript
// プロジェクト管理ポータル マニフェスト
// カテゴリとツールの定義

export const VISUAL_TOOL_GROUPS = [
  {
    id: "rules",
    title: "ルール・規約",
    tools: [
      // { id: "rule-id", title: "ルール名", path: "sites/rules/..." }
    ]
  },
  {
    id: "master",
    title: "マスタテーブル",
    sections: [
      // { title: "セクション名", tools: [...] }
    ]
  },
  {
    id: "design-docs",
    title: "設計ドキュメント",
    // design-docs.js から動的構築
  }
];
```

#### design-docs.js

```javascript
// docs/*.md → ポータルカテゴリ対応表
// 追記責任: flow Phase 9 の updating-portal-data スキル

export const DESIGN_DOCS = [
  // { path: "docs/01_.../xxx/機能基本設計書.md", category: "機能", title: "xxx" }
];

export const DOC_CATEGORIES = [
  "機能",
  "画面",
  "操作フロー",
  "開発プロセス"
];
```

### 5-4. sites/rules/ のカテゴリ番号体系

| 番号 | カテゴリ | 内容 |
|---|---|---|
| 01-project | プロジェクト概要 | overview, environments |
| 02-design | 設計・アーキテクチャ | architecture, screen-docs-lifecycle |
| 03-naming | 命名規則 | file-naming, identifier-consistency |
| 04-code | コーディング標準 | coding-standards, code-review-criteria |
| 05-test | テストポリシー | test-policy, test-coverage-checklist |
| 06-design | UI デザイン | patterns, design-system, design-impl-guide |
| 08-auto | 自動化 hook | hook スクリプト群（settings.json から参照） |

07 は欠番（予約済み）。08-auto は hook スクリプトの最大集積地で、
settings.json の hook command が `${CLAUDE_PROJECT_DIR}/project-portal/sites/rules/08-auto/<rule-name>/` を参照する。

---

## 6. CI/CD 基盤

### 6-1. GitHub Actions ワークフロー（ci.yml）

```yaml
name: CI

on:
  pull_request:
    branches: [main]
    paths:
      - 'src/**'
    paths-ignore:
      - 'src/**/*.test.*'

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    name: Test & Lint
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Lint
        run: npm run lint

      - name: Type check
        run: npm run typecheck

      - name: Test
        run: npm test

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: test-results/
          retention-days: 7
```

スタック別の拡張:
- フルスタック: FE/BE のジョブを並列化、Supabase CLI セットアップを追加
- E2E: Playwright のインストールとブラウザ起動を追加
- Python: setup-python + pip cache を追加

### 6-2. dependabot.yml

```yaml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "monthly"
    open-pull-requests-limit: 1
    groups:
      npm-deps:
        patterns:
          - "*"
```

スタック別の拡張:
- Python: `package-ecosystem: "pip"`, `directory: "/backend"` を追加

### 6-3. issue テンプレート

3 テンプレート + blank 禁止が標準セット:

| テンプレート | title prefix | label | 用途 |
|---|---|---|---|
| bug-report.md | `[Bug]:` | バグ | 既存機能のバグ報告 |
| feature-request.md | `[Feat]:` | 機能追加 | 新機能・改善提案 |
| problem-statement.md | `[Proposal]:` | 提案 | 解決策未定の問題提起 |

config.yml: `blank_issues_enabled: false`

### 6-4. PR テンプレート

PR テンプレート（`.github/pull_request_template.md`）の必須セクション構成:

| セクション | 内容 |
|---|---|
| 判断サマリ | 判断点の有無。pr-review-daily の自動承認判定に使用 |
| (見出し: 概要) | 変更の目的・背景を 1-2 文で |
| 変更フロー | Mermaid 図（API 追加・状態変化・複数コンポーネント連携時） |
| (見出し: なぜこの実装か) | 技術的な根拠 |
| 検討した代替案 | 不採用案とその理由 |
| 影響範囲 | 変更ファイル・影響する機能・破壊的変更の有無 |
| 確認方法 | レビュアーが動作を確認する手順 |
| テスト | 実施済みチェックリスト |
| 実害検証 | UI 操作 / API 呼び出し / E2E / 赤チーム検証の証跡 |
| 生成プロンプト | Claude Code で作成した場合の使用プロンプト |

正本は `<project>` の `.github/pull_request_template.md` を参照。
creating-new-project スキルはこのテーブルに基づいてプロジェクト固有のテンプレートを生成する。

### 6-5. qa/ 構成

```
qa/
├── user-stories.md       # Given-When-Then 形式のユーザーストーリー
└── qa-tracking.tsv       # QA ステータス追跡
```

#### user-stories.md テンプレート

```markdown
# ユーザーストーリー

## F-001: <機能名>

### US-001: <ストーリー名>

**Given** <前提条件>
**When** <操作>
**Then** <期待結果>

### US-002: <ストーリー名（異常系）>

**Given** <前提条件>
**When** <異常操作>
**Then** <エラー表示>
```

### 6-6. .husky/ git hook 構成

#### pre-commit

```bash
#!/usr/bin/env sh
. "$(dirname -- "$0")/_/husky.sh"

# 1. Claude markers guard
if git diff --cached --name-only | grep -q '\.claude/markers/'; then
  echo "ERROR: .claude/markers/ files must not be committed"
  exit 1
fi

# 2. Secret scanning
npx gitleaks protect --staged --config .config/gitleaks.toml

# 3. Lint staged files
npx lint-staged
```

#### pre-push

```bash
#!/usr/bin/env sh
. "$(dirname -- "$0")/_/husky.sh"

# 1. Author validation
ALLOW_NAME='<github-username>'
# ... author check logic

# 2. Hook unit tests
npm run test:flow-hooks 2>/dev/null || true

# 3. Diff-based quality checks (parallel FE/BE)
# ... changed file detection and conditional test/lint execution
```

### 6-7. .config/ セキュリティ・品質設定

#### gitleaks.toml テンプレート

```toml
title = "<project-name> secret detection"

[extend]
useDefault = true

[allowlist]
description = "Global allowlist for false positives"

paths = [
  '''node_modules/''',
  '''\.venv/''',
  '''\.git/''',
  '''\.claude/markers/''',
  '''\.env\.example$''',
]

regexTarget = "match"
regexes = [
  '''^[a-f0-9]{64}$''',
  '''^(?i)(example[-_]?|dummy[-_]?|test[-_]?|placeholder[-_]?)''',
]
```

#### lychee.toml テンプレート

```toml
verbose = "info"
no_progress = true
cache = true
max_cache_age = "1d"
max_concurrency = 8
timeout = 20
max_retries = 2

accept = [200, 206, 301, 302, 304, 307, 308, 429, 999]

exclude = [
  "^https?://localhost",
  "^https?://127\\.0\\.0\\.1",
  "^mailto:",
  "^tel:",
]

exclude_path = [
  "node_modules",
  "dist",
  "coverage",
  ".git",
  "test-results",
  "logs",
]
```

---

## 7. project-context/rule.md + flow-values.yml + layers.yml（プロジェクト標準構成規約 / orchestrating-dev-flow 連携）

スキーマ正本: `~/.claude/rules/scoped/agent-config/project-structure/rule.md`。旧 `.claude/skills/flow-config/`（flow-context.yml・layers.yml とも）は廃止済みでこの体系に吸収済み（互換レイヤなし）。

### 7-0. rule.md テンプレート（概要・技術スタック・索引部分は 80 行以内。許可リスト節は予算対象外）

```markdown
---
paths: []
---

# プロジェクトコンテキスト（PROJECT-CONTEXT）

<project-name> の概要・技術スタック・設定索引。実装フロー（orchestrating-dev-flow）が前提とする正本コンテキストで、セッション開始時に常時注入される。

## 概要

<目的を1文で>

## 技術スタック

| レイヤー | 技術 |
|---|---|
| フロントエンド | <framework> + TypeScript |
| FE テスト / Lint | <test-runner> / <linter> |
| バックエンド | <framework>（該当する場合） |
| BE テスト / Lint | <test-runner> / <linter>（該当する場合） |
| DB | <database>（該当する場合） |

## 設定索引

| 種別 | 場所 |
|---|---|
| 実装フロー設定値 | `.claude/rules/always/project-context/flow-values.yml`（本ファイルの機械可読サイドカー） |
| ドメイン用語辞書 | `.claude/rules/domain/dictionary/rule.md` |
| ドメイン制約 | `.claude/rules/domain/domain-constraints/rule.md` |
| 全域技術制約 | `.claude/rules/project/context-scope/rule.md` |
| コードベース境界 | `.claude/rules/project/codebase-boundary/rule.md` |
| レイヤー別コマンド体系 | `.claude/rules/always/project-context/layers.yml` |

## 任意受け口（置けば効く）

以下は未配置でもエラーにならない任意の上書き先。必要になったら作成する。

- 命名値の上書き: `.claude/rules/always/naming/commit-branch/naming-values.txt`
- プロジェクト辞書（textlint 語彙）: `.claude/rules/always/review-checklist/text-dictionary/prh.yml`
- レビュー観点（code / document / report ドメイン限定）: `.claude/rules/scoped/review-checklist/<domain>/<name>/rule.md`

## ルート直下許可ディレクトリ

| ディレクトリ名 | 用途 |
|---|---|
| src | ソースコード |
| docs | ドキュメント |

## 行動原則

- ルール正本は `project-portal/sites/rules/` 配下。hook が `[...-BLOCK]` / `[...-REQUIRED]` を注入したら該当 rule を Read して PROCEDURE に従う
- コード変更は対応する `docs/` の設計書更新を同一 PR に含めること必須
```

### 7-1. flow-values.yml 最小テンプレート（FE のみ）

固定スキーマ（正本のキー）は必ず全キーを埋める（値不明は `null` / `{}` / `[]`）。拡張キーはプロジェクト独自に追加してよい（正本スキーマの対象外・プロジェクト内の文書・スキルのみが消費）。

```yaml
# <project-name> flow-values.yml
# スキーマ正本: ~/.claude/rules/scoped/agent-config/project-structure/rule.md

# --- 固定スキーマ ---
domain_glossary: .claude/rules/domain/dictionary/rule.md
design_system: null
test_conventions: .claude/rules/project/context-scope/test/rule.md
adr_dir: null
design_docs: docs
portal_dir: project-portal

review_gates:
  pre_impl: null
  impl_quality: null
  pre_push: null
  e2e: null

review_agents: {}

pr:
  template: .github/pull_request_template.md
  required_sections:
    - "## 概要"
    - "## なぜこの実装か"
    - "## 影響範囲"
    - "## 確認方法"
    - "## テスト"
    - "## 生成プロンプト"
    - "## 実害検証"
  critical_globs:
    - "src/**"
  skip_globs: []

classify:
  quick_max_files: 2
  quick_excludes:
    - migration
    - schema_change
    - api_contract
    - ui_component

preflight:
  skip_tools: []

# --- 拡張キー（プロジェクト独自。正本スキーマの対象外） ---
project_index: project-portal/data/master-tables/project-index.js
techstack: project-portal/data/master-tables/techstack.js
master_tables:
  - project-portal/data/master-tables/features.js
  - project-portal/data/master-tables/screens.js

screen_docs:
  base_dir: docs/02_画面基本設計
  files_per_screen:
    - 画面基本設計書.md
    - DESIGN.md
    - 結合テスト観点表.md

test:
  fe_unit_cmd: "npx vitest run"
  fe_lint_cmd: "npx biome check"
  fe_type_check_cmd: "npx tsc --noEmit"

flow:
  log_dir: logs/flow-feature
  recur_min: 3
  slow_step_min: 120
  slow_session_min: 3600
```

### 7-2. フルスタック追加分（FE + BE + DB）

```yaml
# 上記最小テンプレートに加えて以下を追加・変更

# --- 拡張キー ---
architecture:
  - project-portal/sites/rules/02-design/architecture/overview/rule.html
  - project-portal/sites/rules/02-design/architecture/structure/rule.html
master_tables:
  - project-portal/data/master-tables/features.js
  - project-portal/data/master-tables/screens.js
  - project-portal/data/master-tables/api.js
  - project-portal/data/master-tables/operation-flow.js
design_rules:
  - project-portal/sites/rules/06-design/patterns/rule.html
  - project-portal/sites/rules/06-design/design-system/rule.html
test_rules:
  - project-portal/sites/rules/05-test/test-policy/rule.html

# E2E テスト設定（DB ありの場合のみ）
e2e:
  fe_url: "http://localhost:<fe-port>"
  be_url: "http://localhost:<be-port>"
  test_cmd: "<e2e-command>"
  db_start_cmd: "<db-start-command>"
  health_endpoint: /api/health

test:
  fe_unit_cmd: "cd frontend && npx vitest run"
  fe_lint_cmd: "cd frontend && npx biome check"
  fe_type_check_cmd: "cd frontend && npx tsc --noEmit"
  be_unit_cmd: "cd backend && .venv/bin/pytest tests/"
  be_lint_cmd: "cd backend && .venv/bin/ruff check"
  be_type_check_cmd: "cd backend && .venv/bin/mypy app/"
```

### 7-3. layers.yml テンプレート

```yaml
# <project-name> layers.yml
# レイヤー別のコマンド体系

layers:
  - name: frontend
    src: src              # or frontend/src
    lint: "npx biome check src"
    test: "npx vitest run"
    coverage: "npx vitest run --coverage"
    type_check: "npx tsc --noEmit"

  # フルスタック時に追加
  # - name: backend
  #   src: backend/app
  #   lint: "backend/.venv/bin/ruff check backend/"
  #   test: "cd backend && .venv/bin/pytest tests/ -q"
  #   coverage: "pytest --cov"
  #   type_check: "backend/.venv/bin/mypy backend/app"
```

---

## 8. 構成要素の導入マップ

creating-new-project スキルが生成する範囲と、プロジェクト成長に伴い追加する範囲を定義する。

### Tier 1: プロジェクト作成直後（creating-new-project が生成）

| 要素 | 内容 |
|---|---|
| CLAUDE.md | 技術スタック・コマンド・行動原則 |
| .claude/settings.json | 最小 permission のみ（hooks は空配列） |
| .claude/rules/always/project-context/ | rule.md（概要・設定索引・ルート直下許可リスト節）+ flow-values.yml（最小）+ layers.yml（最小） |
| .gitignore | Claude Code + IDE + logs 対応 |
| docs/REQUIREMENTS.md | ヒアリング結果 |
| Makefile | dev / test / lint の基本 target |

### Tier 2: 最初の機能実装時

| 要素 | 内容 |
|---|---|
| docs/01_機能基本設計/<機能名>/ | 機能設計書 |
| docs/02_画面基本設計/<画面名>/ | 画面設計書 4 ファイルセット |
| .claude/rules/project/context-scope/ | 全域制約 + レイヤー別 lazy rule |
| .github/pull_request_template.md | PR テンプレート |
| .github/ISSUE_TEMPLATE/ | issue テンプレート 3 種 |

### Tier 3: チーム開発・品質強化時

| 要素 | 内容 |
|---|---|
| .husky/pre-commit | lint-staged + gitleaks |
| .husky/pre-push | author 検証 + テスト |
| .config/gitleaks.toml | シークレット検知設定 |
| .config/lychee.toml | リンク切れ検査 |
| .github/workflows/ci.yml | PR 時自動テスト |
| .github/dependabot.yml | 依存更新 |
| qa/ | ユーザーストーリー + QA 追跡 |

### Tier 4: ポータル・自動化成熟期

| 要素 | 内容 |
|---|---|
| project-portal/ | 管理ポータル SPA |
| project-portal/sites/rules/ | ルール HTML + hook スクリプト |
| project-portal/data/master-tables/ | マスタテーブル群 |
| .claude/rules/domain/ | ドメイン辞書・ビジネス制約 |

| settings.json hook 拡張 | 20+ hooks（commit/merge/test/naming 等） |
| logs/ | ルーティン出力ディレクトリ群 |

---

## 9. `<project>` 固有要素の汎化対応表

| `<project>` 固有 | 汎化形 |
|---|---|
| React 19 + Vite | `<FE framework>` |
| FastAPI + Python 3.11 | `<BE framework>`（FE only なら省略） |
| Supabase (PostgreSQL) | `<DB>`（FE only なら省略） |
| frontend/ + backend/ | src/（モノリスの場合） |
| Vitest / Biome | `<test-runner>` / `<linter>` |
| pytest / Ruff / mypy | `<BE test>` / `<BE lint>` / `<BE type-check>` |
| supabase/ migrations | `<DB migration dir>` |
| port 5173 / 8000 | ポート管理規約に基づくベースポート + オフセット |
| game-constraints/rule.md | domain/<constraint-name>/rule.md |
| ゲーム用語辞書 | domain/dictionary/rule.md（ドメイン用語） |
| data/character-images/ | data/<domain-specific>/（ドメインデータ） |
| Render (backend) | `<hosting provider>` |
| Vercel (frontend) | `<hosting provider>` |
| E2E: Playwright | `<E2E framework>`（必要に応じて追加） |

---

## 10. ポータル sites/rules/ と .claude/rules/ の使い分け

hook スクリプトの配置場所は 2 系統ある。

| 配置場所 | 用途 | 可視性 |
|---|---|---|
| `.claude/rules/<category>/<name>/` | Claude Code native rule（paths 付き lazy ロード対応） | Claude Code のみ |
| `project-portal/sites/rules/<NN>-<category>/<name>/` | ポータル統合ルール（HTML 散文 + hook スクリプト同居） | ポータルで閲覧可能 |

使い分けの判断基準:

- Claude Code の paths 付き lazy ロードが必要 → `.claude/rules/`
- ポータルでルールを HTML 表示したい → `project-portal/sites/rules/`
- hook スクリプトのみ（ルール文書不要） → `project-portal/sites/rules/08-auto/`
- 両方必要 → `.claude/rules/` に rule.md、`project-portal/sites/rules/` に rule.html + hook

プロジェクト初期は `.claude/rules/` のみで十分。ポータル統合は Tier 4 に該当する。
