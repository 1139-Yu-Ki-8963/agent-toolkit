# Phase 6-10: CI/CD・ルート設定・ポート登録・Git・検証（詳細手順）

> `creating-new-project/SKILL.md` の Phase 6〜10 詳細。

## Phase 6: CI/CD・品質基盤

### 6-1. .github/ ディレクトリ

```
.github/
├── pull_request_template.md
├── dependabot.yml
├── workflows/
│   └── ci.yml
└── ISSUE_TEMPLATE/
    ├── bug-report.md
    ├── feature-request.md
    ├── problem-statement.md
    └── config.yml
```

テンプレートは `project-structure-reference-model.md` §6 を参照。

PR テンプレートの必須セクション:
- 判断サマリ / 概要 / 変更フロー / なぜこの実装か / 検討した代替案
- 影響範囲 / 確認方法 / テスト / 実害検証 / 生成プロンプト

### 6-1b. docs リンク検査（lychee CI ジョブ）

`.github/workflows/ci.yml` に docs リンク検査ジョブを追加する。`.config/lychee.toml` の設定を使用する。

```yaml
  docs-check:
    name: Docs Link Check
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4

      - name: Check links (lychee)
        uses: lycheeverse/lychee-action@v2
        with:
          args: --config .config/lychee.toml docs/
          fail: true
```

`on.pull_request.paths` に `'docs/**'` を追加してドキュメント変更時にも CI が発火するようにする。

### 6-2. .husky/ ディレクトリ

```bash
cd ~/Projects/<project-name>
npx husky init
```

- `pre-commit` — .claude/markers/ ガード + gitleaks + lint-staged
- `pre-push` — author 検証 + テスト + lint

### 6-3. .config/ ディレクトリ

- `gitleaks.toml` — シークレット検知設定
- `lychee.toml` — リンク切れ検査設定

### 6-4. qa/ ディレクトリ

- `user-stories.md` — Phase 1 の機能リストから Given-When-Then 形式で生成
- `qa-tracking.tsv` — 空の QA ステータス追跡

### 6-5. logs/ ディレクトリ

```bash
mkdir -p logs/flow-feature && touch logs/flow-feature/.gitkeep
```

---

## Phase 7: ルート設定

### 7-1. CLAUDE.md

テンプレートは `project-structure-reference-model.md` §2-1 を参照。200 行以内。

### 7-2. .gitignore

テンプレートは `project-structure-reference-model.md` §2-2 を参照。

### 7-3. .gitattributes

テンプレートは `project-structure-reference-model.md` §2-3 を参照。

### 7-4. Makefile

テンプレートは `project-structure-reference-model.md` §2-4 を参照。

### 7-5. dev server ポート設定

`package.json` の `dev` スクリプトにポートを設定:
```json
"dev": "next dev -p <base_port+1>"
```

---

## Phase 8: ポート割当登録

`~/.claude/rules/always/local-environment/port-management/rule.md` を Edit で更新する。

### 8-1. ベースポートテーブルに追加

### 8-2. 割当表セクションを追加

スタックに応じた列構成:
- FE のみ: frontend + portal
- フルスタック: backend + frontend + portal + DB tools

---

## Phase 9: Git + GitHub

### 9-1. Git 初期化

```bash
cd ~/Projects/<project-name>
git init
git add -A
git commit -m "【初期構築】<project-name> プロジェクト作成"
```

### 9-2. GitHub リポジトリ作成

AskUserQuestion で確認してから実行:
- `作成して push` — `gh repo create --private --source=. --push`
- `ローカルのみ` — GitHub リポジトリは作成しない
- `中止` — Phase 9 を中止

---

## Phase 10: 検証

### 10-1. 構造検証

以下のディレクトリ・ファイルが全て存在することを確認する:

```bash
# ルート直下
ls ~/Projects/<project-name>/{CLAUDE.md,Makefile,.gitignore,.gitattributes,package.json}

# .claude/ 基盤
ls ~/Projects/<project-name>/.claude/settings.json
find ~/Projects/<project-name>/.claude/rules -name 'rule.md' | wc -l  # 8+ ファイル
ls ~/Projects/<project-name>/.claude/rules/always/project-context/{rule.md,flow-values.yml,layers.yml}
ls ~/Projects/<project-name>/.claude/rules/always/placement/directory-structure/rule.md

# docs/ 体系
ls -d ~/Projects/<project-name>/docs/{01_機能基本設計,02_画面基本設計,03_操作フロー設計,04_開発プロセス設計}
find ~/Projects/<project-name>/docs -name '*.md' | wc -l

# project-portal/
ls ~/Projects/<project-name>/project-portal/{index.html,style.css}
ls ~/Projects/<project-name>/project-portal/data/manifest.js
ls ~/Projects/<project-name>/project-portal/src/main.js

# CI/CD
ls ~/Projects/<project-name>/.github/pull_request_template.md
ls ~/Projects/<project-name>/.github/workflows/ci.yml
ls ~/Projects/<project-name>/.github/ISSUE_TEMPLATE/config.yml

# QA
ls ~/Projects/<project-name>/qa/user-stories.md
```

欠落があれば Phase を遡って補完する。

### 10-2. dev server 起動確認

```bash
cd ~/Projects/<project-name>
npm run dev &
sleep 5
curl -s -o /dev/null -w "%{http_code}" http://localhost:<base_port+1>
kill %1 2>/dev/null || true
```

HTTP 200 が返れば成功。

### 10-3. ポータル起動確認

```bash
cd ~/Projects/<project-name>
python3 project-portal/tools/serve.py &
sleep 3
curl -s -o /dev/null -w "%{http_code}" http://localhost:<base_port+2>
kill %1 2>/dev/null || true
```

HTTP 200 が返れば成功。

### 10-4. 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- 構造検証（10-1）の欠落有無
- dev server 起動確認（10-2）の HTTP ステータス
- ポータル起動確認（10-3）の HTTP ステータス
