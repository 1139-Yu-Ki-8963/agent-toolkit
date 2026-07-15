# scaffolding-flow-structure（内部参照モジュール）

> 本ファイルは `creating-new-project` スキルの内部参照モジュール。旧 `dev-flow-scaffolding-project` スキルの手順を統合した。単独の SKILL として起動されることはなく、`creating-new-project/SKILL.md` から Read される前提で書かれている。
>
> `creating-new-project/SKILL.md` の Phase 3（Claude Code 基盤）・Phase 5（プロジェクトポータル）・Phase 6（CI/CD・品質基盤）と重複する記述がある場合は、`SKILL.md` 本体の記述を正とする。本ファイルは主に以下の 2 点を補うために参照する:
>
> 1. `~/agent-home/skills/orchestrating-dev-flow/references/module-preflight-check.md` を使った生成後の前提条件検証手順（Phase 10 の構造検証を補完）
> 2. `project-portal/` の最小テンプレート一式（`scaffolding-assets/portal-template/`）をベースにした差分コピー手順

新プロジェクトに orchestrating-dev-flow が前提とするディレクトリ構造と設定ファイルを自動生成する手順。

## 前提

- プロジェクトルートで実行する
- git 管理されていること

## 基本ワークフロー

### Step 1: 既存構造の確認

`.claude/rules/always/project-context/flow-values.yml` が既に存在するか確認する。存在する場合はユーザーに「既存の設定を上書きしますか？」と AskUserQuestion で確認する。

### Step 2: プロジェクト構造のヒアリング

AskUserQuestion で以下を確認する:

1. 技術スタック（レイヤー構成）
   - frontend: フレームワーク・lint ツール・テストツール
   - backend: 言語・lint ツール・テストツール
   - 追加レイヤーの有無

2. PR テンプレートの要件
   - `.github/pull_request_template.md` が既にあるか
   - 必須セクション（概要・なぜこの実装か・影響範囲・確認方法・テスト）のカスタマイズ要否

ヒアリング結果の利用先:
- 技術スタック → Step 3（flow-values.yml / layers.yml の生成内容）
- PR テンプレート要件 → Step 4（テンプレートのカスタマイズ）

### Step 3: 基本ファイル生成

以下のディレクトリとファイルを生成する:

```
.claude/rules/always/project-context/     （実体ディレクトリ）
├── rule.md             ← プロジェクト概要・設定索引・ルート直下許可リスト節
├── flow-values.yml     ← ヒアリング結果を反映
└── layers.yml          ← 技術スタックを反映

docs/
├── 個別設計/
│   └── 画面/
└── 知識ベース/
    └── glossary.js     ← export default {}
```

`project-portal/` は `~/agent-home/skills/creating-new-project/references/scaffolding-assets/portal-template/` をまるごとコピーして生成する:

```bash
cp -r ~/agent-home/skills/creating-new-project/references/scaffolding-assets/portal-template/ ./project-portal/
```

コピー後にプロジェクト固有の値を書き換える:
- `index.html`: `brand-title`（プロジェクト名）・`topnav` リンク
- `release-notes.html`: `<title>` のプロジェクト名・`STORE_KEY` の localStorage キー名
- `mocks.html`: `<title>` のプロジェクト名

追加で必要なページを配置する:

```bash
cp ~/agent-home/skills/creating-new-project/references/scaffolding-assets/sample-review-findings.html ./project-portal/review-findings.html
cp ~/agent-home/skills/creating-new-project/references/scaffolding-assets/sample-flow-history.html ./project-portal/flow-history.html
```

### Step 4: PR テンプレート生成

`.github/pull_request_template.md` を生成する（既存がなければ）。

`.github/` ディレクトリが存在しなければ作成する。

テンプレート内容（ヒアリング結果でカスタマイズ）:

```markdown
## 概要

<!-- 変更の概要を 1〜3 文で -->

## なぜこの実装か

<!-- 設計判断の理由 -->

## 影響範囲

- [ ] frontend
- [ ] backend
- [ ] DB スキーマ
- [ ] API 契約
- [ ] 設定ファイル

## 確認方法

<!-- 動作確認の手順 -->

## テスト

- [ ] ユニットテスト追加 / 更新
- [ ] E2E テスト追加 / 更新
- [ ] 手動確認済み

### 未実施・残課題

なし
```

### Step 5: DESIGN.md 生成

**出力先**: プロジェクトルート直下 `DESIGN.md` 固定（`orchestrating-dev-flow` Phase 4 Step 4-1b が生成する画面別 DESIGN.md `<screen_docs.base_dir>/<画面名>/DESIGN.md` とは別物）。既にプロジェクトルートに `DESIGN.md` が存在する場合は上書きせず、「DESIGN.md は既に存在するためスキップしました」と報告してこの Step を終える。

対象プロジェクト内の既存スタイル資産を Glob/Grep で検出する（抽出パターン表・**優先順位順**）:

| 優先順位 | 資産 | 検出パターン | 抽出するもの |
|---|---|---|---|
| ① | Tailwind 設定 | `tailwind.config.{js,ts,cjs,mjs}` の `theme.extend.colors.primary` | primary色 |
| ② | CSS カスタムプロパティ | `:root` 内の `--color-primary` または `--primary` | primary色（この2種類の命名のみ検出対象。それ以外の命名ゆらぎは対象外） |
| ③ | Tailwind v4 `@theme` | `@theme` 内の `--color-primary` | primary色 |
| （種別問わず） | body フォント | `body { font-family: ...; }` または CSS変数 `--font-body` | body typography の font-family 値 |

複数箇所で primary色が見つかった場合は優先順位①→②→③の順で最初に見つかった値のみを採用し、マージしない。同一資産内に `--color-primary` と `--primary` の両方が存在する場合は `--color-primary`（より明示的な命名）を優先する。「既存CSSがある」の判定は、上記パターンのいずれか1件でも実際にマッチした場合のみを指す（ファイルが存在するだけで中身が未マッチなら「検出できない場合」の扱いとする）。

検出できた場合:
1. primary色・body typography（font-family）の**2値のみ**を最小限のトークンとして抽出する（secondary・spacing・shadow等は対象外）
2. 以下のスキーマで DESIGN.md を生成する（`components` は `validate-design-md.sh` の必須フィールドのため省略不可。ダミーで良いので必ず含める）:

```yaml
---
colors:
  primary: "#<検出した16進数値>"
typography:
  body:
    fontFamily: "<検出したfont-family値>"
components:
  button:
    backgroundColor: "{colors.primary}"
---

## Overview
<プロジェクト名>のデザイントークン仕様書（最小構成）。

## Colors
- primary: 主要アクションに使用する基調色。

## Typography
- body: 本文用フォント。

## Components
- button: primary色を使う代表コンポーネント。
```

検出できない場合、以下の最小テンプレートをそのまま生成する:

```yaml
---
colors:
  primary: "#000000"
typography:
  body:
    fontFamily: "sans-serif"
components:
  button:
    backgroundColor: "{colors.primary}"
---

## Overview
（未確定）デザインが固まったら本ファイルを手動で拡充してください。

## Colors
- primary: 仮の値。確定後に更新すること。

## Typography
- body: 仮の値。確定後に更新すること。

## Components
- button: 仮のダミーコンポーネント。確定後に見直すこと。
```
その場合は「デザインが固まったら DESIGN.md を手動で拡充してください」とユーザーに案内する。

いずれの場合も:
3. 生成後に `~/agent-home/tools/design/validate-design-md.sh` で構造検証する（スクリプトが存在する場合。`colors`/`typography`/`components`/`primary` 欠落は FAIL 扱いなので上記テンプレートには全て含めてある。FAIL が出た場合は指摘に従い修正）
4. 生成した DESIGN.md の**プロジェクトルートからの相対パス**（`DESIGN.md`）が flow-values.yml の `design_system` フィールドと一致することを確認する。不一致の場合は flow-values.yml を更新する

**完了**: DESIGN.md が `validate-design-md.sh` を PASS していること（スクリプトが無い環境ではスキップ）

### Step 6: .gitignore 更新

`.gitignore` に以下を追加（未記載の場合）:

```
.flow-progress.json
.claude/markers/
```

### Step 7: プリフライトチェック実行

Step 3〜6 が全て完了していることを確認する。途中で失敗した場合は Step 7 に進まず、失敗した Step とエラー内容をユーザーに報告する。

全ファイル生成完了後に `~/agent-home/skills/orchestrating-dev-flow/references/module-preflight-check.md` を Read し、その手順に従って前提条件を検証する。

- go → Step 8 に進む
- no-go → FAIL 項目の修正方法を案内する

### Step 8: 完了報告

生成したファイル一覧をユーザーに提示する:

```
## scaffold 完了

### 生成ファイル
- .claude/rules/always/project-context/rule.md（ルート直下許可リスト節を含む）
- .claude/rules/always/project-context/flow-values.yml
- .claude/rules/always/project-context/layers.yml
- docs/知識ベース/glossary.js
- docs/個別設計/画面/ (ディレクトリ)
- project-portal/ (6 ファイル)
- .github/pull_request_template.md
- DESIGN.md (生成した場合)

### プリフライトチェック結果
全 N 項目 PASS

### カスタマイズ案内
- flow-values.yml の pr.critical_globs を実プロジェクトに合わせて調整してください
- layers.yml のコマンドが実環境で動作するか確認してください
```

プリフライトが no-go を返した場合:

```
## scaffold 完了（プリフライト未通過）

### 生成ファイル
（上記と同じ）

### プリフライトチェック結果
FAIL: N 項目
- <FAIL 項目と修正方法の一覧>

### 対応手順
上記の FAIL 項目を修正し、`~/agent-home/skills/orchestrating-dev-flow/references/module-preflight-check.md` の手順を再実行する。
```

## 予想を裏切る挙動

- 既存の `project-portal/` がある場合は上書きしない。差分だけ追加する
- layers.yml のコマンドはヒアリング結果から推測するが、実際に動くかはユーザーが確認する必要がある
- DESIGN.md の自動生成は既存のスタイル資産がある場合のみ。何もない状態では最小テンプレートを生成する
