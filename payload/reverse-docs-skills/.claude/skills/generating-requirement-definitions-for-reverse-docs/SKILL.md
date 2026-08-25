---
name: generating-requirement-definitions-for-reverse-docs
日本語名: 要件定義文書のとりまとめ
description: "対象のコードは読まず、作成済みの一覧の元データと個別の基本設計書から確かめられる事実だけで、要件定義の5つの文書を作る。"
invocation: generating-requirement-definitions-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write]
---

## いつ使うか

段階計画の途中で、機能要件一覧・帳票要件・バッチ要件・外部連携要件・ビジネス概要のいずれかを記録したいとき。

## いつ使わないか

個別の単位ごとの基本設計書・詳細設計書を作るとき、一覧の元データそのものを作るとき。

# 正本: reverse-docs-skills

# 要件定義5文書の生成スキル

工程全体は orchestrating-ai-development-setup が案内する。本スキルは統括フローへは結線されておらず、単独起動でのみ動く。起動引数を渡せば動く。対象コードは一切読まない。既に生成済みの一覧マニフェストと個別基本設計書、つまり他スキルの成果物だけを情報源とする。

## 情報源と対象外

情報源は次の2つに限る。

1. 一覧マニフェスト（`<kind>-manifest.ext.json` または `<kind>-manifest.json`。無ければ該当なし記録 `<label>一覧（該当なし）.md`）
2. 個別基本設計書（帳票要件・バッチ要件・外部連携要件のみ対象。各ユニットの基本設計書が持つ、テンプレートが名指しする特定の章）

対象コード・原本ファイルパス・関数名・変数名は読まない。各文書が満たすべき要件の業務上の目的・想定利用者・利用頻度は業務の意図である。業務の意図はこの2つの情報源のどちらにも現れない。そのため常に 要確認事項一覧へ回す。埋まらない欄を推測で埋めない。一般的な内容で補うことも行わない。

## 起動引数

| 引数 | 必須 | 内容 |
|---|---|---|
| `output_dir` | 必須 | 納品物ルートの絶対パス。一覧マニフェスト（`<output_dir>/<manifestsRoot>/`）・個別基本設計書（種別ごとの `<output_dir>/<kindUnitRoot>/`。例: `reportUnitRoot`）・出力先（`<output_dir>/<commonRoot>/`）は、それぞれ `delivery-payload/references/output-layout.json` の物理配置キーから解決する。既存の一覧生成スキル群・個別設計書生成スキル群と同じ `output_dir` を渡す |
| `template_root` | 必須 | テンプレ一式のルート。`<template_root>/リバース検証/プロジェクト共通/` の要件定義5文書を雛形に使う |
| `target_docs` | 任意（既定は5件すべて） | 生成対象を doc_id で絞り込む配列。`functional-requirements`（機能要件一覧）／`report-requirements`（帳票要件）／`batch-requirements`（バッチ要件）／`external-requirements`（外部連携要件）／`business-overview`（ビジネス概要）から選ぶ |

本スキルはユーザーに直接確認しない（AskUserQuestion不使用）。単独起動時は上表の args をユーザーから直接取得する。

## 配置の解決方針

一覧・個別設計書・出力先の物理配置は、`delivery-payload/references/output-layout.json` の宣言から解決する。この宣言は、既存の一覧生成スキル群と個別設計書生成スキル群の両方に反映済みである。一覧マニフェストは `manifestsRoot`（既定値 `docs/manifests`）配下の `<kind>-manifest(.ext).json` に永続化される。個別設計書は種別ごとの `<kindUnitRoot>` 配下に配置される。既定値は `reportUnitRoot`＝`docs/design/reports`である。`batchUnitRoot`＝`docs/design/batches`、`externalUnitRoot`＝`docs/design/externals`も同様である。本スキルの出力先は `commonRoot`（既定値 `docs/design/common`）配下である。パスを直書きせず、これらのキーから解決する。

種別ラベルの文字列は直書きせず、宣言から解決する。帳票・バッチ・外部連携の3種別は、個別設計書のファイル名も宣言に持つ。ファイル名は `design-unit-layout.json` の `kinds.<kind>.phases.basic[0]` から解決する。機能を含む7種別（画面・API・テーブル・バッチ・帳票・外部連携・機能）の表示用ラベルは `output-layout.json` の `kindLabels` から解決する。表示用ラベルは path には使わない。

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` で Phase 1〜4 のタスクを登録する。各 Phase 開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 4 から Phase 3 へ差し戻す場合は該当タスクを `in_progress` に戻す。実行環境に TaskCreate/TaskUpdate が存在しない場合は、出力先ディレクトリ内のタスク台帳ファイル（`task-ledger.md`）で同等の Phase 遷移記録を代替する。

## Phase 1: 起動引数の確認と対象文書の確定

## Step 1-1: 起動引数の確認と対象文書の確定

**使用ツール**: Bash / Read

- Step 1: `output_dir`・`template_root` の実在を確認する（`test -d`）。いずれかが欠ける場合は `status=ERROR` で停止する。完了条件: 2 引数が実在する
- Step 2: `<template_root>/リバース検証/プロジェクト共通/` 配下に、要件定義5文書のテンプレートが実在することを `test -f` で確認する。対象は `機能要件一覧.md`・`帳票要件.md`・`バッチ要件.md`・`外部連携要件.md`・`ビジネス概要.md` である。完了条件: 5 テンプレートの実在を確認済み
- Step 3: `target_docs` が渡されていれば、値が起動引数表に記載した5つの doc_id の部分集合であることを確認する。未指定なら5件すべてを対象とする。完了条件: 対象文書の doc_id 集合が確定している

**完了**: 2 引数が実在し、対象 doc_id に対応するテンプレートの実在を確認済みで、対象文書の集合が確定している

## Phase 2: 入力の特定

## Step 2-1: 一覧マニフェストの入力判定（機能・帳票・バッチ・外部連携要件）

**使用ツール**: Bash / Read

対象文書に機能・帳票・バッチ・外部連携要件のいずれかが含まれていれば、該当する種別（feature/report/batch/external）ごとに次を行う。

- Step 1: 種別のラベルを解決する。feature は `output-layout.json` の `kindLabels.feature` から解決する。report/batch/external は `design-unit-layout.json` の `kinds.<kind>.label` から解決する。完了条件: 対象種別のラベルが確定している
- Step 2: `<output_dir>/<manifestsRoot>/<kind>-manifest.ext.json` を確認する。無ければ `<kind>-manifest.json` を確認する。いずれかが実在すれば「マニフェスト有」と判定する。`manifestsRoot` は output-layout の物理配置キー（既定値 `docs/manifests`）。無ければ `<output_dir>/<unitListAbsentMd>` の実在を確認し、実在すれば「該当なし（0件）」と判定する。`unitListAbsentMd` は output-layout の物理配置キーである。`{label}` に対象種別のラベルを代入する（既定値 `docs/manifests/{label}一覧（該当なし）.md`）。それも無ければ「入力なし（対象外）」と判定する。完了条件: 対象種別の入力状態（マニフェスト有／該当なし／入力なし）が確定している
- Step 3: 「入力なし」と判定した文書は、以降の Phase をスキップする対象として記録する。存在しない前提で書かない。実在しない入力から捏造しない。完了条件: スキップ対象の記録が確定している

**完了**: 選択された機能・帳票・バッチ・外部連携要件それぞれについて入力状態が確定し、入力なしの文書はスキップ対象として記録済みである

## Step 2-2: 個別基本設計書の入力判定（帳票・バッチ・外部連携要件）

**使用ツール**: Bash / Read

対象文書に帳票・バッチ・外部連携要件のいずれかが含まれ、Step 2-1で「マニフェスト有」と判定されていれば、次を行う。対象は当該マニフェストが持つユニットごとである。

- Step 1: `design-unit-layout.json` の `kinds.<kind>.phases.basic[0]` をファイル名とする。値は `帳票基本設計書.md`／`バッチ基本設計書.md`／`外部連携基本設計書.md` のいずれかである。`<output_dir>/<kindUnitRoot>/<kind>-<識別子>/<unitPhaseDirNames.basic>/<ファイル名>` の実在を `test -f` で確認する。`<kindUnitRoot>` は種別ごとに `reportUnitRoot`・`batchUnitRoot`・`externalUnitRoot` のいずれかである。いずれも output-layout の物理配置キーである。既定値はそれぞれ `docs/design/reports`・`docs/design/batches`・`docs/design/externals` である。`unitPhaseDirNames.basic` は output-layout の `unitPhaseDirNames.basic` の値（既定値 `basic-design`）であり、scaffold-design-unit.sh が実際に展開する配置フォルダ名と一致させる（1-210）。`<識別子>` はマニフェストの `unitId`、無ければ `unitKey` を使う。完了条件: 対象種別の全ユニットについて個別基本設計書の有無を確認済み
- Step 2: 実在するユニットについて、テンプレートが名指しする章を Read し、記入材料として保持する。帳票は §1.2 出力の条件と契機・§1.3 レイアウトの要件である。バッチは §1.1 起動の契機と実行の周期・§1.3 異常時の復旧の方針である。外部連携は §1.1 連携先と方式・§1.3 正常応答と異常応答・§1.4 タイムアウトとリトライと冪等性である。完了条件: 実在ユニット全件の該当章を読了済み

**完了**: 対象種別の全ユニットについて個別基本設計書の有無が確定し、実在分は該当章の記入材料を保持している

## Step 2-3: 件数入力判定（ビジネス概要）

**使用ツール**: Bash / Read

対象文書に `business-overview` が含まれていれば、7種別それぞれについて次を行う。7種別は機能・画面・API・テーブル・バッチ・帳票・外部連携である。

- Step 1: `output-layout.json` の `kindLabels` から種別のラベルを解決する。完了条件: 7種別のラベルが確定している
- Step 2: `<output_dir>/<manifestsRoot>/<kind>-manifest.json` を確認する。無ければ `.ext.json` を確認する。実在すれば件数取得キーで要素数を数える。件数取得キーは種別により異なる。`screen`（画面）は最上位キーが `screens` であり、`.screens` の要素数を件数とする。他の6種別（機能・API・テーブル・バッチ・帳票・外部連携）は最上位キーが `units` であり、`.units` の要素数を件数とする（実データで確認済み: `screen-manifest.json` は最上位キーに `screens` を持ち `units` を持たない。他6種別のマニフェストは最上位キーに `units` を持つ）。マニフェストが実在しなければ `<output_dir>/<unitListAbsentMd>` の実在を確認する。`unitListAbsentMd` は output-layout の物理配置キーである。`{label}` に対象種別のラベルを代入する（既定値 `docs/manifests/{label}一覧（該当なし）.md`）。実在すれば件数を0とする。どちらも無ければ「対象外（入力なし）」と記録する。完了条件: 7種別それぞれについて件数または「対象外（入力なし）」が確定している

**完了**: 7種別すべてについて件数または「対象外（入力なし）」が確定している

## Phase 3: 執筆

## Step 3-1: テンプレートの配置

**使用ツール**: Bash / Read / Write

Phase 2 で「入力なし」と判定されなかった対象文書について、`<template_root>/リバース検証/プロジェクト共通/<ファイル名>` を Read する。読み込んだ内容を `<output_dir>/<commonRoot>/<ファイル名>` へ Write する。中間ディレクトリが無ければ作成する。`commonRoot` は output-layout の物理配置キー（既定値 `docs/design/common`）。表示用ラベルは path には使わない。

**完了**: 「入力なし」以外の対象文書すべてが出力先へ配置済みである

## Step 3-2: §2観測事実の記入

**使用ツール**: Bash / Read / Write

- Step 1（機能要件一覧）: マニフェストの各ユニットについて §2 の行を記入する。`unitKey` をキーへ、`unitNameGuess` を機能名へ、`category` を大分類へ記す。`relatedScreens`・`relatedApis`・`relatedTables` の要素数の合計を構成要素数へ記す。`unitId`（無ければ `unitKey`）を個別設計書へ記す。完了条件: 全ユニットの行が記入済み
- Step 2（帳票・バッチ・外部連携要件）: マニフェストの各ユニットについて記入する。`unitKey` をキーへ、`unitNameGuess` を名称へ記す。`unitId`（無ければ `unitKey`）を個別設計書へ記す。Step 2-2 で個別基本設計書が実在したユニットは、保持した該当章の記述から観測できる事実だけを該当列へ転記する。該当列は帳票なら出力の条件・契機・様式の要件である。バッチなら起動の契機・実行の周期・復旧の方針である。外部連携なら連携先・連携の契機・異常時の取り扱いである。個別基本設計書が未生成のユニットは、それらの列を空欄のまま残す。完了条件: 全ユニットの行が記入済みである。未生成ユニットの列は空欄のまま識別できる
- Step 3（ビジネス概要）: §2 の値列へ、Phase 2 Step 2-3 で確定した件数、または「対象外（入力なし）」を記入する。参照先列はテンプレートの記載を変更しない。完了条件: 7種別すべての値列が記入済み
- Step 4: 原本（マニフェスト・個別基本設計書）に無い値を書かない。推測で埋めない。完了条件: 全記入値が原本の記載に対応している

**完了**: 対象文書の §2 が、観測できた範囲で記入済みである（個別基本設計書が未生成の列は空欄のまま残る）

## Step 3-3: 要確認事項一覧の記入

**使用ツール**: Read / Write

- Step 1（機能・帳票・バッチ・外部連携要件）: 各ユニットにつき、業務の意図を必ず1行、意味語キーで §3 へ記入する。業務の意図はそのテンプレートが名指しする項目である。機能要件一覧は満たすべき要件、帳票要件は利用者・利用目的・配布先の意味、バッチ要件は業務上の目的、外部連携要件は業務上の目的と求められる頻度である。完了条件: 対象文書ごとに §3 の行数がユニット数以上になっている
- Step 2: Step 3-2 で空欄のまま残した観測列があれば、列ごとに1行を追加する。導出できなかった理由へ「個別基本設計書が未生成」と具体的に記す。完了条件: 空欄となった観測列すべてに対応する行が追加済み
- Step 3（ビジネス概要）: テンプレートが持つ3つの必須確認事項行を削除せず残す。3行は事業概要・システム役割・対象利用者である。Phase 2 Step 2-3 で「対象外（入力なし）」と判定した種別があれば、その種別も意味語キーで §3 へ追加する。完了条件: 必須3行が残存し、対象外種別があれば追加済み
- Step 4: 対象コードの位置は記録しない。完了条件: 全キーが意味語で一意である

**完了**: 対象文書ごとに 要確認事項一覧が記入済みである。行数はユニット数以上（機能・帳票・バッチ・外部連携要件）、または必須3行＋対象外種別（ビジネス概要）である

## Step 3-4: frontmatterのstatus確定

**使用ツール**: Read / Write

- Step 1: 対象文書の §2 に、個別基本設計書の未生成に起因する空欄が1件でも残っている場合、frontmatterの `status` を `draft` のまま維持する。完了条件: 空欄が残る文書はすべて `draft` のままである
- Step 2: 空欄が1件も残っていない対象文書は `status` を `draft` から `traced` へ更新する。対象はマニフェストと個別基本設計書がすべて実在し、§2 に空欄が無く、業務の意図がすべて §3 へ移されている文書である。完了条件: 条件を満たす文書はすべて `traced` になっている

**完了**: 対象文書ごとに `status` が `draft` または `traced` のいずれかに確定している

## Phase 4: 機械検査

## Step 4-1: 機械検査

**使用ツール**: Bash / Read

次の6つを実行する。1つでも不合格なら Phase 3 へ戻る。上限3回で収束しなければ `status=ERROR` とする。

- 検査1 業務語彙の検査: 生成した本文に実装用語・内部成果物名が含まれないことを grep で確認する。検出対象は型構文・フレームワーク用語・原本の拡張子・内部識別子である。内部識別子は `unitId`・`unitKey`・`detectionMethod`・`sourceFile`・`unitNameGuess`・`manifest.ext.json` である。検出 0 件で合格

  ```bash
  grep -nE 'interface [A-Z]|: *(string|number|boolean)\b|\.(py|pl|pm|cgi|rb|go|java|tsx|jsx)\b|unitId|unitKey|detectionMethod|sourceFile|unitNameGuess|manifest\.ext\.json' <対象文書.md>
  ```

- 検査2 注記の残存検査: テンプレートの記入規則を書いた HTML コメント（`<!-- -->`）が残っていないことを確認する。残存 0 件で合格
- 検査3 frontmatterの検査: `status` が `draft` または `traced` のいずれかであり、Step 3-4 の判定結果と一致していることを確認する
- 検査4 章の完備検査: テンプレートが持つ全ての章見出し（§1〜§3）が出力に存在することを確認する
- 検査5 §3行数の検査: 機能・帳票・バッチ・外部連携要件は §3 の行数が対象ユニット数以上であることを確認する。ビジネス概要は3つの必須キー（事業概要・システム役割・対象利用者）が残存することを確認する
- 検査6 配置の検査: 対象文書が `<output_dir>/<commonRoot>/<ファイル名>` に実在することを確認する

**完了**: 6 検査すべてが合格している

## サブエージェント委任仕様

本スキルは子スキルを起動しない。マニフェスト・個別基本設計書の読解と執筆（Phase 2〜3）は、業務語彙の一貫性を保つため単一のメインエージェントが通しで担う。

## ループ設計

Phase 4（機械検査）で不合格が検出された場合、該当する対象文書のみ Phase 3 で書き直して Phase 4 を再実行する。

| 要素 | 内容 |
|---|---|
| 反復条件 | 6 検査のいずれかが1件でも不合格なら、該当箇所を書き直して Phase 4 を再実行する |
| 上限回数 | 3回 |
| 停止条件 | 収束停止: 6 検査すべて合格 ／ リソース上限: 3回到達（未収束の場合は `status=ERROR` として呼び出し元へ差し戻す） |

## 停止条件

| status | 意味 |
|---|---|
| `DONE` | 「入力なし」以外の対象文書すべてが観測できた範囲で記入済みで、Phase 4 の 6 検査すべてに合格した |
| `NONE` | 対象文書のすべてが「入力なし」と判定され、生成できる文書が1件も無かった |
| `ERROR` | 必須引数の欠落・テンプレート不在・Phase 4 が上限3回で収束しない、のいずれかで著述不能 |

## 予想を裏切る挙動

- `status=traced` になるのは、§2 の観測列に空欄が1件も残らない場合だけである。業務の意図は §3 へ常に移すが、これは `status` の判定には影響しない。業務の意図は原理的に §2 の観測列ではないためである
- 帳票・バッチ・外部連携要件は、マニフェストが実在しても個別基本設計書が未生成なら §2 の一部列が空欄のまま残る。この状態は `NONE` でも `ERROR` でもなく `DONE` として返る。§3 には「個別基本設計書が未生成」の行が積み上がる
- 機能要件一覧だけは個別基本設計書を読まない。§2 の全列がマニフェスト単独で埋まる。機能一覧マニフェストは派生一覧という性質を持ち、個別の機能設計書は本文を持たず、関連画面・API・テーブルの対応表に近いためである

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 2 引数が実在し、対象 doc_id に対応するテンプレートの実在を確認済みで、対象文書の集合が確定している |
| Phase 2 | 選択された全種別について入力状態（マニフェスト有／該当なし／入力なし）、個別基本設計書の有無、および7種別の件数または対象外が確定している |
| Phase 3 | 対象文書の §2・§3・frontmatterの `status` が、観測できた範囲で記入済みである |
| Phase 4 | 6 検査すべてが合格している |
| **Goal** | 「入力なし」以外の対象文書が、業務語彙のみで観測事実と要確認事項一覧を分離した状態で `<output_dir>/<commonRoot>/` に確定している |

## 完了報告

`../../../delivery-payload/references/完了報告の書き方.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- 業務語彙の検査結果（grep 0件 / N件）
- 対象文書ごとの `status`（`draft` / `traced`）と、「入力なし」でスキップした文書の一覧

## 参照資料

本スキルは orchestrating-ai-development-setup へ結線されていない。単独起動時は上表の args をユーザーから直接取得する。

- `delivery-payload/templates/リバース検証/プロジェクト共通/機能要件一覧.md` — 雛形
- `delivery-payload/templates/リバース検証/プロジェクト共通/帳票要件.md`・`バッチ要件.md`・`外部連携要件.md`・`ビジネス概要.md` — 雛形
- `delivery-payload/references/納品物フォルダ体系.md` — 成果物の配置
- `delivery-payload/references/design-unit-layout.json` — 帳票・バッチ・外部連携の個別設計書のラベル・ファイル名の宣言
- `delivery-payload/references/output-layout.json` — 種別ラベル（`kindLabels`）の宣言
- `delivery-payload/references/output-layout.json` — 物理配置キー（`manifestsRoot`・`commonRoot`）の宣言
- `delivery-payload/references/output-layout.json` — 物理配置キー（`<kind>UnitRoot`・`unitListAbsentMd`）の宣言
- `.claude/skills/generating-feature-list-for-reverse-docs/SKILL.md` — 入力となる機能一覧マニフェストの生成元
- `.claude/skills/generating-report-list-for-reverse-docs/SKILL.md` — 入力となる帳票一覧マニフェストの生成元
- `.claude/skills/generating-batch-list-for-reverse-docs/SKILL.md` — 入力となるバッチ一覧マニフェストの生成元
- `.claude/skills/generating-external-list-for-reverse-docs/SKILL.md` — 入力となる外部連携一覧マニフェストの生成元
- `.claude/skills/generating-report-basic-design-for-reverse-docs/SKILL.md` — 入力となる帳票の個別基本設計書の生成元
- `.claude/skills/generating-batch-basic-design-for-reverse-docs/SKILL.md` — 入力となるバッチの個別基本設計書の生成元
- `.claude/skills/generating-external-basic-design-for-reverse-docs/SKILL.md` — 入力となる外部連携の個別基本設計書の生成元
- `.claude/skills/generating-reverse-common-docs/SKILL.md` — 出力先配置の踏襲元。同じ `<output_dir>/<commonRoot>/` へ出力する先行スキルである
