---
name: generating-screen-transition-for-reverse-docs
description: "画面遷移図.html を画面一覧マニフェストとコード内のルーティング定義から機械生成する。 TRIGGER when: 画面遷移図生成、画面遷移図作成、遷移図HTML作成。 SKIP: 画面一覧自体の作成（→generating-screen-list-for-reverse-docs）、他種別詳細ページ生成（→対応する種別別スキル）。"
invocation: generating-screen-transition-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate]
---

# 画面遷移図生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの将来ページ受け口のうち画面遷移図（T4）のみを担い、単独起動できる（起動引数を渡せば動く）。

画面一覧.html に埋め込まれたマニフェスト（画面の集合）と、対象リポジトリのルーティング定義を突合する。ルーティング定義とは Router 定義・`navigate()`・`<Link>`・`redirect` を指す。突合結果から **画面遷移図.html** を機械検証付きで生成する。**本スキルは判定・評価を一切行わない**。宛先を解決できない遷移は捏造せず `unresolved[]` へ隔離する。`route` が空文字列の画面（`validate-manifest.sh` は `route` キー自体の欠落を許さないため、実際に起こるのは空文字）も同様に隔離する。

## 使用タイミング

- 画面一覧.html が確定済みで、ポータルに画面遷移図カードを追加したいとき
- 起動引数: `target_repo_path`（調査対象リポジトリの絶対パス）・`docs_root`（画面一覧.html の所在かつ出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<docs_root>/画面遷移図.html` に固定する（`build-portal.sh` の `FUTURE_FILES` と同値）。前提となる画面一覧.html は `<docs_root>/画面一覧/画面一覧.html` に固定で存在することを見に行く。

## 設計原則: 固定と可変の分離

マニフェストスキーマ・整合検証（`validate-page-data.sh`）・HTML生成（`build-detail-page.sh`）は決定的スクリプトに固定する。抽出（Router 種別の判別・遷移の検出）はプロジェクトごとに可変である。

画面遷移の検出に組み込み検出器はない。**カスタム抽出パスのみ**を使う。Claude 自身が Phase 1 の戦略宣言に沿って、プロジェクト専用の抽出手順を設計・実行する。抽出結果は、スキーマ準拠の page-data.json（`pageKind: "transition"`）として出力する。抽出者が誰であっても、`validate-page-data.sh` が抽出者非依存で整合性を機械保証する。汎用の正規表現は無条件に当てない。対象プロジェクトの Router 種別（React Router・Next.js App/Pages Router・Vue Router 等）を先に判別してから検出し、遷移の取り違えを防ぐ。

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| 整合検証 | `../../../shared/scripts/detail-pages/validate-page-data.sh` |
| HTML生成 | `../../../shared/scripts/detail-pages/build-detail-page.sh` |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

種別固有の調査項目・Router 別検出パターンの詳細は `references/transition-detection.md` を参照する。

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` で Phase 1〜4 のタスクを登録する。各 Phase 開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 3 から Phase 2 へ差し戻す場合は Phase 2 タスクを `in_progress` に戻す。実行環境に TaskCreate/TaskUpdate が存在しない場合は、`$CLAUDE_JOB_DIR/tmp/task-ledger.md` で同等の Phase 遷移記録を代替する。

## Phase 手順

### Phase 1: 前提確認・検出戦略の宣言

- **Step 1** — `<docs_root>/画面一覧/画面一覧.html` の実在を確認する。不在ならハード停止する。この場合 `generating-screen-list-for-reverse-docs` の先行実行を案内して終了する。完了条件: 実在確認済み、または不在を報告して停止している
- **Step 2** — 画面一覧.html 内の `<script type="application/json" id="screen-manifest">` を抽出する。`screens[]` の件数・`route` の値が空文字列の画面の件数を確認する（`validate-manifest.sh` は `route` キー自体の欠落を許さないため、実際に起こるのは空文字）。完了条件: `screens[]` 件数と route 空文字件数が確定済み
- **Step 3** — `target_repo_path` の定義ファイル（`package.json` の依存関係・import 文の形跡）から Router 種別を判別する。候補は React Router・Next.js App Router・Next.js Pages Router・Vue Router 等。完了条件: Router 種別が特定済み、または特定不能の根拠（推定経路）が記録済み
- **Step 4** — 検出戦略宣言を作成する。内容は `routerKind`・抽出対象 API（`navigate`・`<Link>`・`redirect` 等のうち実在するもの）・confidence 判定基準の 3 点。AskUserQuestion で承認を取り、宣言 JSON は一時ファイルに保存する。完了条件: 戦略 JSON が保存済みかつユーザー承認済み

### Phase 2: 抽出

- **Step 1** — `screens[]` から、`kind` が `route` または `embedded-view` で `route` が空文字列でない画面を選ぶ。選んだ画面を `nodes[]` へ転記する（`unitKey` = `screenKey`、`label` = `screenNameGuess`）。`route` が空文字列の画面は `nodes[]` に含めない。代わりに `unresolved[]` へ、理由「routeが空文字列のため遷移解決不能」を添えて登録する。完了条件: `nodes[]` と route 空文字画面の `unresolved[]` 登録が確定済み
- **Step 2** — Phase 1 で宣言した戦略に沿って、Router 定義・`navigate()`・`<Link>`・`redirect` を Grep/Read で走査する。走査対象から遷移候補を洗い出す。各候補には `from`（発生元画面の `unitKey`）・`to`（遷移先 route）・`trigger`（契機）・`sourceRef`（file:line）・`confidence` の 5 項目を記録する。完了条件: 遷移候補一覧が確定済み
  - **`section`**: sourceRef の行を含む最も近い親セクション要素から推定する。探索優先順位: (1) `<section>`/`<article>` 内の直近の見出し（h2〜h4）テキスト (2) `<nav>` の aria-label 属性値 (3) `<form>` の legend テキストまたは直前の見出し (4) 直近の祖先 `<div>` のクラス名から意味を推定。いずれにも該当しない場合は省略する
  - **`triggerType`**: 要素の種類から判定する。`<a>`/`<Link>`/`router-link` → 「リンク遷移」、`<form>` submit/`<button type="submit">` → 「フォーム送信」、`redirect()`/`navigate()`/`router.push()` → 「リダイレクト」、上記以外 → 省略（テンプレート側で「リンク遷移」にフォールバック）
- **Step 3** — 各候補の `to`（route 文字列）を `nodes[]` 転記元の `route` 値と突合し `unitKey` へ解決する。解決できた候補は `from`/`to` を `unitKey` に置き換え `edges[]` へ追加する。解決できない候補（動的セグメント不一致・外部 URL・存在しない route）は `edges[]` に含めない。代わりに `unresolved[]` へ `{label: "<sourceRef> の遷移", reason: "宛先未解決", sourceRef}` として登録する。完了条件: `edges[]` が全件解決済みで確定している
- **Step 4** — page-data.json を組み立てる。`pageKind: "transition"`、`legend[]`（凡例。空配列可）、`nodes[]`、`edges[]`、`unresolved[]` を埋める。完了条件: page-data.json を一時ディレクトリへ保存済み

page-data.json の保存先は `$CLAUDE_JOB_DIR/tmp/screen-transition-page-data.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

### Phase 3: 整合検証（機械実行）

- **Step 1** — 整合検証スクリプトを実行する。`edges[].from`/`.to` が `nodes[].unitKey` に実在するかの孤児参照検査を含め、`validate-page-data.sh` が機械実行する（手動 jq 突合は不要）。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/detail-pages/validate-page-data.sh <page-data.json> --target-repo <target_repo_path>
  ```

- **Step 2** — Step 1 が FAIL したら `[FAIL]` 項目名で分岐する。「孤児参照」FAIL の場合は該当 edge を `edges[]` から外し `unresolved[]` へ差し戻して Phase 2 Step 3 へ戻る。その他の FAIL（`sourceRef` 実在等）は該当箇所を修正し Step 1 を再実行する。3 回失敗したら Phase 2 Step 4（page-data 組み立て）へ差し戻す。完了条件: `validate-page-data.sh` が exit 0（孤児参照検査を含め全項目 PASS）

### Phase 4: 画面遷移図.html 生成

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<docs_root>/画面遷移図.html` が生成済み

  ```
  ../../../shared/scripts/detail-pages/build-detail-page.sh <page-data.json> <docs_root> --page transition
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定（ポータル未生成環境）なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../shared/scripts/build-portal.sh <target_repo_path> <docs_root> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-detail-page.sh` 経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 画面一覧.html の実在確認済み（または不在を報告して停止）。Router 種別と検出戦略がユーザー承認済み |
| Phase 2 | `nodes[]`／`edges[]` が確定し page-data.json を保存済み。route 空文字画面・宛先未解決の遷移は `unresolved[]` へ隔離済み |
| Phase 3 | `validate-page-data.sh --target-repo` が全項目 PASS（孤児参照検査含む） |
| Phase 4 | `<docs_root>/画面遷移図.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | 画面一覧マニフェストとコードの実測から解決できた遷移のみから画面遷移図.html が生成され、route空文字画面・宛先未解決の遷移は捏造せず可視化されている |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（画面一覧.html 不在）\| `ERROR` |
| artifacts | 生成した画面遷移図.html のパス（`STOPPED`/`ERROR` 時は空） |
| page_kind | `transition`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由（不在パス）、route空文字画面・宛先未解決件数、または次工程への申し送り |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復対象 | Phase 3 Step 1 が FAIL → Step 2 の分岐（孤児参照は Phase 2 Step 3、その他はその場）で修正して再実行 |
| 上限回数 | 3 回 |
| 収束停止 | `validate-page-data.sh` が exit 0（孤児参照検査含め全項目 PASS） |
| 発散検知 | 同一検査項目の同一 FAIL が 2 回連続で再発した場合は即座に Phase 2 Step 4 へ差し戻す |
| リソース上限 | 3 回失敗で Phase 2 Step 4（page-data 組み立て）へ差し戻す |

## 重要な注意事項

- 判定・評価はしない。画面設計の良否・遷移の妥当性には一切踏み込まず、コードの実測から解決できた遷移のみを転記する
- 宛先未解決の遷移を AskUserQuestion で手動確定しない。route 文字列とコードのどちらかを即興で正としない
- Phase 4 の HTML 手作業組み立てを禁止する。`build-detail-page.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `docs_root` 配下の画面遷移図.html のみ

## テンプレート/コード分析時の注意

対象リポジトリのソースファイルが非UTF-8のレガシーエンコーディング（日本語の2バイト系文字コード等）で記述されている場合、GNU grep はこれらをバイナリファイルとして扱い、一致行があっても無出力で終了する。テンプレートやハンドラコードに対する全ての grep 呼び出しに `-a`（`--text`）フラグを付与すること。

## 予想を裏切る挙動

- 出力先は `<docs_root>` 直下（画面一覧のような種別専用フォルダは作らない）。`build-detail-page.sh` の `--page transition` 固定出力名仕様に従う
- page-data の `nodes[]` は `{unitKey, label}` のみを持つ。`route` は Phase 2 の解決処理でのみ使う一時情報であり、page-data には持ち込まない
- `route` が空文字列の画面（`validate-manifest.sh` は `route` キー自体の欠落を許さないため、実際に起こるのは空文字）は `nodes[]` から除外される。除外された画面は遷移の起点・終点のいずれにもならない。当該画面が絡む遷移候補は自動的に宛先未解決として `unresolved[]` に落ちる
- `portal_output_dir` 未指定時は `build-portal.sh` を実行しない。生成済み画面遷移図.html はそのまま残り、次回ポータル生成時に自動でカード化される

## 設計判断

### validate-page-data.sh / build-detail-page.sh の共用

**必要性**: page-data.json の整合検証と HTML 生成は pageKind 非依存の決定的処理であり、5 種別（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順）に共通する。`shared/scripts/detail-pages/` の単一実装を全種別スキルが相対パスで共用することで、スキーマ変更時の同期漏れを防ぐ。

**代替案を採用しなかった理由**:
- スキルフォルダ内への複製: スキーマ変更時に種別数ぶんの同期漏れリスクが生じる
- Claude 手作業での HTML 組み立て: 検証なしのデータ混入（テーブル一覧系での `entryFile=None` 混入実害）が再発する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: page-data.json のスキーマ、または画面遷移図.html の形式が廃止された時

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-page-data.sh` の PASS/FAIL 行と孤児 edge 件数を追加する。

## 参照資料

- `../../../shared/scripts/detail-pages/page-data-schema.md` — page-data.json のスキーマ定義（T4: transition 節）
- `references/transition-detection.md` — Router 種別ごとの検出戦略ガイダンス
- `references/generating-screen-transition-for-reverse-docs-guide.html` — スキルガイド
