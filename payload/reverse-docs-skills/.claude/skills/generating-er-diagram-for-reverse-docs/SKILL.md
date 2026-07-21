---
name: generating-er-diagram-for-reverse-docs
description: "ER図.html をテーブル一覧manifestとマイグレーション/モデルのFK定義から機械生成する。 TRIGGER when: ER図生成、テーブル関連図作成、ER diagram HTML作成。 SKIP: テーブル一覧自体の作成（→generating-table-list-for-reverse-docs）、他種別詳細ページ生成。"
invocation: generating-er-diagram-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate]
---

# ER図生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの将来ページ受け口のうち ER図（T4）のみを担い、単独起動できる（起動引数を渡せば動く）。

テーブル一覧.html に埋め込まれた manifest（`unit_kind=table`）をエンティティの正とする。対象リポジトリのマイグレーション/ORM モデル定義から外部キー（以下 FK）を抽出し、**ER図.html** として書き出す。**本スキルは判定・評価を一切行わない**。FK として検出できた関連のみを転記する。参照先テーブルが manifest に存在しない FK は、捏造せず `unresolved[]` に分離する。FK が 1 件も見つからない場合は、生成せず事実として停止報告する。

## 使用タイミング

- テーブル一覧.html が確定済みで、ポータルに ER 図カードを追加したいとき
- 起動引数: `target_repo_path`（対象リポジトリの絶対パス）・`docs_root`（テーブル一覧.html 所在 / ER図.html 出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<docs_root>/ER図.html` に固定する（`build-portal.sh` の `FUTURE_FILES` と同値）。前提となるテーブル一覧.html は `<docs_root>/テーブル一覧/テーブル一覧.html` を既定パスとする。

## 設計原則

- **抽出元は 2 段** — エンティティは確定済みのテーブル一覧 manifest（`units[]`）から取る。関連（FK）だけを対象リポジトリから新規抽出する
- **manifest 外参照は捏造しない** — FK の参照先テーブルが manifest の `units[]` に存在しない場合、関連として転記せず `unresolved[]` へ分離する
- **FK 0 件は停止** — 検出戦略に沿って走査しても FK が 1 件も見つからない場合、page-data を生成せずユーザーへ報告して停止する
- **固定と可変の分離** — 整合検証（`validate-page-data.sh`）と HTML 生成（`build-detail-page.sh`）は決定的スクリプトに固定する。抽出（FK 走査・entities/relations の組み立て）は Claude 自身が Bash/Read/Grep で行う

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| 整合検証 | `../../../shared/scripts/detail-pages/validate-page-data.sh` |
| HTML生成 | `../../../shared/scripts/detail-pages/build-detail-page.sh` |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

種別固有の FK 検出手法（ORM 別パターン・cardinality の導出規則）は `references/er-detection.md` を参照する。

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` で Phase 1〜4 のタスクを登録する。各 Phase 開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 3 から Phase 2 へ差し戻す場合は Phase 2 タスクを `in_progress` に戻す。実行環境に TaskCreate/TaskUpdate が存在しない場合は、`docs_root` 内のタスク台帳ファイル（`task-ledger.md`）で同等の Phase 遷移記録を代替する。

## Phase 手順

### Phase 1: 前提確認 + 検出戦略宣言

- **Step 1** — `<docs_root>/テーブル一覧/テーブル一覧.html` の実在を確認する。あわせて `<script type="application/json" id="unit-manifest">` の埋め込みも確認する。不在ならハード停止する。この場合 `generating-table-list-for-reverse-docs` の先行実行を案内して終了する。完了条件: manifest の実在確認済み、または不在を報告して停止している
- **Step 2** — `target_repo_path` の定義ファイル・依存関係から ORM/マイグレーション種別（SQLAlchemy／Prisma／生 SQL migration 等）を判別する。判別手法は `references/er-detection.md` の調査対象・検出手法を参照する。完了条件: 種別が特定済み、または特定不能の根拠（推定経路）が記録済み
- **Step 3** — 検出戦略（走査対象ファイル・FK 検出パターン・除外パターン）を宣言し、AskUserQuestion で承認を取る。宣言内容は一時ファイルに保存する。完了条件: 検出戦略（ORM 種別・走査対象・除外パターン・`approvedByUser: true`）が保存済み

### Phase 2: 抽出

- **Step 1** — テーブル一覧 manifest の `units[]` から `entities[]` を組み立てる。`kind != "unresolved"` の各 unit について `identifier` を `key`、`unitNameGuess` または `identifier` を `label` とする。完了条件: `entities[]` が確定済み
- **Step 2** — Phase 1 で確定した検出戦略に沿って FK を走査する。検出した FK ごとに参照元・参照先テーブルを特定する。両方が `entities[].key` に存在すれば `relations[]`（`from`/`to`/`cardinality`/`sourceRef`）へ分類する。参照先が `entities[].key` に存在しなければ `unresolved[]`（`label`/`reason`/`sourceRef`）へ分類する。`cardinality` の導出規則は `references/er-detection.md` を参照する。完了条件: 検出した FK すべてについて `relations[]` または `unresolved[]` への振り分けが完了済み
- **Step 3** — 検出件数を確認する。`relations[]` が 0 件ならユーザーに報告してハード停止する（関連を捏造しない）。完了条件: `relations[]` 1 件以上を確認済み、または 0 件を報告して停止している
- **Step 4** — page-data.json を組み立てる。`pageKind: "er"`、`legend[]`（`cardinality` の記号説明）、`entities[]`・`relations[]`・`unresolved[]` を埋める。完了条件: page-data.json を一時ディレクトリへ保存済み

page-data.json の保存先は `$CLAUDE_JOB_DIR/tmp/er-page-data.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

### Phase 3: 整合検証

- **Step 1** — 整合検証スクリプトを実行する。`relations[].from`/`to` が `entities[].key` に実在するかの孤児関連検査を含め、`validate-page-data.sh` が機械実行する（手動事前確認は不要）。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/detail-pages/validate-page-data.sh <page-data.json> --target-repo <target_repo_path>
  ```

- **Step 2** — Step 1 が FAIL したら `[FAIL]` 項目名で分岐する。「孤児参照」FAIL の場合は該当 relation を `unresolved[]` へ差し戻して Phase 2 Step 2（FK 走査）へ戻る。その他の FAIL（`sourceRef` 実在等）は該当箇所を修正し Step 1 を再実行する。3 回失敗したら Phase 2 Step 2（FK 走査）へ差し戻す。完了条件: exit 0（孤児関連検査を含め全項目 PASS）

### Phase 4: ER図.html 生成

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<docs_root>/ER図.html` が生成済み

  ```
  ../../../shared/scripts/detail-pages/build-detail-page.sh <page-data.json> <docs_root> --page er
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定（ポータル未生成環境）なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../shared/scripts/build-portal.sh <target_repo_path> <docs_root> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-detail-page.sh` 経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | テーブル一覧 manifest の実在確認済み（または不在を報告して停止）。検出戦略がユーザー承認済み |
| Phase 2 | `entities[]` を manifest から確定済み。FK 走査で `relations[]`/`unresolved[]` へ振り分け済み、または 0 件を報告して停止している |
| Phase 3 | `validate-page-data.sh --target-repo` が全項目 PASS（孤児関連検査含む） |
| Phase 4 | `<docs_root>/ER図.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | テーブル一覧 manifest と対象リポジトリの FK 定義から検証済みの ER図.html が生成され、manifest 外参照・0 件検出時は捏造せず停止報告されている |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（テーブル一覧不在・FK 0 件）\| `ERROR` |
| artifacts | 生成した ER図.html のパス（`STOPPED`/`ERROR` 時は空） |
| page_kind | `er`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由（テーブル一覧不在・FK 0 件）、または次工程への申し送り |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復対象 | Phase 3 Step 1 が FAIL → Step 2 の分岐で修正して再実行 |
| 上限回数 | 3 回 |
| 収束停止 | `validate-page-data.sh` が exit 0（孤児関連検査含め全項目 PASS） |
| 発散検知 | 同一検査項目の同一 FAIL が 2 回連続で再発した場合は即座に Phase 2 Step 2（FK 走査）へ差し戻す |
| リソース上限 | 3 回失敗で Phase 2 Step 2 へ差し戻す |

## 重要な注意事項

- 判定・評価はしない。テーブル設計の良否・正規化の妥当性には一切踏み込まず、FK として検出できた関連の事実のみを転記する
- FK 0 件・参照先不明時に AskUserQuestion で手動関連を聞き出さない。検出できない関連を即興確定しない
- Phase 4 の HTML 手作業組み立てを禁止する。`build-detail-page.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `docs_root` 配下の ER図.html のみ

## 予想を裏切る挙動

- 出力先は `<docs_root>` 直下（`ER図` のような種別専用フォルダは作らない）。`build-detail-page.sh` の `--page er` 固定出力名仕様に従う
- `entities[].key` はテーブル一覧 manifest の `identifier` を使う（`unitKey` ではない）。`relations[].from`/`to` は `entities[].key` を参照する必要があるため、この対応を崩さない
- マイグレーションと ORM モデルの両方が存在する場合、テーブル一覧生成時に確定した定義（Phase 1 の判別結果）と同じ側から FK を抽出する。両方を無差別に走査すると同一関連の重複検出になる
- 自己参照 FK（同一テーブル内の親子関係等）は `from`/`to` が同一の `entities[].key` になる。孤児関連には該当しない
- `portal_output_dir` 未指定時は `build-portal.sh` を実行しない。生成済み ER図.html はそのまま残り、次回ポータル生成時に自動でカード化される

## 設計判断

### エンジンスクリプトの共用（validate-page-data.sh / build-detail-page.sh）

**必要性**: page-data.json の整合検証と HTML 生成は pageKind 非依存の決定的処理であり、5 種別（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順）に共通する。`shared/scripts/detail-pages/` の単一実装を全種別スキルが相対パスで共用することで、スキーマ変更時の同期漏れを防ぐ。

**代替案を採用しなかった理由**:
- スキルフォルダ内への複製: スキーマ変更時に種別数ぶんの同期漏れリスクが生じる
- Claude 手作業での HTML 組み立て: 検証なしのデータ混入（テーブル一覧系での `entryFile=None` 混入実害）が再発する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: page-data.json のスキーマ、または ER図.html の形式が廃止された時

### 孤児関連の未然分離（Phase 2 Step 2 での unresolved[] 振り分け）

**必要性**: FK 抽出は Claude 自身が行うため、manifest 外参照（`entities[].key` に存在しない `to`）が紛れ込みうる。`validate-page-data.sh` の孤児参照検査（pageKind 非依存。transition の孤児 edge 検査と同型）は生成前に必ずこれを捕捉する。ただし抽出の時点で参照先未存在の FK を `unresolved[]` へ振り分けておけば、`relations[]` には解決済みの関連のみが積まれる。Phase 3 での FAIL・差し戻しの往復も減る。

**代替案を採用しなかった理由**:
- 抽出時に振り分けず `validate-page-data.sh` の孤児参照検査のみに任せる: 検証は捕捉するが、FAIL のたびに Phase 2 まで差し戻す往復が発生し、抽出精度の向上に寄与しない

**保守責任者**: 人手（ユーザー）

**廃棄条件**: `validate-page-data.sh` の孤児参照検査が抽出時点まで遡って自動振り分けを行うようになった時

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-page-data.sh` の PASS/FAIL 行と孤児関連の確認結果を追加する。

## 参照資料

- `../../../shared/scripts/detail-pages/page-data-schema.md` — page-data.json のスキーマ定義
- `references/er-detection.md` — ORM 別 FK 検出パターンと cardinality 導出規則
- `references/generating-er-diagram-for-reverse-docs-guide.html` — スキルガイド
