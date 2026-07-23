---
name: generating-entity-state-for-reverse-docs
description: "状態遷移図.html をデータ設計.mdの状態遷移表から機械生成する。 TRIGGER when: 状態遷移図生成、エンティティ状態遷移の図化、entity-state HTML作成。 SKIP: 状態遷移表自体の採録（→generating-reverse-common-docs）、他種別詳細ページ生成。"
invocation: generating-entity-state-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate]
---

# 状態遷移図生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの将来ページ受け口のうち状態遷移図（T7）のみを担い、単独起動できる（起動引数を渡せば動く）。

データ設計.md の §6 状態遷移表（生成済み。generating-reverse-common-docs が採録する）をエンティティの状態遷移の正とする。表の各行を機械的に nodes/edges へ変換し、**状態遷移図.html** として書き出す。**本スキルは判定・評価を一切行わない**。状態遷移表に記載された遷移のみを転記する。表に記載がない状態遷移を推測・補完しない。状態遷移表が未採録、または該当章に行が 1 件もない場合は、生成せず事実として停止報告する。

## 使用タイミング

- データ設計.md の §6 状態遷移表が確定済みで、ポータルに状態遷移図カードを追加したいとき
- 起動引数: `target_repo_path`（対象リポジトリの絶対パス。根拠パスの実在検証に使用）・`output_dir`（データ設計.md 所在 / 状態遷移図.html 出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行する。ただし状態遷移図（entity-state）のポータルカード受け口は本スキル作成時点で `build-portal.sh` に未配線であり、再実行してもカードが増えないことがある（別途の配線作業を要する。本スキルの責務外）

出力先は `<output_dir>/状態遷移図.html` に固定する（`build-detail-page.sh` の `get_page_filename` と同値）。前提となるデータ設計.md は `<output_dir>/プロジェクト共通/データ設計.md` を既定パスとする。

## 設計原則

- **抽出元は単一** — データ設計.md の §6 状態遷移表 1 箇所のみを一次情報とする。対象リポジトリへの新規走査は行わない（根拠パスの実在検証のみ `--target-repo` で行う）
- **表外の遷移は捏造しない** — 状態遷移表に記載がない状態・遷移をコード調査や推測で補わない
- **行 0 件は停止** — §6 状態遷移表に行が 1 件もない場合、page-data を生成せずユーザーへ報告して停止する
- **固定と可変の分離** — 整合検証（`validate-page-data.sh`）と HTML 生成（`build-detail-page.sh`）は決定的スクリプトに固定する。抽出（表の行→nodes/edges への変換）は Claude 自身が Bash/Read で行う

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| 整合検証 | `../../../shared/scripts/detail-pages/validate-page-data.sh` |
| HTML生成 | `../../../shared/scripts/detail-pages/build-detail-page.sh` |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` で Phase 1〜4 のタスクを登録する。各 Phase 開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 3 から Phase 2 へ差し戻す場合は Phase 2 タスクを `in_progress` に戻す。実行環境に TaskCreate/TaskUpdate が存在しない場合は、`output_dir` 内のタスク台帳ファイル（`task-ledger.md`）で同等の Phase 遷移記録を代替する。

## Phase 手順

### Phase 1: 前提確認

- **Step 1** — `<output_dir>/プロジェクト共通/データ設計.md` の実在と、`## §6 状態遷移表` 見出し・表（列: エンティティ/状態/遷移前/契機/遷移後/根拠パス）の実在を確認する。不在ならハード停止する。この場合 `generating-reverse-common-docs` の先行実行（データ設計.md §6 の採録）を案内して終了する。完了条件: 表の実在確認済み、または不在を報告して停止している
- **Step 2** — 表のデータ行数（プレースホルダ行 `<実測: ...>` のみの雛形状態は 0 件扱い）を確認する。0 件ならユーザーに報告してハード停止する（遷移を捏造しない）。完了条件: データ行 1 件以上を確認済み、または 0 件を報告して停止している

### Phase 2: 抽出

- **Step 1（nodes組み立て）** — 表の各行から `(エンティティ, 状態)` の組を集める。加えて `遷移前`/`遷移後` の値も同一エンティティの状態として扱い、`状態` 列にない値があれば合わせて集める（表記漏れによる孤児参照を防ぐため）。集めた組の重複を除いた一覧を `nodes[]` とする。`key` は `<エンティティ>.<状態>`（例: `注文.下書き`）、`label` は状態名そのもの、`entity` はエンティティ名とする。完了条件: `nodes[]` が確定済み
- **Step 2（edges組み立て）** — 表の各行を 1 edge に変換する。`from` は `<エンティティ>.<遷移前>`、`to` は `<エンティティ>.<遷移後>`、`trigger` は `契機` 列の値、`sourceRef` は `根拠パス` 列の値、`entity` はエンティティ名とする。完了条件: 表の全データ行が `edges[]` へ変換済み
- **Step 3（page-data.json組み立て）** — `pageKind: "entity-state"`、`legend[]`（矢印記号「→」= 状態遷移、程度の簡潔な凡例。任意で空配列も可）、`nodes[]`・`edges[]`・`unresolved[]`（表の記述からは解決できない遷移がある場合のみ使用。通常は空配列）を埋める。完了条件: page-data.json を一時ディレクトリへ保存済み

page-data.json の保存先は `$CLAUDE_JOB_DIR/tmp/entity-state-page-data.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

### Phase 3: 整合検証

- **Step 1** — 整合検証スクリプトを実行する。`edges[].from`/`to` が `nodes[].key` に実在するかの孤児参照検査を含め、`validate-page-data.sh` が機械実行する（手動事前確認は不要）。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/detail-pages/validate-page-data.sh <page-data.json> --target-repo <target_repo_path>
  ```

- **Step 2** — Step 1 が FAIL したら `[FAIL]` 項目名で分岐する。「孤児参照」FAIL の場合は、表の `状態`/`遷移前`/`遷移後` の値に表記ゆれ（同一状態の異表記等）がないかを確認し、Phase 2 Step 1（nodes組み立て）へ戻って修正する。その他の FAIL（`sourceRef` 実在等）は該当箇所を修正し Step 1 を再実行する。3 回失敗したら Phase 2 Step 1 へ差し戻す。完了条件: exit 0（孤児参照検査を含め全項目 PASS）

### Phase 4: 状態遷移図.html 生成

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<output_dir>/状態遷移図.html` が生成済み

  ```
  ../../../shared/scripts/detail-pages/build-detail-page.sh <page-data.json> <output_dir> --page entity-state
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行する。未指定（ポータル未生成環境）なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../shared/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-detail-page.sh` 経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | データ設計.md §6 状態遷移表の実在・データ行 1 件以上を確認済み（または不在・0 件を報告して停止） |
| Phase 2 | 表の全行から `nodes[]`・`edges[]` へ変換済み |
| Phase 3 | `validate-page-data.sh --target-repo` が全項目 PASS（孤児参照検査含む） |
| Phase 4 | `<output_dir>/状態遷移図.html` が生成済み |
| **Goal** | データ設計.md §6 状態遷移表から検証済みの状態遷移図.html が生成され、表に記載のない遷移は捏造せず、行 0 件時は停止報告されている |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（状態遷移表不在・データ行0件）\| `ERROR` |
| artifacts | 生成した状態遷移図.html のパス（`STOPPED`/`ERROR` 時は空） |
| page_kind | `entity-state`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定、またはentity-stateカード受け口が未配線のため省略） |
| hint | 停止理由（状態遷移表不在・データ行0件）、または次工程への申し送り |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復対象 | Phase 3 Step 1 が FAIL → Step 2 の分岐で修正して再実行 |
| 上限回数 | 3 回 |
| 収束停止 | `validate-page-data.sh` が exit 0（孤児参照検査含め全項目 PASS） |
| 発散検知 | 同一検査項目の同一 FAIL が 2 回連続で再発した場合は即座に Phase 2 Step 1（nodes組み立て）へ差し戻す |
| リソース上限 | 3 回失敗で Phase 2 Step 1 へ差し戻す |

## 重要な注意事項

- 判定・評価はしない。状態設計の良否・遷移の妥当性には一切踏み込まず、状態遷移表に記載された遷移の事実のみを転記する
- 状態遷移表に記載がない遷移を AskUserQuestion で聞き出さない。記載のない遷移を即興確定しない
- Phase 4 の HTML 手作業組み立てを禁止する。`build-detail-page.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `output_dir` 配下の状態遷移図.html のみ
- `shared/scripts/build-portal.sh` は本スキルの責務外。編集しない

## 予想を裏切る挙動

- 出力先は `<output_dir>` 直下（`状態遷移図` のような種別専用フォルダは作らない）。`build-detail-page.sh` の `--page entity-state` 固定出力名仕様に従う
- `nodes[].key` は `<エンティティ>.<状態>` 形式に固定する（ER図の `entities[].key` のような単一識別子ではなく、複数エンティティを横断する状態名の衝突を避けるための複合キー）
- 同一エンティティ内の自己遷移（例: 「差し戻し」で同じ状態へ戻る遷移は通常発生しないが、`from`/`to` が同一状態を指す行がある場合はそのまま転記する。孤児参照には該当しない
- `portal_output_dir` 未指定時は `build-portal.sh` を実行しない。生成済み状態遷移図.html はそのまま残り、`build-portal.sh` が entity-state のカード受け口に対応した時点で次回ポータル生成時にカード化される

## 設計判断

### エンジンスクリプトの共用（validate-page-data.sh / build-detail-page.sh）

**必要性**: page-data.json の整合検証と HTML 生成は pageKind 非依存の決定的処理であり、他種別（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順）と共通する。`shared/scripts/detail-pages/` の単一実装を全種別スキルが相対パスで共用することで、スキーマ変更時の同期漏れを防ぐ。

**代替案を採用しなかった理由**:
- スキルフォルダ内への複製: スキーマ変更時に種別数ぶんの同期漏れリスクが生じる
- Claude 手作業での HTML 組み立て: 検証なしのデータ混入が再発する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: page-data.json のスキーマ、または状態遷移図.html の形式が廃止された時

### nodes 集合を状態列だけでなく遷移前/遷移後からも補完する（Phase 2 Step 1）

**必要性**: 状態遷移表の `状態` 列は本来すべての状態を網羅する想定だが、表記漏れ（`遷移前`/`遷移後` にのみ登場し `状態` 列に採録されなかった状態）が起きた場合、そのまま `nodes[]` を組み立てると `edges[].from`/`to` が `nodes[].key` に存在しない孤児参照になり、Phase 3 で無用な差し戻しが発生する。`遷移前`/`遷移後` の値も状態集合の補完元として合わせて集めることで、表記漏れがあっても孤児参照を未然に防ぐ。

**代替案を採用しなかった理由**:
- `状態` 列のみを nodes の情報源とし、孤児参照は `validate-page-data.sh` の検査のみに任せる: 検査は捕捉するが、表記漏れのたびに Phase 2 まで差し戻す往復が発生し、抽出精度の向上に寄与しない

**保守責任者**: 人手（ユーザー）

**廃棄条件**: データ設計.md の状態遷移表フォーマットが `状態` 列の完全網羅を機械的に保証する形式に変更された時

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-page-data.sh` の PASS/FAIL 行と孤児参照の確認結果を追加する。

## 参照資料

- `../../../shared/scripts/detail-pages/page-data-schema.md` — page-data.json のスキーマ定義（T7: entity-state 節）
- `shared/templates/リバース検証/プロジェクト共通/データ設計.md` — §6 状態遷移表のテンプレート定義元
