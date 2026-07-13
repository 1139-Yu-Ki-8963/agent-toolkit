---
name: consult-lint-setup
description: 文章品質の機械強制一式を顧客環境へ導入し実機検証まで行う。 TRIGGER when: 「文章品質を導入」「textlint導入」「lint環境を構築」「文体の機械強制を入れて」と言われた時。 SKIP: 導入済み環境への語彙追加のみの場合（prh.yml へ直接追記）、解決事例の閲覧のみの場合。
invocation: consult-lint-setup
type: orchestration
allowed-tools: Read, Write, Edit, Bash, Glob, AskUserQuestion
---

# 文章品質の導入（consult-lint-setup）

解決事例「prd長文-学術調」の解決策を顧客環境で再現する実行スキル。読み物の手順書ではなく、解析から検証までを本スキルが実行する。

## Phase 1: プロジェクト解析

対象リポジトリ（以下 `<repo>`）で次を調査する。

- 文書の配置: `*.md` の分布と主要ディレクトリ
- Node.js の利用可否: `node -v`
- 既存の lint 設定: `.textlintrc*` の有無。既存があれば上書きせず統合方針を検討する
- `.claude/settings.json` の有無と既存 hooks 構成

### Step 1-1: 文書分布の調査

Glob (`**/*.md`) で `<repo>` 全体を走査し、Markdown 文書の分布と主要ディレクトリを把握する。

**入力**: `<repo>` のルートパス
**完了**: 主要な文書ディレクトリと `*.md` の分布件数を把握している

### Step 1-2: Node.js の利用可否確認

Bash で `node -v` を実行し、Node.js のインストール有無とバージョンを確認する。

**入力**: なし
**完了**: Node.js の利用可否とバージョンが判明している

### Step 1-3: 既存lint設定の確認

Glob (`**/.textlintrc*`) で既存の lint 設定ファイルを検索する。存在する場合は Read で内容を確認し、上書きせず統合する方針を検討する。

**入力**: `<repo>` のルートパス
**完了**: 既存lint設定の有無と、ある場合の統合方針が定まっている

### Step 1-4: settings.json の確認

`<repo>/.claude/settings.json` を Read で確認し、既存の hooks 構成の有無を把握する。

**入力**: `<repo>/.claude/settings.json`
**完了**: settings.json の有無と既存hooks構成が把握できている

完了条件: 文書分布・Node利用可否・既存lint設定・既存hooks構成が把握されている

## Phase 2: 導入計画の承認

配置先一覧（検査設定・辞書・文体規約・hook スクリプト・settings.json への登録内容）を表で提示し、AskUserQuestion で承認を得てから変更に着手する。

### Step 2-1: 配置計画の表作成

検査設定・辞書・文体規約・hookスクリプト・settings.json への登録内容の配置先一覧を表形式で作成する。

**入力**: Phase 1 で把握した文書分布・既存lint設定・既存hooks構成
**完了**: 配置先一覧の表が作成されている

### Step 2-2: 承認

AskUserQuestion で配置先一覧の表を提示し、導入への承認を得る。

**入力**: Step 2-1 で作成した配置先一覧の表
**完了**: 顧客から導入の承認を得ている

完了条件: 配置先一覧を提示し、AskUserQuestion で承認を得ている

## Phase 3: 検査エンジンの導入

1. `<repo>/tools/linter/` を作成する
2. `references/textlintrc-template.json` を `<repo>/tools/linter/.textlintrc.json` として配置する
3. `references/prh-template.yml` を `<repo>/tools/linter/prh.yml` として配置する
4. `.textlintrc.json` 内の `{{PRH_PATH}}` を実配置パス（`tools/linter/prh.yml` の相対パス等）に置換する
5. `package.json` を作成し、次を install する: `textlint` `textlint-rule-preset-ja-technical-writing` `textlint-rule-prh` `textlint-filter-rule-allowlist` `textlint-filter-rule-comments`

### Step 3-1: linter ディレクトリ作成

Bash で `<repo>/tools/linter/` を作成する（`mkdir -p`）。

**入力**: `<repo>` のルートパス
**完了**: `<repo>/tools/linter/` が存在する

### Step 3-2: 検査設定テンプレート配置

Write で `references/textlintrc-template.json` の内容を `<repo>/tools/linter/.textlintrc.json` として配置する。

**入力**: `references/textlintrc-template.json`
**完了**: `<repo>/tools/linter/.textlintrc.json` が配置されている

### Step 3-3: 辞書テンプレート配置

Write で `references/prh-template.yml` の内容を `<repo>/tools/linter/prh.yml` として配置する。

**入力**: `references/prh-template.yml`
**完了**: `<repo>/tools/linter/prh.yml` が配置されている

### Step 3-4: PRH_PATH の置換

Edit で `.textlintrc.json` 内の `{{PRH_PATH}}` を実配置パス（`tools/linter/prh.yml` の相対パス等）に置換する。

**入力**: `<repo>/tools/linter/.textlintrc.json`
**完了**: `{{PRH_PATH}}` プレースホルダが実パスに置換されている

### Step 3-5: package.json 作成とinstall

Bash で `package.json` を作成し、`textlint` `textlint-rule-preset-ja-technical-writing` `textlint-rule-prh` `textlint-filter-rule-allowlist` `textlint-filter-rule-comments` を install する。

**入力**: なし
**完了**: `package.json` が作成され、対象パッケージの install が完了している

完了条件: `.textlintrc.json`・`prh.yml`・`package.json` が配置され install が完了している

## Phase 4: 文体規約の配置

`references/writing-rule-template.md` を `<repo>/.claude/rules/writing-quality-rules/rule.md` として配置する。`.claude/rules/` の運用がないプロジェクトでは CLAUDE.md への統合を提案する。

### Step 4-1: 文体規約テンプレートの読み込み

Read で `references/writing-rule-template.md` を読み込む。

**入力**: `references/writing-rule-template.md`
**完了**: テンプレート内容を把握している

### Step 4-2: 文体規約の配置

Write で読み込んだテンプレートを `<repo>/.claude/rules/writing-quality-rules/rule.md` として配置する。`.claude/rules/` の運用がないプロジェクトでは CLAUDE.md への統合を提案する。

**入力**: Step 4-1 で読み込んだテンプレート内容
**完了**: 文体規約 rule.md が配置されている、または CLAUDE.md への統合提案が済んでいる

完了条件: 文体規約 rule.md が配置されている、または CLAUDE.md への統合提案が済んでいる

## Phase 5: hook の設置

1. `references/textlint-hook-template.sh` を `<repo>/.claude/hooks/check-textlint-commit.sh` へ配置し、実行権限を付与する
2. スクリプト冒頭の設定変数（検査設定パス・検査対象パターン）を実配置に合わせて書き換える
3. `<repo>/.claude/settings.json` の PreToolUse(Bash) にこの hook を登録する。既存の hooks 配列があれば追記マージし、settings.json 全体を上書きしない

### Step 5-1: hookテンプレートの読み込みと配置

Read で `references/textlint-hook-template.sh` を読み込み、Write で `<repo>/.claude/hooks/check-textlint-commit.sh` として配置する。

**入力**: `references/textlint-hook-template.sh`
**完了**: `<repo>/.claude/hooks/check-textlint-commit.sh` が配置されている

### Step 5-2: 設定変数の書き換え

Edit でスクリプト冒頭の設定変数（検査設定パス・検査対象パターン）を実配置に合わせて書き換える。

**入力**: `<repo>/.claude/hooks/check-textlint-commit.sh`
**完了**: 設定変数が実配置のパス・パターンに書き換えられている

### Step 5-3: 実行権限付与

Bash で `chmod +x <repo>/.claude/hooks/check-textlint-commit.sh` を実行する。

**入力**: `<repo>/.claude/hooks/check-textlint-commit.sh`
**完了**: スクリプトに実行権限が付与されている

### Step 5-4: settings.json への hook 登録

Edit で `<repo>/.claude/settings.json` の PreToolUse(Bash) にこの hook を登録する。既存の hooks 配列があれば追記マージし、settings.json 全体を上書きしない。

**入力**: `<repo>/.claude/settings.json`
**完了**: settings.json に hook が登録されている

完了条件: hook スクリプトが配置され実行権限が付与され、settings.json に登録されている

## Phase 6: 実機検証

1. 違反語（例: ベストプラクティス）を含む一時 md に textlint を直接実行し、検出を確認する
2. 同ファイルを staged にして `git commit` を試み、hook が停止させることを確認する
3. 一時ファイル・staged 内容・検証用に作ったコミット候補を後片付けする
4. 結果を PASS/FAIL 表で報告する。textlint 単体の確認だけで終わらせない

### Step 6-1: 違反サンプル作成

Write で違反語（例: ベストプラクティス）を含む一時 md ファイルを作成する。

**入力**: なし
**完了**: 違反語を含む一時mdファイルが作成されている

### Step 6-2: textlint単体実行

Bash で作成した一時ファイルに textlint を直接実行し、検出を確認する。

**入力**: Step 6-1 で作成した一時mdファイル
**完了**: textlintが違反を検出することを確認している

### Step 6-3: 違反コミット試行

Bash で当該ファイルを staged にして `git commit` を試み、hook が停止させることを確認する。

**入力**: Step 6-1 で作成した一時mdファイル
**完了**: hookがコミットを実際に停止することを確認している

### Step 6-4: 後片付け

Bash で一時ファイル・staged内容・検証用に作ったコミット候補を削除・リセットする。

**入力**: Step 6-1〜6-3 で作成した検証用ファイル・staged内容
**完了**: 検証用の一時ファイル・staged内容が後片付けされている

### Step 6-5: 結果報告

textlint単体の確認とhookによる停止確認の両方をPASS/FAIL表で報告する。

**入力**: Step 6-2・Step 6-3の確認結果
**完了**: PASS/FAIL表で結果を報告している

完了条件: 違反コミットが実際に停止することを確認し、後片付けを終え、PASS/FAIL 表で報告している

## Phase 7: 顧客語彙の初期登録

導入直後に、ヒアリング済みの顧客固有語彙（社名の表記ゆれ・製品名・禁止語）があれば `prh.yml` へ追記する。無ければ「運用の中で追加する」ことを案内して終了する。

### Step 7-1: 顧客語彙の有無確認

AskUserQuestion でヒアリング済みの顧客固有語彙（社名の表記ゆれ・製品名・禁止語）の有無を確認する。

**入力**: ヒアリング内容
**完了**: 顧客固有語彙の有無が確認されている

### Step 7-2: 語彙追記

語彙がある場合、Edit で `prh.yml` へ追記する。無ければ「運用の中で追加する」ことを案内して終了する。

**入力**: Step 7-1 で確認した顧客固有語彙
**完了**: 顧客固有語彙を `prh.yml` へ追記した、または追加不要の案内を済ませている

完了条件: 顧客固有語彙を `prh.yml` へ追記した、または追加不要の案内を済ませている

## 重要ルール

- コンサル環境の辞書・設定の実物を顧客環境にコピーしない。`references/` の雛形のみを使い、雛形には一般語彙しか含めない
- 既存の `settings.json`・lint 設定は上書きせずマージする
- 検証は「違反コミットが実際に止まる」ことの確認まで必須とする
- 導入したファイルはすべて顧客リポジトリの資産であり、顧客語彙の辞書は顧客のものである

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 文書分布・Node利用可否・既存lint設定・既存hooks構成が把握されている |
| Phase 2 | 配置先一覧を提示し、AskUserQuestion で承認を得ている |
| Phase 3 | `.textlintrc.json`・`prh.yml`・`package.json` が配置され install が完了している |
| Phase 4 | 文体規約 rule.md が配置されている、または CLAUDE.md への統合提案が済んでいる |
| Phase 5 | hook スクリプトが配置され実行権限が付与され、settings.json に登録されている |
| Phase 6 | 違反コミットが実際に停止することを確認し、PASS/FAIL 表で報告している |
| Phase 7 | 顧客固有語彙を `prh.yml` へ追記した、または追加不要の案内を済ませている |
| **Goal** | 顧客環境で違反コミットが実際に停止することを実機確認し、後片付け済みで報告している |

## 予想を裏切る挙動

- hook 雛形は jq / git / textlint が欠如している環境では fail-open で素通りする。導入検証を省くとこの欠落に気づけない
- OS によってはシステム Python が外部管理で pip を直接導入できない。仮想環境や別ランタイム経由の導入を検討する

## 完了報告

- `.claude/skills/shared/references/completion-report-format.md` の作業報告型骨格に従う
- 固有の検証行として、配置ファイル一覧・実機検証の PASS/FAIL 表・辞書の初期語彙数を追加する

## 設計判断

**必要性**: `references/textlint-hook-template.sh`（顧客プロジェクトの `.claude/hooks/check-textlint-commit.sh` として Phase 5 で配置される雛形）は、git commit コマンドの検出・staged 差分からの追加行抽出・textlint 実行・行番号突合という複数分岐を持つロジックであり、Bash ツール直叩きでは毎回同じ 80 行超の処理を再現する必要がある。本スキルは複数の顧客プロジェクトへ同一ロジックを繰り返し導入することを目的としており、雛形として `.sh` に固定化しておくことでコピー配置のみで導入を完結させる。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 導入のたびに同じ長大ロジックを都度生成する必要があり、顧客環境に残る成果物（実行可能な hook スクリプト）にならない
- 既存 Makefile ターゲット拡張: 顧客プロジェクトの多くは Makefile を持たず、`.claude/hooks/` という Claude Code の hook 実行規約に載せる必要があるため Makefile 経由では成立しない
- package.json scripts 追加: PreToolUse hook として `settings.json` から直接呼び出す構成のため、npm scripts 経由では hook 登録の単純さが失われる

**保守責任者**: 人手（consult-lint-setup スキルの利用者・保守者）

**廃棄条件**: consult-lint-setup スキルが廃止された時、または textlint-hook-template のロジックが顧客側で標準的な textlint CLI 機能（staged 差分限定検査）として吸収され雛形が不要になった時
