# Phase 2-4: スキャフォールド・Claude Code 基盤・ドキュメント体系（詳細手順）

> `creating-new-project/SKILL.md` の Phase 2〜4 詳細。

## Phase 2: スキャフォールド

### 2-1. create-next-app 実行

```bash
cd ~/Projects
npx create-next-app@latest <project-name> \
  --typescript --tailwind --eslint --app \
  --src-dir --import-alias "@/*" \
  --no-turbopack --use-npm
```

スタックが `React + Vite + FastAPI` の場合は代わりに:
```bash
cd ~/Projects && mkdir <project-name> && cd <project-name>
mkdir frontend backend
cd frontend && npm create vite@latest . -- --template react-ts
cd ../backend && python3 -m venv .venv && pip install fastapi uvicorn
```

### 2-2. 画面別ルーティング生成

Phase 1 の画面一覧に基づき、ページファイルを生成する。

テンプレート:
```tsx
export default function <PageName>Page() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center p-24">
      <h1 className="text-4xl font-bold"><画面名></h1>
      <p className="mt-4 text-lg text-gray-500">このページは準備中です</p>
    </main>
  )
}
```

ルーティング:
- `/` → `src/app/page.tsx`
- `/dashboard` → `src/app/dashboard/page.tsx`
- `/tasks/[id]` → `src/app/tasks/[id]/page.tsx`

### 2-3. docs/REQUIREMENTS.md 配置

テンプレートは `project-structure-reference-model.md` §4 を参照。Phase 1 の値で置換する。

---

## Phase 3: Claude Code 基盤

`.claude/rules/` を実体ディレクトリとして作成し、rules（domain / project / always）・settings.json を構築する。domain・project カテゴリの各 rule.md は正本 `~/agent-home/templates/project-claude-rules/` からコピーし、プレースホルダを置換する。always カテゴリはプロジェクト標準構成規約（`~/.claude/rules/scoped/agent-config/project-structure/rule.md`）の必須 2 ファイル（project-context/rule.md（`## ルート直下許可ディレクトリ` 節を含む）・flow-values.yml）をこの Phase で新規生成する。レイヤー別コマンド体系 `layers.yml` も project-context/ 配下に同じ Phase で配置する（`.claude/skills/flow-config/` は廃止済み・跡地なし）。flow 系 rules（loop-commit / session-context）は scaffold しない。

### 3-1. ディレクトリ作成

```
.claude/
├── settings.json
└── rules/
    ├── always/
    │   └── project-context/
    │       ├── rule.md                    # プロジェクト概要・設定索引・ルート直下許可リスト節（★必須）
    │       ├── flow-values.yml            # 実装フロー設定値（★必須）
    │       └── layers.yml                 # レイヤー別コマンド体系（★必須）
    ├── domain/
    │   ├── dictionary/
    │   │   └── rule.md
    │   └── domain-constraints/
    │       └── rule.md
    └── project/
        ├── context-scope/
        │   ├── rule.md
        │   └── frontend/
        │       └── rule.md
        └── codebase-boundary/
            └── rule.md
```

### 3-2. rules/domain/dictionary/rule.md

コピー元: `~/agent-home/templates/project-claude-rules/domain/dictionary/rule.md`

コピー後にプロジェクト固有の用語エントリを追記する。Phase 1 の機能名・画面名から初期エントリを生成する。

| プレースホルダ | 置換値 |
|---|---|
| `<プロジェクト名>` | Phase 1 の `project_name` |
| `<domain-term-N>` | Phase 1 の機能名・画面名 |

### 3-3. rules/domain/domain-constraints/rule.md

コピー元: `~/agent-home/templates/project-claude-rules/domain/domain-constraints/rule.md`

プロジェクト固有のドメイン制約（ビジネスルール・バリデーション等）を記載する。コピー後に `<プロジェクト名>` をプロジェクト名で置換する。

### 3-4. rules/project/context-scope/

コピー元: `~/agent-home/templates/project-claude-rules/project/context-scope/`

`rule.md`（親ルール）と `frontend/rule.md`（paths 付き lazy rule）をコピーする。コピー後に以下を実施する。

| プレースホルダ | 置換値 |
|---|---|
| `<プロジェクト名>` | Phase 1 の `project_name` |
| `<fe-src>` | スタックに応じて `src` または `frontend/src` |

スタックがフルスタックの場合、`backend/rule.md`・`db/rule.md` を追加コピーする。test は全スタックで配置する（FE のみ構成でも Vitest 等のテスト規約が必要）ため、`test/rule.md` は常に含める。FE のみ構成では `backend/`・`db/` は作成しない。

### 3-5. project-context/rule.md のルート直下許可リスト節

コピー元テンプレート: `~/agent-home/templates/project-claude-rules/project/directory-structure/rule.md`（許可リストのテーブル部分のみ流用）
配置先: `.claude/rules/always/project-context/rule.md` 内の `## ルート直下許可ディレクトリ` 節（専用ファイルは廃止。`check-mkdir-allowlist.sh` hook はこの節を正規パスとして参照する）

テンプレートのテーブル部分をスタックに応じて追加・削除し、project-context/rule.md の設定索引の下に `## ルート直下許可ディレクトリ` 節として挿入する。

| スタック | 対応 |
|---|---|
| FE のみ | `src`・`public` 行を残す。`frontend`・`backend`・`supabase` 行は削除 |
| フルスタック | `frontend`・`backend`・`supabase` を追加。`src` を `frontend` に変更 |

### 3-5b. codebase-boundary テンプレートの複製

`~/agent-home/templates/project-claude-rules/project/codebase-boundary/rule.md` を `.claude/rules/project/codebase-boundary/rule.md` へ複製する。複製後に以下を実施する。

1. `paths` セクションをプロジェクトの実構成（`src/`・`frontend/`・`backend/` 等）に合わせて書き換える。テンプレート内のスタックに存在しないパス・正規表の行は削除する（例: FE のみ構成の場合は `lib/**` を削除する）
2. `<プロジェクト名>` を Phase 1 の `project_name` で置換する

### 3-6. rules/always/project-context/

プロジェクト標準構成規約の必須ファイルとして `.claude/rules/always/project-context/rule.md`（3-5 の `## ルート直下許可ディレクトリ` 節を含む）・`flow-values.yml` を配置する。テンプレートは `project-structure-reference-model.md` §7 を参照。Phase 1 のスタック選択に基づき最小テンプレートまたはフルスタックテンプレートを選択する。任意受け口（naming-values.txt・prh.yml・scoped/review-checklist）はこの時点では生成せず、`project-context/rule.md` の設定索引に「置けば効く受け口」として案内のみ記載する。

`.claude/rules/always/project-context/layers.yml`（レイヤー別コマンド体系）も同じ Phase で配置する。テンプレートは `project-structure-reference-model.md` §7-3 を参照。

### 3-7. settings.json

テンプレートは `project-structure-reference-model.md` §3-3 を参照。初期構成:
- `worktree.baseRef: "fresh"`
- `hooks`: 初期は全て空配列。flow 系 hook はグローバル層の管轄のため含めない
- `permissions`: Agent, Skill, git, make, npm, gh, curl
- `outputStyle: "Proactive"`

スタックがフルスタックの場合、permissions に python/pytest/ruff 等を追加する。

### 3-8: flow 前提構造の補足検証

`scaffolding-flow-structure.md` を Read し、Step 5（DESIGN.md 生成）を実行してから、Step 7（`orchestrating-dev-flow/references/module-preflight-check.md` を Read して実行するプリフライトチェック）を実行して、3-2〜3-7 で生成した flow 前提構造（flow-values.yml・layers.yml・rules 一式）が orchestrating-dev-flow の前提条件を満たすか検証する。

同ファイルの Step 1〜4・6 は 3-1〜3-7・Phase 1・Phase 5 で既に実施済みのため再実行しない。`project-portal/` は Phase 5 の手順（oradora-battle-base 参照）を正とし、同ファイル Step 3 の `scaffolding-assets/portal-template/` コピー手順は Phase 5 が未整備な場合の代替手段としてのみ使う。**Step 5（DESIGN.md 生成）は 3-1〜3-7・Phase 1・Phase 5 のいずれでも実行されないため、Step 7（プリフライトチェック）の前に Step 5 を実行する。**

- go → Phase 4 に進む
- no-go → FAIL 項目を修正してから Phase 4 に進む

---

## Phase 4: ドキュメント体系

`docs/` 配下に番号付き 4 カテゴリを作成し、初期ドキュメントを配置する。

### 4-1. カテゴリ作成

```bash
mkdir -p docs/01_機能基本設計
mkdir -p docs/02_画面基本設計/_共通
mkdir -p docs/03_操作フロー設計
mkdir -p docs/04_開発プロセス設計
```

### 4-2. 機能設計書の初期生成

Phase 1 の機能リストから、各機能の設計書ディレクトリと初期ファイルを生成する。

```
docs/01_機能基本設計/<機能名>/
├── 機能基本設計書.md
├── 単体テスト観点表.md
└── 結合テスト観点表.md
```

コピー元は `~/agent-home/templates/project-docs/01_機能基本設計/`。frontmatter の `status: draft` で作成する。

### 4-3. 画面設計書の初期生成（4 ファイルセット + 共通）

Phase 1 の画面リストから、各画面の 4 ファイルセットを生成する。

```
docs/02_画面基本設計/<画面名>/
├── 画面基本設計書.md
├── DESIGN.md
├── 単体テスト観点表.md
└── 結合テスト観点表.md
```

コピー元は `~/agent-home/templates/project-docs/02_画面基本設計/`（`doc_id`・`target_screen`・`route` を Phase 1 の値で置換する）。

加えて `templates/project-docs/02_画面基本設計/_共通/` の 3 ファイル（DESIGN.md・メッセージ定義書.md・画面共通仕様.md）をプロジェクトに 1 セット `docs/02_画面基本設計/_共通/` へ配置する。

```
docs/02_画面基本設計/_共通/
├── DESIGN.md
├── メッセージ定義書.md
└── 画面共通仕様.md
```

### 4-4. 操作フロー設計書の初期生成

Phase 1 の機能から主要な操作フローを推論し、初期設計書を生成する。

コピー元は `~/agent-home/templates/project-docs/03_操作フロー設計/` の 2 ファイル（操作フロー設計書.md・E2Eテスト観点表.md）。`flow_name` を置換して各フローへ複製する。

```
docs/03_操作フロー設計/<フロー名>/
├── 操作フロー設計書.md
└── E2Eテスト観点表.md
```

### 4-5. 開発プロセス設計の初期ドキュメント

```
docs/04_開発プロセス設計/環境変数一覧.md
docs/04_開発プロセス設計/用語集.md
docs/04_開発プロセス設計/プロジェクト地図.md
```

`環境変数一覧.md` にはスタック依存の環境変数を列挙する。`用語集.md` は `rules/domain/dictionary/rule.md` へのポインタ。`プロジェクト地図.md` は `templates/project-docs/04_開発プロセス設計/プロジェクト地図.md` を複製し、プロジェクト名・モジュール一覧を記入する。

### 4-6. 設計書レビュー観点の配置

`templates/project-docs/設計書レビュー観点.md` を `docs/` 直下へ複製する（変更なし、参照専用）。

```
docs/設計書レビュー観点.md
```
