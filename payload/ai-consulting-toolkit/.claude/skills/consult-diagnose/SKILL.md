---
name: consult-diagnose
description: 顧客のClaude Code設定を診断し、規約・スキル・hookの整備状況レポートを生成する。 TRIGGER when: 「設定を診断」「ルールの状態を見て」「スキルを点検」と言われた時。 SKIP: 新規設定の導入作業の場合（→consult-lint-setup / consult-repo-rules）。
invocation: consult-diagnose
type: transform
allowed-tools: Read, Write, Bash, Glob
---

# 設定診断（consult-diagnose）

顧客プロジェクトに存在する Claude Code 設定（CLAUDE.md・`.claude/rules/`・`.claude/skills/`・`settings.json` の hooks）を診断し、「何が設定されていて、何が足りないか」を HTML レポートにまとめる実行スキル。consult-repo-rules（規約整備）・consult-lint-setup（lint 導入）の前段に置き、提案の根拠を現状診断として提供する。

## Phase 1: 設定資産の検出

対象リポジトリ（以下 `<repo>`）で次を検出する。

### Step 1-1: CLAUDE.md の検出

Glob (`CLAUDE.md`) で有無を確認し、存在すれば Bash (`wc -l`) で行数を計測する。

**入力**: `<repo>` のルートパス
**完了**: CLAUDE.md の有無と行数が把握されている

### Step 1-2: rule.md 一覧の取得

Glob (`**/rule.md`) で `.claude/rules/` 配下の rule.md を一覧化し、各ファイルを Bash (`wc -l`) で行数計測する。

**入力**: `<repo>/.claude/rules/`
**完了**: rule.md の一覧と各行数が把握されている

### Step 1-3: SKILL.md 一覧の取得

Glob (`**/SKILL.md`) で `.claude/skills/` 配下の SKILL.md を一覧化し、各ファイルの frontmatter を Bash (`grep`) で走査して `name` / `type` を抽出する。

**入力**: `<repo>/.claude/skills/`
**完了**: SKILL.md の一覧と各 name/type が把握されている

### Step 1-4: hooks 構成の抽出

Read で `<repo>/.claude/settings.json` を読み、`hooks` オブジェクトからイベント名と matcher の一覧を抽出する。

**入力**: `<repo>/.claude/settings.json`
**完了**: hooks のイベント名と matcher 一覧が把握されている（settings.json 不在なら「なし」と記録する）

### Step 1-5: permissions 構成の抽出

Read した `<repo>/.claude/settings.json` の `permissions.allow` / `permissions.deny` の件数を数える。

**入力**: `<repo>/.claude/settings.json`
**完了**: allow / deny の件数が把握されている

完了条件: CLAUDE.md・rule.md 一覧・SKILL.md 一覧・hooks 構成・permissions 構成が把握されている

## Phase 2: 品質指標の計測

Phase 1 で検出した資産を対象に、機械強制の有無と Step 粒度化の有無を計測する。

### Step 2-1: ルールごとの機械強制有無

Step 1-2 の各 rule.md について、同一ディレクトリ内の hook スクリプト（`.sh`）の有無を Bash (`find`) で確認し、機械強制の有無を判定する。

**入力**: Step 1-2 の rule.md 一覧
**完了**: ルールごとの行数と機械強制（hook）有無が対応付けられている

### Step 2-2: スキルごとの Step 粒度確認

Step 1-3 の各 SKILL.md を Read し、`## Phase` の数と `### Step` の有無を確認する。

**入力**: Step 1-3 の SKILL.md 一覧
**完了**: スキルごとの Phase 数と Step 有無が把握されている

### Step 2-3: hook スクリプトの構文検査

Step 1-4 で抽出した hook の command パスそれぞれに Bash (`bash -n <path>`) を実行し、exit 0 以外のものをエラーとして一覧化する。

**入力**: Step 1-4 で抽出した hook command パス一覧
**完了**: hook スクリプトの構文検査結果（PASS/FAIL）が一覧化されている

### Step 2-4: 網羅性チェック

CLAUDE.md・rules・skills・hooks の 4 項目それぞれについて、Phase 1 の検出結果から「あり」「なし」を判定する。

**入力**: Step 1-1〜1-4 の検出結果
**完了**: 4 項目それぞれの「あり/なし」判定が確定している

完了条件: ルールごとの機械強制有無・スキルごとの Step 粒度・hook 構文検査結果・4 項目の網羅性判定が揃っている

## Phase 3: レポート HTML 生成

### Step 3-1: テンプレート読み込み

Read で `references/diagnose-report-template.html` を読み込む。

**入力**: `references/diagnose-report-template.html`
**完了**: テンプレートの構成を把握している

### Step 3-2: 検出結果・計測値の埋め込み

Phase 1・Phase 2 で得た検出結果と計測値を、テンプレート内の `{{...}}` プレースホルダおよび各 `table.spec` 行に埋め込む。

**入力**: Phase 1・Phase 2 の全結果、Step 3-1 で読み込んだテンプレート
**完了**: プレースホルダと表行がすべて実データに置換されている

### Step 3-3: 出力

Write で `clients/<案件名>/設定診断_<YYYYMMDD>.html` として出力する。

**入力**: Step 3-2 で埋め込み済みの HTML 内容
**完了**: `clients/<案件名>/設定診断_<YYYYMMDD>.html` が出力されている

完了条件: 検出結果・計測値を埋め込んだレポート HTML が `clients/<案件名>/設定診断_<YYYYMMDD>.html` に出力されている

## Phase 4: 推奨アクションの記載

### Step 4-1: 推奨アクションの記載

Step 2-4 で「なし」と判定された資産それぞれについて、推奨アクションは「何を整備するか・推進側が実施する」を顧客の言葉で記載する（例: 「コーディング規約とレビューの仕組みの整備（推進側が実施）」）。内部スキル名は書かない。対応の割り当て（rules・hooks 不在 → consult-repo-rules、lint 未導入 → consult-lint-setup）はコンサル側の判断情報として本節にのみ保持し、Edit でレポートの `{{recommendations}}` には顧客向け表現のみを記載する。

**入力**: Step 2-4 の網羅性判定
**完了**: 「なし」判定資産ごとに対応スキルが推奨アクションとして記載されている

### Step 4-2: Step 粒度未達の指摘

Step 2-2 で Step 見出しを持たない SKILL.md があれば、Edit でレポートの `{{findings}}` に指摘として追記する。

**入力**: Step 2-2 のスキルごとの Step 有無判定
**完了**: Step 粒度未達のスキルがあれば指摘が追記されている、なければ「該当なし」と記載されている

完了条件: 網羅性判定に基づく推奨アクションと、Step 粒度未達の指摘（該当なしの場合はその旨）がレポートに記載されている

## 重要ルール

- コンサル環境の rules/skills/hooks の実物を顧客プロジェクトへコピーしない。診断は Read 専用の走査であり、`references/` の雛形はレポート HTML のみに使う
- 推測で「あり/なし」を判定しない。Glob/Read/Bash で実際に検出できたものだけを「あり」とする
- レポートは診断結果の記述に留め、規約整備・lint 導入そのものは consult-repo-rules / consult-lint-setup に委ねる
- レポート HTML に consult- で始まる名称・環境固有のパスを含めない（`.claude/skills/shared/references/customer-output-checklist.md` の自問チェックに従う）。出力前に `grep -c "consult-" clients/<案件名>/設定診断_<YYYYMMDD>.html` が 0 であることを確認する

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | CLAUDE.md・rule.md 一覧・SKILL.md 一覧・hooks 構成・permissions 構成が把握されている |
| Phase 2 | ルールごとの機械強制有無・スキルごとの Step 粒度・hook 構文検査結果・4 項目の網羅性判定が揃っている |
| Phase 3 | 検出結果・計測値を埋め込んだレポート HTML が `clients/<案件名>/設定診断_<YYYYMMDD>.html` に出力されている |
| Phase 4 | 網羅性判定に基づく推奨アクションと、Step 粒度未達の指摘（該当なしの場合はその旨）がレポートに記載されている |
| **Goal** | 顧客プロジェクトの設定資産の有無・品質指標・推奨アクションが1枚のレポート HTML にまとまっている |

## Gotchas

- `settings.json` が `.claude/settings.json` と `.claude/settings.local.json` に分かれている場合、両方を Read しないと hooks・permissions を見落とす
- hook の command パスは相対パス表記のことが多く、`bash -n` 実行時は `<repo>` を起点に解決する必要がある
- `.claude/rules/` の配置パターンは `<topic>-rules/rule.md` 型と `<scope>/<topic>/<name>/rule.md` 型が混在しうる。Glob は `**/rule.md` で両方を拾う

## 完了報告

- `.claude/skills/shared/references/completion-report-format.md` の作業報告型骨格に従う
- 固有の検証行として、検出資産件数（rules N本・skills N本・hooks N件）・網羅性4項目の判定結果・出力レポートのパスを追加する
