---
name: generating-tech-stack-for-reverse-docs
description: "技術スタック.html を調査書と定義ファイルの実測突合から機械生成する。 TRIGGER when: 技術スタックページ生成、tech stack HTML作成。 SKIP: アーキテクチャ調査書自体の作成（→surveying-architecture-for-reverse-docs）、他種別詳細ページ生成。"
invocation: generating-tech-stack-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Grep, Glob]
---

# 技術スタックページ生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの将来ページ受け口のうち技術スタック（T3）のみを担い、単独起動できる（起動引数を渡せば動く）。

アーキテクチャ調査書 §2 の技術スタック表を定義としつつ、対象リポジトリの定義ファイル（`package.json` 等）の実測値と突合する。一致を確認できた項目だけを **技術スタック.html** として書き出す。**本スキルは判定・評価を一切行わない**。事実の転記に徹し、調査書と実測値が食い違う項目は生成せず停止報告する。

## 使用タイミング

- アーキテクチャ調査書が確定済みで、ポータルに技術スタックカードを追加したいとき
- 起動引数: `target_repo_path`（調査対象リポジトリの絶対パス）・`docs_root`（調査書の所在かつ出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<docs_root>/技術スタック.html` に固定する（`build-portal.sh` の `FUTURE_FILES` と同値）。

## 設計原則

- **転記のみ** — 技術選定の良否・妥当性は判定しない。調査書と定義ファイルの実測値が一致した項目のみを転記する
- **乖離は捏造せず停止** — 調査書記載値と定義ファイル実測値が食い違う場合、page-data を生成せずユーザーへ報告して停止する
- **固定と可変の分離** — 整合検証（`validate-page-data.sh`）と HTML 生成（`build-detail-page.sh`）は決定的スクリプトに固定する。抽出（§2 表の読取・定義ファイルの実測）は Claude 自身が Bash/Read/Grep で行う

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| 整合検証 | `../../../shared/scripts/detail-pages/validate-page-data.sh` |
| HTML生成 | `../../../shared/scripts/detail-pages/build-detail-page.sh` |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

## Phase 手順

### Phase 1: データ源読込

- **Step 1** — `<docs_root>/プロジェクト共通/アーキテクチャ調査書.md` の実在を確認する。不在ならハード停止する。この場合 `surveying-architecture-for-reverse-docs` の先行実行を案内して終了する。完了条件: 調査書の実在確認済み、または不在を報告して停止している
- **Step 2** — `target_repo_path` 直下の定義ファイルを列挙する。対象は `package.json`／`requirements.txt`／`pyproject.toml`／`go.mod` 等のうち実在するもののみ。完了条件: 実在する定義ファイルのパス一覧が確定済み

### Phase 2: 抽出・突合

- **Step 1** — 調査書 §2 技術スタック表（言語・ランタイム／フレームワーク／パッケージマネージャ／ルーティングライブラリ）の記載値をそのまま読み込む。完了条件: §2 表の全行の記載値を転記済み
- **Step 2** — Phase 1 Step 2 の定義ファイルを読み、項目ごとの実測値（実バージョン・実パッケージ名）を確認し調査書記載値と突合する。完了条件: 項目ごとに一致／乖離が判定済み
- **Step 3** — 乖離を 1 件でも検出したら page-data を生成せず、乖離内容（項目・調査書記載値・定義ファイル実測値）をユーザーへ報告して停止する。完了条件: 全項目一致を確認済み、または乖離を報告して停止している
- **Step 4** — 全項目一致を確認できたら page-data.json を組み立てる。`pageKind: "techstack"`、`tiles[]`（領域別代表 4 枠以内の要約タイル）を埋める。`rows[]`（`{item, value, sourceRef}`。`sourceRef` は定義ファイルの実パス）も埋める。完了条件: page-data.json を一時ディレクトリへ保存済み

page-data.json の保存先は `$CLAUDE_JOB_DIR/tmp/tech-stack-page-data.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

### Phase 3: 整合検証（機械実行）

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/detail-pages/validate-page-data.sh <page-data.json> --target-repo <target_repo_path>
  ```

- **Step 2** — FAIL 時は `sourceRef` を修正し Step 1 を再実行する。3 回失敗したら Phase 2 Step 4（page-data 組み立て）へ差し戻す。完了条件: exit 0

### Phase 4: 技術スタック.html 生成

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<docs_root>/技術スタック.html` が生成済み

  ```
  ../../../shared/scripts/detail-pages/build-detail-page.sh <page-data.json> <docs_root> --page techstack
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定（ポータル未生成環境）なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../shared/scripts/build-portal.sh <target_repo_path> <docs_root> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-detail-page.sh` 経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 調査書の実在確認済み、または不在を報告して停止している |
| Phase 2 | 全項目一致を確認して page-data.json を保存済み、または乖離を報告して停止している |
| Phase 3 | `validate-page-data.sh --target-repo` が全項目 PASS |
| Phase 4 | `<docs_root>/技術スタック.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | 調査書と定義ファイルの実測値が完全一致する項目のみから技術スタック.html が生成され、乖離があれば捏造せず停止報告されている |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（調査書不在・乖離検出）\| `ERROR` |
| artifacts | 生成した技術スタック.html のパス（`STOPPED`/`ERROR` 時は空） |
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
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `docs_root` 配下の技術スタック.html のみ

## 予想を裏切る挙動

- 出力先は `<docs_root>` 直下（`テーブル一覧.html` のような種別専用フォルダは作らない）。`build-detail-page.sh` の `--page techstack` 固定出力名仕様に従う
- `rows[]` の `sourceRef` は文書参照形式（`アーキテクチャ調査書.md#§2`）ではなく、突合に使った定義ファイルの実パスを使う。文書参照形式は `validate-page-data.sh` の実在検査対象外になり検証精度が落ちるため
- 調査書の記載値が「実在しない（理由: …）」の項目は突合対象外とし、`rows[]` にも含めない（存在しない技術を転記しない）
- `portal_output_dir` 未指定時は `build-portal.sh` を実行しない。生成済み技術スタック.html はそのまま残り、次回ポータル生成時に自動でカード化される

## 設計判断

### validate-page-data.sh / build-detail-page.sh の共用

**必要性**: page-data.json の整合検証と HTML 生成は pageKind 非依存の決定的処理であり、5 種別（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順）に共通する。`shared/scripts/detail-pages/` の単一実装を全種別スキルが相対パスで共用することで、スキーマ変更時の同期漏れを防ぐ。

**代替案を採用しなかった理由**:
- スキルフォルダ内への複製: スキーマ変更時に種別数ぶんの同期漏れリスクが生じる
- Claude 手作業での HTML 組み立て: 検証なしのデータ混入（テーブル一覧系での `entryFile=None` 混入実害）が再発する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: page-data.json のスキーマ、または技術スタック.html の形式が廃止された時

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-page-data.sh` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../shared/scripts/detail-pages/page-data-schema.md` — page-data.json のスキーマ定義
- `references/generating-tech-stack-for-reverse-docs-guide.html` — スキルガイド
