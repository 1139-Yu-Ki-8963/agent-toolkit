---
name: generating-batch-detail-design-for-reverse-docs
description: |
  バッチ詳細設計書を原本の処理定義から生成する（unit_kind=batch 専用）。
  TRIGGER when: バッチ詳細設計書の作成、処理手順とコミット・排他制御の書き起こし。
  SKIP: バッチ基本設計書の生成（→generating-batch-basic-design-for-reverse-docs）、バッチ一覧の作成（→generating-batch-list-for-reverse-docs）。
invocation: generating-batch-detail-design-for-reverse-docs
type: transform
allowed-tools: [AskUserQuestion, Bash, Grep, Read, Write]
---

# バッチ詳細設計書の生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはバッチ 1 本ごとの詳細設計書の執筆のみを担い、単独起動できる。起動引数は batch_manifest_path・source_dir・output_dir・template_root の 4 つで、これらを渡せば動く。`unit_kind` は **batch 固定** であり、引数では受け取らない。

## 情報源

情報源は次の 2 つに限る。

1. バッチ一覧の拡張マニフェスト（`batch-manifest.ext.json`。`unitId`・`unitKey`・`kind`・`unitNameGuess`・`identifier`・`detectionMethod`・`confidence`・`fileCount`・`sourceFile`・`schedule`・`targetTables`・`downstreamJobs`・`execMethod` を含む）
2. マニフェストの `sourceFile` が指す原本コード

抽出するのは、処理の流れ、コミットの単位、排他の制御、リトライ、件数と実行時間の目安である。基本設計スキルが担う意味は抽出しない。それはバッチ基本設計書（generating-batch-basic-design-for-reverse-docs）の担当である。

## 使用タイミング

- バッチ一覧が生成済みで、ジョブ単位の詳細設計書を作りたいとき
- 前提: `<output_dir>/一覧/バッチ一覧/batch-manifest.ext.json` が生成済みであること

## 起動引数

| 引数 | 必須 | 内容 |
|---|---|---|
| `batch_manifest_path` | 必須 | バッチ一覧の拡張マニフェストの絶対パス |
| `source_dir` | 必須 | 原本コードのルート |
| `output_dir` | 必須 | 出力先のルート |
| `template_root` | 必須 | テンプレート群のルート |
| `unit_keys` | 任意 | 対象を絞るキーの配列 |
| `common_docs_root` | 任意 | 共通文書のルート |

`unit_kind` は `batch` 固定であり引数に取らない。

## 成果物

| 項目 | 値 |
|---|---|
| 出力フォルダ | `<output_dir>/バッチ/batch-<バッチ識別子>/詳細設計/` |
| 出力ファイル | `バッチ詳細設計書.md` |
| テンプレート | `<template_root>/リバース検証/バッチ/バッチ詳細設計書.md` |

`<バッチ識別子>` はマニフェストの `unitId` を使う。`unitId` が空（`null` または空文字）の場合は `unitKey` を使う。両方が空の場合だけ当該ユニットを生成せず、`status=ERROR` で中断して hint に「出力先の識別子が確定しない」と当該ユニットの `identifier` を記録する。

実マニフェストでは `unitId` が全件空のことがある。一覧生成側が `unitId` を非必須フィールドとして扱い、実装にも `null` を入れる分岐があるためである。合成フィクスチャでは埋まっていることが多く、この状態は実データでしか現れない。

`unitKey` をディレクトリ名に使う場合、パス区切り（`/`）と制御文字をそのまま使わない。含む場合はハイフンへ置き換えて使い、置換した事実を当該設計書の要確認事項一覧へ記録する。

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` で Phase 1〜4 のタスクを登録する。各 Phase 開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 4 から Phase 3 へ差し戻す場合は該当タスクを `in_progress` に戻す。実行環境に TaskCreate/TaskUpdate が存在しない場合は、出力先ディレクトリ内のタスク台帳ファイル（`task-ledger.md`）で同等の Phase 遷移記録を代替する。

## Phase 1: 起動引数の検収と対象の確定

## Step 1-1: 起動引数の検収と対象の確定

- **Step 1**: 必須 4 引数の実在を確認する（`test -f` / `test -d`）。いずれかが欠ける場合は `status=ERROR` で停止する。完了条件: 4 引数すべてが実在する
- **Step 2**: `batch_manifest_path` を Read し、`unitKind` が `batch` であること、`units` が 1 件以上あることを確認する。完了条件: マニフェストが検収済み
- **Step 3**: 対象ユニットを確定する。`unit_keys` が渡されていればその集合、無ければマニフェストの全ユニットを対象とする。完了条件: 対象ユニットの一覧が確定済み

**完了**: 4 引数が実在し、マニフェストが検収済みで、対象ユニットが確定している

## Phase 2: 原本読解

## Step 2-1: ユニットごとの原本読解

対象ユニット 1 件につき次を行う。

- **Step 1**: マニフェストの `sourceFile` が指すファイルを Read する。完了条件: 読解対象のファイルが確定済み
- **Step 2**: 処理の流れ、コミットの単位、排他の制御、リトライ、件数と実行時間の目安を原本から抽出する。各項目に `file:line` 形式の根拠を付ける。根拠を付けられない項目は空欄のままとし、要確認事項一覧へ回す。完了条件: 全項目の記入材料が根拠付きで揃っている
- **Step 3**: マニフェストの `schedule`・`targetTables`・`downstreamJobs`・`execMethod` と、原本から読み取った内容の整合を確認する。食い違いがあれば要確認事項一覧へ記録する。完了条件: マニフェストとの整合確認が済んでいる

**完了**: 対象ユニット全件について、根拠付きの記入材料が揃っている

## Phase 3: 執筆

### テンプレートの配置

執筆の前に、テンプレートを出力先へ配置する。手作業で Read と Write を行わず、次のスクリプトを呼ぶ。

```bash
bash shared/scripts/scaffold-design-unit.sh batch detail <output_dir> <識別子> <表示名> <template_root>
```

`<kind>` と `<phase>` は本スキルの担当に固定する。配置済みのファイルへ記入する形で執筆する。

配置に失敗した場合は執筆へ進まず、`status=ERROR` を返す。

## Step 3-1: テンプレートの展開と記入

- **Step 1**: `<template_root>/リバース検証/バッチ/バッチ詳細設計書.md` を Read する。読み込んだ内容を `<output_dir>/バッチ/batch-<バッチ識別子>/詳細設計/バッチ詳細設計書.md` へ書き出す。`<バッチ識別子>` の決め方は「成果物」節の規約に従う。中間ディレクトリが無ければ作成する。完了条件: 全対象ユニットのファイルが配置済み
- **Step 2**: Phase 2 で得た材料を各章へ記入する。原本に無い値を書かない。推測で埋めない。完了条件: 各章の記入が完了している
- **Step 3**: 空欄のまま残った項目を要確認事項一覧へ列挙する。キーは連番を禁じ、内容を要約した意味語で付ける。完了条件: 要確認事項一覧が埋まっている
- **Step 4**: frontmatter の `status` を `draft` から `authored` へ更新する。完了条件: `status: authored` になっている

**完了**: 全対象ユニットの設計書が記入済みである

## Phase 4: 機械検査

## Step 4-1: 機械検査

次の 5 つを実行する。1 つでも不合格なら Phase 3 へ戻る。上限 3 回で収束しなければ `status=ERROR` とする。

- **検査1 拡張マニフェスト記載事項の一致**: マニフェストの `schedule`・`targetTables`・`downstreamJobs`・`execMethod` のうち値を持つフィールドが、生成した本文に反映されていることを確認する。不一致 0 件で合格
- **検査2 注記の残存検査**: テンプレートの記入規則を書いた HTML コメント（`<!-- -->`）が残っていないことを確認する。残存 0 件で合格
- **検査3 frontmatter の検査**: `status` が `authored` になっていることを確認する
- **検査4 章の完備検査**: テンプレートが持つ全ての章見出しが出力に存在することを確認する
- **配置の検査**: `bash shared/scripts/scaffold-design-unit.sh --verify batch detail <output_dir> <識別子>` を実行し、必須ファイルの存在・トークンの残存なし・章の完備・配置先の妥当性を確認する

**完了**: 5 検査すべてが合格している

## 根拠の書き方

本スキルは詳細設計であり、根拠は本文に書いてよい。原本のファイルと行を `file:line` の形で示す形で記録する。これは兄弟の基本設計スキル（generating-batch-basic-design-for-reverse-docs）が根拠を本文に書かない方針と逆である。詳細設計は実装用語を使ってよく、実装用語の混入を理由に差し戻すことはしない。

## サブエージェント委任仕様

本スキルは子スキルを起動しない。原本読解と執筆（Phase 1〜3）は一貫性を保つため単一のメインエージェントが通しで担う。

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
| `DONE` | 全対象ユニットのバッチ詳細設計書が記入済み、かつ Phase 4 の 4 検査すべてに合格した |
| `ERROR` | 必須引数の欠落・マニフェスト不整合・出力先の識別子が確定しない・Phase 4 が上限 3 回で収束しない、のいずれかで著述不能 |

## 予想を裏切る挙動

- 実マニフェストでは `unitId` が全件空のことがある。その場合の出力先は `unitKey` 由来になるため、合成フィクスチャで確認した出力先と実データでの出力先が一致しないことがある
- 本スキルは実装用語の混入を検査対象としない。実装用語をそのまま本文に書いてよい点が兄弟の基本設計スキルと逆である
- 本スキルの成果物は往復検証の対象外である。バッチ詳細設計書だけからコードを再生成して原本と突き合わせる検証は行わない

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 4 引数が実在し、マニフェストが検収済みで、対象ユニットが確定している |
| Phase 2 | 対象ユニット全件について、根拠付きの記入材料が揃っている |
| Phase 3 | 全対象ユニットの設計書が記入済みである |
| Phase 4 | 5 検査すべてが合格している |
| **Goal** | 対象バッチごとに、根拠付きの処理定義と要確認事項を持つ設計書が生成されている |

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- 拡張マニフェスト記載事項の一致結果（差分 0件 / N件）
- 全対象ユニットの `status: authored` への更新状況

## 参照資料

本スキルは orchestrating-reverse-docs-flow の契約に準拠し、args 全量指定で単独起動できる。

- `.claude/skills/generating-batch-list-for-reverse-docs/SKILL.md` — 入力となるマニフェストの生成元
- `.claude/skills/generating-batch-basic-design-for-reverse-docs/SKILL.md` — バッチ単位の基本設計書（根拠を本文に書かない。本スキルとは根拠の書き方が逆）
- `shared/references/chapter-map.md` — 章の役割キーの対応表
- `shared/references/納品物フォルダ体系.md` — 成果物の配置
