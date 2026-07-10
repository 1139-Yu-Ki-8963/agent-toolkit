---
name: consult-analyze
description: 顧客リポジトリの解析レポートHTMLを生成する。技術構成・規約状況・テスト分布を可視化する。 TRIGGER when: 「リポジトリを解析」「プロジェクト解析」「構成を見せて」と言われた時。 SKIP: 解析済みで規約整備のみの場合（→consult-repo-rules）。
invocation: consult-analyze
type: transform
allowed-tools: Read, Write, Bash, Glob
---

# プロジェクト解析レポートの生成（consult-analyze）

顧客リポジトリ（以下 `<repo>`）を受け取った直後に「何がどう作られているか」を自動解析し、技術構成・ファイル分布・テストの有無・規約の状況・依存関係を1枚HTMLで可視化する。consult-repo-rules の Phase 1（リポジトリ解析）を独立させ、ヒアリングの裏付けと提案の根拠に使える納品物として出す。

## Phase 1: 基本情報の収集

`<repo>` の言語・枠組み・ディレクトリ構成・ファイル分布・規模を機械的に集計する。

### Step 1-1: 言語・枠組みの検出

Bash で `find <repo> -type f | sed 's/.*\.//' | sort | uniq -c | sort -rn` を実行し拡張子分布を把握する。合わせて Read で `package.json` / `requirements.txt` / `go.mod` 等の依存管理ファイルを確認し、主要言語・フレームワークを特定する。

**入力**: `<repo>` のルートパス
**完了**: 主要言語・依存管理ファイル・フレームワークが特定されている

### Step 1-2: ディレクトリ構成の取得

Bash で `find <repo> -maxdepth 2 -type d` を実行し、ルート直下2階層のディレクトリ構成を取得する。

**入力**: `<repo>` のルートパス
**完了**: ルート直下2階層のディレクトリ構成が取得されている

### Step 1-3: ファイル分布の集計

Bash で `find <repo> -type f | sed 's/.*\.//' | sort | uniq -c | sort -rn` を実行し、拡張子別のファイル件数を集計する。

**入力**: `<repo>` のルートパス
**完了**: 拡張子別のファイル件数が集計されている

### Step 1-4: 総行数の集計

Bash で `find <repo> -type f -name '*.<ext>' | xargs wc -l` 相当を主要拡張子ごとに実行し、総行数と行数上位10ファイルを集計する。

**入力**: Step 1-3 で判明した主要拡張子
**完了**: 総行数と行数上位10ファイルが集計されている

完了条件: 言語・枠組み・ディレクトリ構成・ファイル分布・行数上位10ファイルが集計されている

## Phase 2: 品質基盤の確認

テスト・lint・CI・規約・依存の有無を機械的に確認する。推測でなく検出事実のみ扱う。

### Step 2-1: テストの有無と分布

Glob で `*test*` / `*spec*` / `tests/**` / `__tests__/**` を検索し、テストファイルの有無と分布を確認する。

**入力**: `<repo>` のルートパス
**完了**: テストファイルの有無と分布が確認されている

### Step 2-2: lint設定の有無

Glob で `.eslintrc*` / `.textlintrc*` / `.prettierrc*` / `pyproject.toml` 等を検索し、lint設定の有無を確認する。

**入力**: `<repo>` のルートパス
**完了**: lint設定ファイルの有無が確認されている

### Step 2-3: CI設定の有無

Glob で `.github/workflows/**` / `.gitlab-ci.yml` 等を検索し、CI設定の有無を確認する。

**入力**: `<repo>` のルートパス
**完了**: CI設定ファイルの有無が確認されている

### Step 2-4: 規約の有無

Glob で `CLAUDE.md` / `.claude/rules/**` / `CONTRIBUTING.md` を検索し、規約整備の有無を確認する。

**入力**: `<repo>` のルートパス
**完了**: 規約整備の有無が確認されている

### Step 2-5: 依存の数と種類

Bash で `package.json` の `dependencies`/`devDependencies` 数、`requirements.txt` の行数等を確認し、依存の数と主要な依存を把握する。

**入力**: Step 1-1 で確認した依存管理ファイル
**完了**: 依存の数と主要な依存が把握されている

完了条件: テスト・lint・CI・規約・依存それぞれの有無と数が確認されている

## Phase 3: レポートHTML生成

`references/analyze-report-template.html` を雛形にレポートを生成する。

### Step 3-1: テンプレートの読み込み

Read で `references/analyze-report-template.html` を読み込み、プレースホルダ構成・§構成を確認する。

**入力**: `references/analyze-report-template.html`
**完了**: プレースホルダ一覧と§構成を把握している

### Step 3-2: プレースホルダの置換

Phase 1・Phase 2 で収集した結果を `{{...}}` プレースホルダへ実データとして割り当てる。ディレクトリ構成は `<pre>` のツリー表示、ファイル分布・規模上位・品質基盤・依存関係は各表形式に整形する。

**入力**: Step 3-1 のテンプレート、Phase 1・Phase 2 の集計結果
**完了**: プレースホルダに対応する実データが整形されている

### Step 3-3: 出力

Write で `clients/<案件名>/プロジェクト解析_<YYYYMMDD>.html` にテンプレートをコピーしたうえで `{{...}}` プレースホルダを全て実データで置換して出力する。

**入力**: Step 3-2 で整形した実データ
**完了**: `clients/<案件名>/プロジェクト解析_<YYYYMMDD>.html` が生成されている

完了条件: Phase 1・Phase 2の集計結果を反映したレポートHTMLが生成されている

## Phase 4: 所見の記載

検出事実から読み取れる所見のみを記載する。推測は書かない。

### Step 4-1: 所見の抽出

Phase 1・Phase 2 の集計結果から読み取れる事実の所見を3〜5点抽出する（テストがない領域・lint未導入・規約の有無等）。推測ではなく検出事実だけを書く。

**入力**: Phase 1・Phase 2 の集計結果
**完了**: 検出事実に基づく所見が3〜5点抽出されている

### Step 4-2: HTMLへの追記

Edit で Step 4-1 の所見を Step 3-3 で出力したHTMLの所見セクション（§7）に追記する。

**入力**: Step 4-1 の所見、Step 3-3 で出力したHTML
**完了**: 所見セクションに所見が反映されている

完了条件: 検出事実に基づく所見がHTMLの所見セクションに反映されている

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 言語・枠組み・ディレクトリ構成・ファイル分布・行数上位10ファイルが集計されている |
| Phase 2 | テスト・lint・CI・規約・依存それぞれの有無と数が確認されている |
| Phase 3 | Phase 1・Phase 2の集計結果を反映したレポートHTMLが生成されている |
| Phase 4 | 検出事実に基づく所見がHTMLの所見セクションに反映されている |
| **Goal** | 顧客リポジトリの技術構成・ファイル分布・テストの有無・規約の状況・依存関係が1枚HTMLで可視化されている |

## Gotchas

- 所見は検出事実のみを書く。推測・評価の断定（「品質が低い」等）は書かない
- コンサル環境の固有情報（利用者名・内部パス）をレポートHTMLに書かない
- `analyze-report-template.html` の `<style>` とズーム script は変更しない。プレースホルダ置換のみ行う
- レポート HTML に consult- で始まる名称・環境固有のパスを含めない（`.claude/skills/shared/references/customer-output-checklist.md` の自問チェックに従う）。

## 完了報告

- `.claude/skills/shared/references/completion-report-format.md` の作業報告型骨格に従う
- 固有の検証行として、生成したレポートHTMLのパス・検出した所見件数・品質基盤の有無サマリの3点を追加する
