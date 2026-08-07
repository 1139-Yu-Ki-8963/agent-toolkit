---
name: generating-report-basic-design-for-reverse-docs
description: |
  帳票 1本ごとの基本設計書を業務語彙のみで生成する（unit_kind=report 専用）。
  TRIGGER when: 帳票基本設計書の作成、出力物単位の業務設計書の生成。
  SKIP: 帳票詳細設計書の生成（→generating-report-detail-design-for-reverse-docs）、帳票一覧の作成（→generating-report-list-for-reverse-docs）。
invocation: generating-report-basic-design-for-reverse-docs
type: transform
allowed-tools: [AskUserQuestion, Bash, Grep, Read, Write]
---

# 帳票基本設計書の生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルは帳票 1 本ごとの基本設計書の執筆のみを担い、単独起動できる。起動引数は report_manifest_path・source_dir・output_dir・template_root の 4 つが必須で、これらを渡せば動く。`unit_kind` は **report 固定** であり、引数では受け取らない。

## 情報源

情報源は次の 2 つに限る。

1. 帳票一覧の拡張マニフェスト（`report-manifest.ext.json`。`format`・`trigger` を含む）
2. マニフェストの `sourceFile` が指す原本コード

抽出するのは、項目の定義、出力の条件、出力の契機、レイアウトの要件である。項目の編集の処理、改ページ、集計といった実装の詳細は抽出しない。それは帳票詳細設計書（generating-report-detail-design-for-reverse-docs）の担当である。

## 使用タイミング

- 帳票一覧が生成済みで、出力物単位の業務設計書を作りたいとき
- 前提: `<output_dir>/一覧/帳票一覧/report-manifest.ext.json` が生成済みであること

## 起動引数

| 引数 | 必須 | 内容 |
|---|---|---|
| `report_manifest_path` | 必須 | 帳票一覧の拡張マニフェストの絶対パス |
| `source_dir` | 必須 | 原本コードのルート |
| `output_dir` | 必須 | 出力先のルート |
| `template_root` | 必須 | テンプレート群のルート |
| `unit_keys` | 任意 | 対象を絞るキーの配列 |
| `common_docs_root` | 任意 | 共通文書のルート。業務語彙とメッセージの突合に使う |

`unit_kind` は `report` 固定であり引数に取らない。

## 成果物

| 項目 | 値 |
|---|---|
| 出力フォルダ | `<output_dir>/帳票/report-<帳票識別子>/基本設計/` |
| 出力ファイル | `帳票基本設計書.md` |
| テンプレート | `<template_root>/リバース検証/帳票/帳票基本設計書.md` |

`<帳票識別子>` はマニフェストの `unitId` を使う。`unitId` が空（`null` または空文字）の場合は `unitKey` を使う。両方が空の場合だけ当該ユニットを生成せず、`status=ERROR` で中断して hint に「出力先の識別子が確定しない」と当該ユニットの `identifier` を記録する。

`unitKey` をディレクトリ名に使う場合、パス区切り（`/`）と制御文字をそのまま使わない。含む場合はハイフンへ置き換えて使い、置換した事実を当該設計書の要確認事項一覧へ記録する。

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` で Phase 1〜4 のタスクを登録する。各 Phase 開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 4 から Phase 3 へ差し戻す場合は該当タスクを `in_progress` に戻す。実行環境に TaskCreate/TaskUpdate が存在しない場合は、出力先ディレクトリ内のタスク台帳ファイル（`task-ledger.md`）で同等の Phase 遷移記録を代替する。

## Phase 1: 起動引数の検収と対象の確定

## Step 1-1: 起動引数の検収と対象の確定

- **Step 1**: 必須 4 引数の実在を確認する（`test -f` / `test -d`）。いずれかが欠ける場合は `status=ERROR` で停止する。完了条件: 4 引数すべてが実在する
- **Step 2**: `report_manifest_path` を Read し、`unitKind` が `report` であること、`units` が 1 件以上あることを確認する。完了条件: マニフェストが検収済み
- **Step 3**: 対象ユニットを確定する。`unit_keys` が渡されていればその集合、無ければマニフェストの全ユニットを対象とする。完了条件: 対象ユニットの一覧が確定済み

**完了**: 4 引数が実在し、マニフェストが検収済みで、対象ユニットが確定している

## Phase 2: 業務的な意味の抽出

## Step 2-1: ユニットごとの業務的な意味の抽出

対象ユニット 1 件につき次を行う。

- **Step 1**: マニフェストの当該ユニットのエントリ（`format`・`trigger` 等）を読む。完了条件: マニフェストの記載事項を把握済み
- **Step 2**: マニフェストの `sourceFile` が指す原本コードを Read し、項目の定義、出力の条件、出力の契機、レイアウトの要件を読み取る。項目の編集の処理・改ページ・集計は読み取らない。完了条件: 業務的な意味の記入材料が揃っている
- **Step 3**: コードから確定できない事項は推測で埋めず、要確認事項として記録する。完了条件: 未確定事項が要確認事項として整理済み

**完了**: 対象ユニット全件について、業務的な意味の記入材料が揃っている

## Phase 3: 執筆

## Step 3-1: テンプレートの展開と記入

- **Step 1**: `<template_root>/リバース検証/帳票/帳票基本設計書.md` を Read する。読み込んだ内容を `<output_dir>/帳票/report-<帳票識別子>/基本設計/帳票基本設計書.md` へ書き出す。`<帳票識別子>` の決め方は「成果物」節の規約に従う。中間ディレクトリが無ければ作成する。完了条件: 全対象ユニットのファイルが配置済み
- **Step 2**: Phase 2 で得た材料を業務語彙のみで各章へ記入する。原本に無い値を書かない。推測で埋めない。完了条件: 各章の記入が完了している
- **Step 3**: 空欄のまま残った項目を要確認事項一覧へ列挙する。キーは連番を禁じ、内容を要約した意味語で付ける。完了条件: 要確認事項一覧が埋まっている
- **Step 4**: frontmatter の `status` を `draft` から `authored` へ更新する。完了条件: `status: authored` になっている

**完了**: 全対象ユニットの設計書が業務語彙のみで記入済みである

## Phase 4: 機械検査

## Step 4-1: 機械検査

次の 4 つを実行する。1 つでも不合格なら Phase 3 へ戻る。上限 3 回で収束しなければ `status=ERROR` とする。

- **検査1 業務語彙の検査**: 生成した本文に実装用語が含まれないことを grep で確認する。検出対象はフレームワーク用語・型構文・`interface` の宣言・型注釈・原本の拡張子・内部の成果物名（`report-manifest`・`unitId`・`unitKey`・`detectionMethod`）。検出 0 件で合格

  ```bash
  grep -nE 'interface [A-Z]|: *(string|number|boolean)\b|\bstyled-components\b|\bFastAPI\b|\bExpress\b|@app\.(get|post|put|delete)|\.(py|pl|pm|cgi|rb|go|java)\b|report-manifest|unitId|unitKey|detectionMethod' <帳票基本設計書.md>
  ```

- **検査2 注記の残存検査**: テンプレートの記入規則を書いた HTML コメント（`<!-- -->`）が残っていないことを確認する。残存 0 件で合格
- **検査3 frontmatter の検査**: `status` が `authored` になっていることを確認する
- **検査4 章の完備検査**: テンプレートが持つ全ての章見出しが出力に存在することを確認する

**完了**: 4 検査すべてが合格している

## 根拠の書き方

兄弟の詳細設計スキル（generating-report-detail-design-for-reverse-docs）は本文に `file:line` の形で根拠を書くよう求めるが、本スキルではこれを禁止する。業務語彙の検査がファイルパスを検出するためである。根拠は本文に書かず、実行結果の報告へ記録する。この方針は generating-reverse-basic-design の「紐づけの確認は執筆者の自己点検で行い、本文に注記を書かない」という記述に従う。

## サブエージェント委任仕様

本スキルは子スキルを起動しない。原本読解と執筆（Phase 1〜3）は業務語彙の一貫性を保つため単一のメインエージェントが通しで担う。

## ループ設計

Phase 4（機械検査）で不合格が検出された場合、該当箇所を Phase 3 で書き直して Phase 4 を再実行する。

| 要素 | 内容 |
|---|---|
| 反復条件 | 4 検査のいずれかが 1 件でも不合格なら、該当箇所を書き直して Phase 4 を再実行する |
| 上限回数 | 3回 |
| 停止条件 | 収束停止: 4 検査すべて合格 ／ リソース上限: 3回到達（未収束の場合は `status=ERROR` として呼び出し元へ差し戻す） |

## 停止条件

| status | 意味 |
|---|---|
| `DONE` | 全対象ユニットの帳票基本設計書が業務語彙のみで記入済み、かつ Phase 4 の 4 検査すべてに合格した |
| `ERROR` | 必須引数の欠落・マニフェスト不整合・出力先の識別子が確定しない・Phase 4 が上限 3 回で収束しない、のいずれかで著述不能 |

## 予想を裏切る挙動

- 実マニフェストでは `unitId` が全件空のことがある。その場合の出力先は `unitKey` 由来になるため、合成フィクスチャで確認した出力先と実データでの出力先が一致しないことがある
- 本スキルの業務語彙の検査は、根拠を `file:line` で本文に書く詳細設計書とは逆に、ファイルパス形式の文字列そのものを不合格の対象とする。根拠を本文に書く癖のまま執筆すると検査4で必ず差し戻される
- 本スキルの成果物は往復検証の対象外である。基本設計書だけからコードを再生成して原本と突き合わせる検証は行わない

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 4 引数が実在し、マニフェストが検収済みで、対象ユニットが確定している |
| Phase 2 | 対象ユニット全件について、業務的な意味の記入材料が揃っている |
| Phase 3 | 全対象ユニットの設計書が業務語彙のみで記入済みである |
| Phase 4 | 4 検査すべてが合格している |
| **Goal** | 対象帳票ごとに、業務語彙のみで書かれた基本設計書と要確認事項一覧が生成されている |

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- 業務語彙の検査結果（grep 0件 / N件）
- 全対象ユニットの `status: authored` への更新状況

## 参照資料

本スキルは orchestrating-reverse-docs-flow の契約に準拠し、args 全量指定で単独起動できる。

- `.claude/skills/generating-report-list-for-reverse-docs/SKILL.md` — 入力となるマニフェストの生成元
- `.claude/skills/generating-report-detail-design-for-reverse-docs/SKILL.md` — 帳票単位の詳細設計書（原本読解型・`file:line` 根拠を本文に書く。本スキルとは根拠の書き方が逆）
- `.claude/skills/generating-reverse-basic-design/SKILL.md` — 業務語彙限定・根拠を本文に書かない方針の引用元
- `shared/references/chapter-map.md` — 章の役割キーの対応表
- `shared/references/納品物フォルダ体系.md` — 成果物の配置
