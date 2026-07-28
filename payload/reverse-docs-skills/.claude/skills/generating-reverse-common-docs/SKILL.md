---
name: generating-reverse-common-docs
description: "対象コードから層化サンプリングで共通6文書のv0を採録する。 TRIGGER when: アーキテクチャ調査書確定後の共通文書採録、NG帰着(c)共通文書欠落の追記。 SKIP: 規約4種・facts抽出・詳細設計執筆。"
invocation: generating-reverse-common-docs
type: orchestration
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, TaskCreate, TaskUpdate]
---

# プロジェクト共通採録スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはアーキテクチャ調査書を前提に、対象リポジトリのコードから層化サンプリングで共通6文書の v0 を採録する。規約4種の調査・分類・生成は専用規約スキルの責務であり、本スキルは規約を作成・追記しない。

対象リポジトリに対しては読み取り専用で動作する。書き込み・変更は一切行わない。出力は `output_dir` 側の共通6文書とサンプル記録のみ。v0 で確定して止める（完成を狙わない）。追記は `mode=append` の別起動でのみ行う。

## 使用タイミング

- 全実在種別のfactsと静的設計が確定した後、共通6文書を統合したいとき
- 往復検証が共通6文書の欠落を検出し、該当文書へ追記したいとき（`mode=append`）

### args（全量指定・対話ゼロ）

| 引数 | 必須 | 内容 |
|---|---|---|
| target_repo_path | 必須 | 対象リポジトリの絶対パス |
| output_dir | 必須 | 出力先ルート。共通6文書とサンプル記録は `<output_dir>/プロジェクト共通/` 配下に出力する |
| template_root | 必須 | テンプレ一式のルート。`<template_root>/プロジェクト共通/` の共通6文書テンプレ（共通設計書・メッセージ定義書・DESIGN・基盤設計・UI共通設計・データ設計）を雛形に使う |
| survey_doc_path | 必須 | アーキテクチャ調査書のパス（ディレクトリ責務マップを層化サンプリングの層定義に使う） |
| mode | 任意（既定 `v0`） | `v0`（新規）／`append`（NG帰着(c)の追記。`append_findings` を受け取り該当文書へ追記して全ゲート再実行） |
| append_findings | `mode=append` 時のみ必須 | 差し戻し元が指摘した欠落挙動・欠落文書の一覧 |

本スキルはユーザーに直接確認しない（AskUserQuestion不使用）。単独起動時は上表の args をユーザーから直接取得する。

## 設計原則

- **読み取り専用**: 対象リポジトリへの書き込み・変更は一切行わない。出力は `output_dir` 配下のみ
- **実装事実主義**: サンプルに現れない規則を発明しない。理想論（あるべき姿）を書かず、実装済みコードに現に存在する事実だけを記録する
- **サンプル外裏取り（但し書き）**: サンプル内コードから参照されている定義本体は、規模・件数・キー一覧の実測に限りサンプル外でも開いて裏取りする。カタログ規模の推測表現を禁止する
- **三点セット必須**: 各規則行は実例（対象リポジトリ内の相対パス3件以上）・頻度（サンプル中の該当割合）・例外率（例外があれば例外の実例パスも）を必ず添える
- **決定的サンプリング**: 層化サンプリングはサブディレクトリ層化（層の直下と各サブディレクトリから均等に選び、残余は辞書順で充当する）で行う。アーキテクチャ調査書が名指しするディレクトリは必須サンプルとして先取りする。選定コマンドは `find`/`sort`/`head` の決定的コマンドに固定する。乱数・目視選定を禁止する（詳細は `references/sampling-rules.md`）
- **v0で止める**: 本スキルは完成を狙わない。v0確定後の追記は `mode=append` の別起動でのみ行う
- **合格判定はスクリプトのexit codeのみ**: 自然文の自己申告での合格判定を行わない

## Phase 手順

### Phase 1: 前提確認

`target_repo_path`・`template_root`・`survey_doc_path` の実在を確認する（`test -d`/`test -f`）。調査書内「ユニット種別判定」節と「ディレクトリ責務マップ」節の実在を `grep` で確認する。共通6文書テンプレを出力先へ複製する。`mode=append` の場合は既存の共通6文書とサンプル記録を確認し、`append_findings` から共通文書だけを洗い出す。

完了条件: 共通6文書テンプレ複製済み、調査書の2節実在確認済み（`mode=append` 時は既存7文書と指摘文書の特定済み）

### Phase 2: 層化サンプリング

調査書のディレクトリ責務マップの各層（責務ディレクトリ）ごとに、サブディレクトリ層化で決定的にサンプルファイル集合を確定する: 単純な `find <層> -type f | sort | head -n <k>` は先頭の辞書順サブディレクトリに偏るソート順バイアスを持つため、層の直下に存在するファイルと各サブディレクトリに存在するファイルとで均等に配分し、残余は辞書順で充当する。アーキテクチャ調査書がディレクトリ責務マップ・後続工程への申し送り等で名指ししたディレクトリは、均等配分に先立って必須サンプルとして先取りする（k値の残り枠から差し引く）。k は層あたり3〜10、詳細な決め方は `references/sampling-rules.md`。全層合計20ファイル以上を確保する。選定コマンドと結果一覧を `<output_dir>/プロジェクト共通/サンプル記録.md` に書き出す（再現可能性の担保）。

完了条件: サンプル記録.md に全層の選定コマンドと選定ファイル一覧が記録済み（合計20ファイル以上）

### Phase 3: 規約成果物の受け渡し確認

規約4種は調査・分類・専用規約スキルが担当する。本スキルは規則を採録・生成・追記しない。

完了条件: 規約の不足は専用規約スキルへの差し戻しとして記録済み

### Phase 4: 共通文書採録

共通設計書.md、メッセージ定義書.md、DESIGN.md、基盤設計.md、UI共通設計.md、データ設計.mdを統合する。入力はアーキテクチャ調査書、層化サンプル、確定済みunit facts、静的設計である。各記述に根拠パスを残し、理想論や推測した意図は書かない。

完了条件: 6文書のプレースホルダ残存ゼロ

### Phase 5: 機械ゲート

`scripts/check-common-docs.sh --scope common-only <output_dir>/プロジェクト共通 <target_repo_path>` を実行する。規約に関する指摘は専用規約スキルへ、共通文書の指摘はPhase 4へ差し戻す。上限到達で収束しない場合は `status=中断` とし、hintに残欠落を記録する。

再試行時の探索範囲拡大: check-common-docs.sh が「検出例不足」（frequency_gap / example_shortage を含む）を報告し、かつ Phase 2 のサンプリング範囲が全ディレクトリを未走査の場合、Phase 2 を scope=wider で再実行してからPhase 3-4 へ進む。全ディレクトリ走査済みの場合は「scope-exhausted」として発散検知と同等に中断する（status=中断、hint に scope-exhausted を記録）。

完了条件: ゲート `exit 0`

### Phase 6: 返却

`mode=v0`は`status=採録v0確定`を返す。返却には共通6文書、サンプル記録、共通文書ルートを含める。`mode=append`は共通文書だけを追記し、`status=追記完了`を返す。

完了条件: `status` が確定している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 共通6文書テンプレ複製済み。調査書の2節実在確認済み（`mode=append` 時は既存6文書と指摘文書の特定済み） |
| Phase 2 | サンプル記録.mdに全層の選定コマンドと選定ファイル一覧が記録済み（合計20ファイル以上） |
| Phase 3 | 規約成果物の担当外確認と、必要時の専用規約スキルへの差し戻し記録が完了 |
| Phase 4 | 6文書のプレースホルダ残存ゼロ |
| Phase 5 | `check-common-docs.sh` が `exit 0` |
| Phase 6 | `status` 確定（`採録v0確定` \| `追記完了` \| `中断`） |
| **Goal** | サンプルに現れた実装事実のみを根拠とする共通6文書とサンプル記録が common-only 機械ゲートで確定し、後続工程が前提として読み込める |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約（返却ブロック共通サブセット: status/scope/artifacts/hint）に準拠する。

| キー | 値 |
|---|---|
| status | `採録v0確定` \| `追記完了` \| `中断` |
| scope | `target_repo_path` のbasename |
| artifacts | `[共通6文書とサンプル記録の絶対パス]` |
| hint | 次工程への申し送り、または中断理由 |
| common_docs_root（拡張） | `プロジェクト共通/` の絶対パス |
| sample_manifest_path（拡張） | サンプル記録.mdの絶対パス |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復対象 | Phase 5（機械ゲート） `exit 1` → Phase 4（共通文書採録）へ戻る |
| 上限回数 | 5回 |
| 収束条件 | `check-common-docs.sh` が `exit 0` |
| 発散条件 | 同一のNG理由（同一検査項目の同一違反）が2回連続で再発した場合、発散として即中断する（上限回数消化前でも中断してよい） |
| 上限到達時の報告 | `status=中断` とし、`hint` に未解消の検査項目・違反内容・試行回数を記録する |
| 検証役の分離 | 合否判定は `check-common-docs.sh` の `exit code` のみで行う。自然文の自己申告での合格判定は行わない |

## 重要な注意事項

- 対象リポジトリに対しては読み取り専用。書き込み・変更は一切行わない
- 出力は `output_dir` 側のみ（共通6文書とサンプル記録）。対象リポジトリ側には何も生成しない
- サンプルに現れない規則を発明しない。実例3件以上・頻度・例外率が揃わない規則は書かない
- 層化サンプリングの選定は決定的コマンド（`find`/`sort`/`head`）に固定する。乱数・目視選定を禁止する
- v0で確定して止める。完成を狙わず、追記は `mode=append` の別起動でのみ行う
- AskUserQuestionを使わない。args全量指定・対話ゼロで完走する
- 合格判定は `check-common-docs.sh` の `exit code` のみで行う。自然文の自己申告は用いない
- SKILL.md本文にプロジェクト固有値（リポジトリ名・画面名・絶対パス・ユーザー名）を一切書かない。固有値はすべて起動argsで受ける

## 予想を裏切る挙動

- common-only は規約行を検証しない。規約の実例数・頻度・例外率・記載パスは専用規約スキルの検証器で判定する
- common-only の記載パス実在チェックは、共通設計書.md・メッセージ定義書.md・DESIGN.mdを対象に、backtickで囲んだ相対パスだけを対象とする。
- メッセージ定義書規模突合（機械ゲート検査6）は、メッセージ定義書.md内の「総件数: <N>件」宣言行と、backtickメッセージ文字列を含むテーブル行の実測件数を突合する。宣言行が無い場合もFAILとする（カタログ規模を推測表現で書けないようにするための機械検証）
- common-only は規約4文書を走査しない。共通6文書には実装事実主義を適用する
- common-only のテンプレ残存検査は共通6文書とサンプル記録を走査する。
- `mode=append` は指摘文書のみ追記すればよいが、機械ゲートは全項目を再実行する。部分ゲートは存在しない
- 発散判定（同一NG理由2連続）は上限5回を消化する前でも即中断する
- 層あたりのk値は層内ファイル数の平方根以上・3以上10以下に丸める。全層合計20ファイル未満だとPhase 2の完了条件を満たさない（詳細は `references/sampling-rules.md`）
- ディレクトリ責務マップの行が「共有ファイル」型（責務列が `共有ファイル（` で始まる）の場合はこの限りでない。対象そのものが単一ファイルのため N=1・k=1固定として扱う（詳細は `references/sampling-rules.md`「共有ファイル行の扱い」）

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- check-common-docs.sh が exit 0・プレースホルダ残存ゼロ

## 設計判断

### check-common-docs.sh

**必要性**: プロジェクト共通文書の品質保証（実例・頻度・例外率の三点セット完備・記載パスの実在・テンプレ残存の不在・理想論表現の不在・メッセージ定義書の規模突合）を、実行者・実行回ごとにブレる自然文の目視確認に委ねると、「サンプルに現れた実装事実のみを根拠とする」という本スキルの中核原則を機械的に検証できない。6検査すべてを1本の決定的スクリプトへ固定化し、`exit code` のみで合否を判定することで、採録担当（人間・サブエージェント問わず）の記述品質を再現可能な基準で強制する。姉妹スキル `surveying-architecture-for-reverse-docs` の `check-architecture-survey.sh` と同じ設計方針（4検査→5検査→6検査への拡張）を踏襲する。

**代替案を採用しなかった理由**:
- Bashツール直叩き: 6検査（実在・規則行完備性・パス実在・テンプレ残存・理想論表現・メッセージ定義書規模突合）を毎回インラインで書くと実行のたびに判定基準がブレる。特に「テーブル行のうちbacktickパス候補を含む行だけを規則行とみなす」判定・「頻度/例外率の正規表現照合」は数十行のロジックを要し、都度手書きは再現性がない
- 既存Makefile拡張: 本スキルはプロジェクト非依存でMakefileを持たない
- Claude自己申告（検証コマンドを介さない目視確認）: 自己申告のみでの品質保証は、姉妹スキルが既に実害（`entryFile=None` 混入等）を経験しており、同種の実害を防ぐため決定的スクリプトに固定する

**保守責任者**: 人手（ユーザー）。検査基準・除外規則を変更した時に更新する。

**廃棄条件**: 共通6文書のフォーマットが廃止された時、または本スキルが撤回された時。

## 参照資料

- `~/reverse-docs-skills/.claude/skills/orchestrating-reverse-docs-flow/references/contract.md` — 返却ブロック契約・args仕様の正本
- `references/sampling-rules.md`（本スキル同梱） — 層化サンプリングの層定義・k値の決め方・決定的選択手順・サンプル記録.mdの記載様式
- `shared/templates/リバース検証/プロジェクト共通/` — 共通6文書の雛形。規約4種は専用規約スキルが扱う。
- `shared/references/リバース工程設計.md` — 工程対応の定義。本スキルはD5 / Step 15の共通統合を担当する
- `.claude/skills/surveying-architecture-for-reverse-docs/SKILL.md` — 本スキルが前提とするアーキテクチャ調査書を確定する上流スキル

<!-- delivery-owner-contracts:start -->
```json
[{"failure_return_to":"orchestrating-reverse-docs-flow","id":"common-design","inputs":["architecture baseline","unit facts"],"outputs":["プロジェクト共通/共通設計書.html"],"stop_conditions":["根拠なし"],"validator":"check-delivery-artifacts.sh"},{"failure_return_to":"orchestrating-reverse-docs-flow","id":"message-definition","inputs":["unit facts"],"outputs":["プロジェクト共通/メッセージ定義書.html"],"stop_conditions":["根拠なし"],"validator":"check-delivery-artifacts.sh"},{"failure_return_to":"orchestrating-reverse-docs-flow","id":"design-md","inputs":["style sources"],"outputs":["プロジェクト共通/DESIGN.md"],"stop_conditions":["根拠なし"],"validator":"check-delivery-artifacts.sh"},{"failure_return_to":"orchestrating-reverse-docs-flow","id":"platform-design","inputs":["architecture baseline"],"outputs":["プロジェクト共通/基盤設計.html"],"stop_conditions":["根拠なし"],"validator":"check-delivery-artifacts.sh"},{"failure_return_to":"orchestrating-reverse-docs-flow","id":"ui-common-design","inputs":["component facts"],"outputs":["プロジェクト共通/UI共通設計.html"],"stop_conditions":["根拠なし"],"validator":"check-delivery-artifacts.sh"},{"failure_return_to":"orchestrating-reverse-docs-flow","id":"data-design","inputs":["table facts"],"outputs":["プロジェクト共通/データ設計.html"],"stop_conditions":["根拠なし"],"validator":"check-delivery-artifacts.sh"}]
```
<!-- delivery-owner-contracts:end -->
