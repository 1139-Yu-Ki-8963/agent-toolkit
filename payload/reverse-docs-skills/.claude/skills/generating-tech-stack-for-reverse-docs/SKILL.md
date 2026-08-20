---
name: generating-tech-stack-for-reverse-docs
日本語名: 技術スタックの書き出し
description: "調査書の記載と定義ファイルの実測値を突き合わせ、技術スタックのページを機械的に作る。"
invocation: generating-tech-stack-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write]
---

## いつ使うか

仕組みを調べた調査書が確定していて、使っている技術の一覧のページを追加したいとき。

## いつ使わないか

仕組みを調べた調査書そのものを作るとき、他の種類の詳細ページを作るとき。

# 正本: reverse-docs-skills

# 技術スタックページ生成スキル

工程全体は orchestrating-ai-development-setup が案内する。本スキルはポータルの将来ページ受け口のうち技術スタック（T3）のみを担い、単独起動できる（起動引数を渡せば動く）。

アーキテクチャ調査書 §2 の技術スタック表を定義としつつ、対象リポジトリの定義ファイル（`package.json` 等）の実測値と突合する。一致を確認できた項目だけを **技術スタック.html** として書き出す。**本スキルは判定・評価を一切行わない**。事実の転記に徹し、調査書と実測値が食い違う項目は生成せず停止報告する。

## 使用タイミング

- アーキテクチャ調査書が確定済みで、ポータルに技術スタックカードを追加したいとき
- 起動引数: `target_repo_path`（調査対象リポジトリの絶対パス）・`output_dir`（調査書の所在かつ出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

HTML出力先は`<output_dir>/project-portal/foundation/技術スタック.html`、再生成入力は
`<output_dir>/<manifestsRoot>/detail-pages/techstack-page-data.json`に固定する。

## 設計原則

- **転記のみ** — 技術選定の良否・妥当性は判定しない。調査書と定義ファイルの実測値が一致した項目のみを転記する
- **乖離は捏造せず停止** — 調査書記載値と定義ファイル実測値が食い違う場合、page-data を生成せずユーザーへ報告して停止する
- **固定と可変の分離** — 整合検証（`validate-page-data.sh`）と HTML 生成（`build-detail-page.sh`）は決定的スクリプトに固定する。抽出（§2 表の読取・定義ファイルの実測）は Claude 自身が Bash/Read/Grep で行う

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| 整合検証 | `../../../generation-engine/scripts/detail-pages/validate-page-data.sh` |
| HTML生成 | `../../../generation-engine/scripts/detail-pages/build-detail-page.sh` |
| ポータル再生成（任意） | `../../../generation-engine/scripts/build-portal.sh` |
| 出力配置解決 | `../../../generation-engine/scripts/output-layout.sh` |

## 実行手順

## Phase 1: データ源読込

## Step 1-1: データ源読込

**使用ツール**: Read / Write

- **Step 1** — `<output_dir>/<commonRoot>/アーキテクチャ調査書.md`（`commonRoot` は output-layout の物理配置キー）の実在を確認する。不在ならハード停止する。この場合 `surveying-architecture-for-reverse-docs` の先行実行を案内して終了する。完了条件: 調査書の実在確認済み、または不在を報告して停止している
- **Step 2** — `target_repo_path` 直下の定義ファイルを列挙する。対象は `package.json`／`requirements.txt`／`pyproject.toml`／`go.mod` 等のうち実在するもののみ。完了条件: 実在する定義ファイルのパス一覧が確定済み

**完了**: 調査書の実在確認済み、または不在を報告して停止している

## Phase 2: 抽出・突合

## Step 2-1: 抽出・突合

**使用ツール**: Read / Bash / Write

- **Step 1** — 調査書 §2 技術スタック表（言語・ランタイム／フレームワーク／パッケージマネージャ／ルーティングライブラリ）の記載値をそのまま読み込む。各行を「実在する」（判定値が具体的な技術名）と「実在しない（理由: …）」の 2 群に分ける。完了条件: §2 表の全行が 2 群いずれかへ分類済み
- **Step 2** — 「実在する」群のみを対象に、Phase 1 Step 2 の定義ファイルを読み、項目ごとの実測値（実バージョン・実パッケージ名）を確認し調査書記載値と突合する。「実在しない」群は突合対象外（定義ファイルに対応物が無いため照合しようがない）。完了条件: 「実在する」群の項目ごとに一致／乖離が判定済み
- **Step 3** — 「実在する」群で乖離を 1 件でも検出したら page-data を生成せず、乖離内容（項目・調査書記載値・定義ファイル実測値）をユーザーへ報告して停止する。完了条件: 「実在する」群の全項目一致を確認済み、または乖離を報告して停止している
- **Step 4** — 「実在する」群の全項目一致を確認できたら page-data.json を組み立てる。`pageKind: "techstack"`、`tiles[]`（領域別代表 4 枠以内の要約タイル）を埋める。`rows[]`（`{item, value, sourceRef}`。`sourceRef` は定義ファイルの実パス）に「実在する」群を埋める。`absentRows[]`（`{item, value, sourceRef}`。`value` は調査書の「実在しない（理由: …）」の理由文をそのまま、`sourceRef` は調査書 §2 の当該行の根拠パス）に「実在しない」群を埋める（1-132: 根拠パスを保持したまま成果物へ残す。捏造ではなく調査書の記載事実そのものの転記）。`description` は一致を確認できた項目と実在しないと判定された項目の両方を扱う旨で書く（一致項目のみを転記した記録である、のような限定表現は使わない）。完了条件: 検証候補のpage-data.jsonを一時保存済み

検証候補は`$CLAUDE_JOB_DIR/tmp/tech-stack-page-data.json`へ保存する。未設定時は
`${TMPDIR:-/tmp}/claude-job-${session}/tmp/`配下に置く。未検証の候補を再生成用の正規配置へ置かない。

**完了**: 全項目一致を確認して page-data.json を保存済み、または乖離を報告して停止している

## Phase 3: 整合検証（機械実行）

## Step 3-1: 整合検証（機械実行）

**使用ツール**: Bash

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../generation-engine/scripts/detail-pages/validate-page-data.sh <page-data.json> --target-repo <target_repo_path>
  ```

- **Step 2** — FAIL 時は `sourceRef` を修正し Step 1 を再実行する。3 回失敗したら Phase 2 Step 4（page-data 組み立て）へ差し戻す。完了条件: exit 0

- **Step 3** — PASSした候補だけを永続化する。`output-layout.sh`で`manifestsRoot`を解決し、`<output_dir>/<manifestsRoot>/detail-pages/techstack-page-data.json`へ保存する。完了条件: 検証済みpage-dataが再生成用の正規配置に存在する

**完了**: `validate-page-data.sh --target-repo` が全項目 PASS

## Phase 4: 技術スタック.html 生成

## Step 4-1: 技術スタック.html 生成

**使用ツール**: Bash / Write

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<output_dir>/project-portal/foundation/技術スタック.html` が生成済み

  ```
  ../../../generation-engine/scripts/detail-pages/build-detail-page.sh <page-data.json> <output_dir>/project-portal/foundation --page techstack
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定（ポータル未生成環境）なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../generation-engine/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-detail-page.sh` 経由の決定的処理で行う。

**完了**: `<output_dir>/project-portal/foundation/技術スタック.html` が生成され、指定時は `build-portal.sh` の再実行が完了している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 調査書の実在確認済み、または不在を報告して停止している |
| Phase 2 | 「実在する」群の全項目一致を確認し、「実在しない」群を根拠付きで absentRows[] へ分離して検証候補を保存済み、または乖離を報告して停止している |
| Phase 3 | `validate-page-data.sh --target-repo` が全項目PASSし、検証済みpage-dataを再生成用の正規配置へ保存済み |
| Phase 4 | `<output_dir>/project-portal/foundation/技術スタック.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | 調査書と定義ファイルの実測値が完全一致する項目はrows[]へ、実在しない項目は根拠付きabsentRows[]へ残り、検証済みpage-dataから技術スタック.htmlを再生成できる。乖離があれば停止報告されている |

## 返却ブロック

本スキルは orchestrating-ai-development-setup の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（調査書不在・乖離検出）\| `ERROR` |
| artifacts | 生成した技術スタック.html と`techstack-page-data.json`のパス（`STOPPED`/`ERROR` 時は空） |
| page_kind | `techstack`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由（乖離内容・不在パス）、または次工程への申し送り |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復対象 | Phase 3 Step 1 が FAIL → Step 2 で修正して再実行 |
| 上限回数 | 3 回 |
| 収束停止 | `validate-page-data.sh` が exit 0 |
| 発散検知 | 同一検査項目の同一 FAIL が 2 回連続で再発した場合は即座に Phase 2 Step 4 へ差し戻す |
| リソース上限 | 3 回失敗で Phase 2 Step 4（page-data 組み立て）へ差し戻す |

## 重要な注意事項

- 判定・評価はしない。技術選定の良否・妥当性・推奨事項には一切踏み込まず、調査書と定義ファイルの一致事実のみを転記する
- 乖離検出時に AskUserQuestion で手動値を聞き出さない。調査書または定義ファイルのどちらかを即興で正としない
- Phase 4 の HTML 手作業組み立てを禁止する。`build-detail-page.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は`output_dir`配下の`project-portal/foundation/技術スタック.html`と検証済みpage-dataのみ

## 予想を裏切る挙動

- 出力先は `<output_dir>/project-portal/foundation` 直下（`テーブル一覧.html` のような種別専用フォルダは作らない）。`build-detail-page.sh` の `--page techstack` 固定出力名仕様に従う
- `rows[]` の `sourceRef` は文書参照形式（`アーキテクチャ調査書.md#§2`）ではなく、突合に使った定義ファイルの実パスを使う。文書参照形式は `validate-page-data.sh` の実在検査対象外になり検証精度が落ちるため
- 調査書の記載値が「実在しない（理由: …）」の項目は突合対象外とし `rows[]` には含めないが、`absentRows[]` へ根拠パス（調査書 §2 の当該行）を保持したまま記録する（1-132）。存在しない技術を「ある」と転記するわけではなく、調査書が既に記録した「無い」という事実とその根拠を成果物からも追跡できるようにするための記録である
- `portal_output_dir`未指定時は`build-portal.sh`を実行しない。永続化したpage-dataは次回の通常ポータル生成で読み取られ、技術スタック.htmlが再生成される

## 設計判断

### validate-page-data.sh / build-detail-page.sh の共用

**必要性**: page-data.json の整合検証と HTML 生成は pageKind 非依存の決定的処理であり、5 種別（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順）に共通する。`generation-engine/scripts/detail-pages/` の単一実装を全種別スキルが相対パスで共用することで、スキーマ変更時の同期漏れを防ぐ。

**代替案を採用しなかった理由**:
- スキルフォルダ内への複製: スキーマ変更時に種別数ぶんの同期漏れリスクが生じる
- Claude 手作業での HTML 組み立て: 検証なしのデータ混入（テーブル一覧系での `entryFile=None` 混入実害）が再発する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: page-data.json のスキーマ、または技術スタック.html の形式が廃止された時

## 完了報告

`../../../delivery-payload/references/完了報告の書き方.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-page-data.sh` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../generation-engine/scripts/detail-pages/page-data-schema.md` — page-data.json のスキーマ定義
- `references/guide.html` — スキルガイド
