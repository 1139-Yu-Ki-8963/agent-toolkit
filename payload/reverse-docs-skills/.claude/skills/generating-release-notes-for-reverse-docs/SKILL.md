---
name: generating-release-notes-for-reverse-docs
description: |
  対象リポジトリの git log からリリースノート HTML を生成する。
  TRIGGER when: 「リリースノートを生成」「変更履歴を出力」と言われた時、orchestrating-reverse-docs-flow の「基盤ページ未生成（任意）」状態キーから起動された時。
  SKIP: git 履歴がないリポジトリ、リリースノートが既に docs_root に存在する時。
invocation: generating-release-notes-for-reverse-docs
type: transform
allowed-tools: [Read, Bash, Write, Edit, Grep, Glob]
---

# リリースノートページ生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの将来ページ受け口のうちリリースノート（基盤ページ・任意）のみを担い、単独起動できる（起動引数を渡せば動く）。

対象リポジトリの `git log` から全コミットを取得し、コミットメッセージから変更種別（機能追加・修正・その他）を機械的に判定したうえで日付ごとにグルーピングし、**リリースノート.html** として書き出す。**本スキルは判定・評価を一切行わない**。コミットメッセージ文字列からの分類ルールに徹し、変更内容の良否・重要度は判定しない。

## 使用タイミング

- git 履歴が存在するリポジトリで、ポータルにリリースノートページを追加したいとき
- 起動引数: `target_repo_path`（対象リポジトリの絶対パス）・`docs_root`（出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<docs_root>/リリースノート.html` に固定する（想定値。エンジン側の対応状況は「重要な注意事項」を参照）。

## 設計原則

- **転記のみ** — 変更内容の重要度・品質は判定しない。`git log` から機械的に取得できる事実（コミットハッシュ・日時・作成者・件名）のみを転記する
- **分類は文字列パターンのみ** — 変更種別（機能追加/修正/その他）はコミットメッセージ先頭の日本語角括弧プレフィックス（例: `【機能追加】` `【バグ修正】` `【リファクタ】`）または既定のキーワード一致で機械判定する。曖昧な場合は「その他」に分類し、恣意的な判断を行わない
- **固定と可変の分離** — 整合検証（`validate-page-data.sh`）と HTML 生成（`build-detail-page.sh`）は決定的スクリプトに固定する。抽出（`git log` の取得・分類・グルーピング）は Claude 自身が Bash で行う

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。`build-detail-page.sh` は既存 5 種別（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順）と共用する想定だが、`release-notes` はエンジン未対応（詳細は「重要な注意事項」）。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| 整合検証 | `../../../shared/scripts/detail-pages/validate-page-data.sh` |
| HTML生成 | `../../../shared/scripts/detail-pages/build-detail-page.sh` |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

## Phase 手順

### Phase 1: git log 取得

- **Step 1** — `target_repo_path` が git 管理下であることを確認する。不在・非 git ならハード停止する。完了条件: git リポジトリであることを確認済み、または不在を報告して停止している
- **Step 2** — 以下のコマンドで全コミットを取得する。完了条件: 全コミットの一覧（ハッシュ・日時・作成者・件名）を取得済み

  ```
  git -C <target_repo_path> log --format='%H|%ai|%an|%s'
  ```

- **Step 3** — Step 2 の出力が 0 件の場合、page-data を生成せずユーザーへ「git 履歴が空」を報告して停止する。完了条件: 1 件以上のコミットを確認済み、または空であることを報告して停止している

### Phase 2: 分類・グルーピング・page-data 構築

- **Step 1** — 各コミットの件名（`%s`）を判定する。先頭の日本語角括弧プレフィックスまたはキーワード一致で「機能追加」「修正」「その他」のいずれかに分類する。完了条件: 全コミットの変更種別が確定済み
- **Step 2** — コミット日時（`%ai` の日付部分）でグルーピングする。同日内は時系列順（新しい順）で並べる。完了条件: 日付ごとのコミット一覧が確定済み
- **Step 3** — page-data.json を組み立てる。`pageKind: "release-notes"`、日付グループごとの要約とコミット明細（ハッシュ・作成者・件名・変更種別・sourceRef）を埋める。sourceRef はコミットハッシュ（例: `<hash>`）とする。完了条件: page-data.json を一時ディレクトリへ保存済み

page-data.json の保存先は `$CLAUDE_JOB_DIR/tmp/release-notes-page-data.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

### Phase 3: 整合検証（機械実行）

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/detail-pages/validate-page-data.sh <page-data.json> --target-repo <target_repo_path>
  ```

- **Step 2** — FAIL 時は該当項目を修正し Step 1 を再実行する。3 回失敗したら Phase 2 Step 3（page-data 組み立て）へ差し戻す。完了条件: exit 0

### Phase 4: リリースノート.html 生成

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<docs_root>/リリースノート.html` が生成済み

  ```
  ../../../shared/scripts/detail-pages/build-detail-page.sh <page-data.json> <docs_root> --page release-notes
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定（ポータル未生成環境）なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../shared/scripts/build-portal.sh <target_repo_path> <docs_root> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-detail-page.sh` 経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 1 件以上のコミットを取得済み、または git 履歴が空であることを報告して停止している |
| Phase 2 | 全コミットの分類・グルーピングを終え page-data.json を保存済み |
| Phase 3 | `validate-page-data.sh --target-repo` が全項目 PASS |
| Phase 4 | `<docs_root>/リリースノート.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | git log の全コミットが変更種別・日付で機械分類され、リリースノート.html として生成されている（または履歴なしを報告して停止している） |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（git 履歴なし・非 git リポジトリ）\| `ERROR` |
| artifacts | 生成したリリースノート.html のパス（`STOPPED`/`ERROR` 時は空） |
| page_kind | `release-notes`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由（git 履歴なし等）、または次工程への申し送り |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復対象 | Phase 3 Step 1 が FAIL → Step 2 で修正して再実行 |
| 上限回数 | 3 回 |
| 収束停止 | `validate-page-data.sh` が exit 0 |
| 発散検知 | 同一検査項目の同一 FAIL が 2 回連続で再発した場合は即座に Phase 2 Step 3 へ差し戻す |
| リソース上限 | 3 回失敗で Phase 2 Step 3（page-data 組み立て）へ差し戻す |

## 重要な注意事項

- **エンジン未対応（前提条件）**: 本スキルが依存する共用エンジン（`build-detail-page.sh` の `get_page_template`/`get_page_filename`、`page-data-schema.md` の `pageKind` 列挙、`build-portal.sh` の `FUTURE_FILES`）は現時点で `glossary`/`techstack`/`transition`/`er`/`env` の 5 種別のみに対応しており、`release-notes` は含まれていない。エンジン側に `release-notes` 用の対応（テンプレート追加・固定出力ファイル名の登録・スキーマ拡張）が入るまで、本スキルの Phase 3・Phase 4 は実行時エラーになる。エンジン拡張は本スキルのスコープ外であり、別途対応が必要
- git log が空（Phase 1 Step 3 で 0 件）の場合は STOPPED を返す
- 判定・評価はしない。変更内容の重要度・品質には一切踏み込まず、コミットメッセージのプレフィックス/キーワード一致による機械分類のみを行う
- 分類が曖昧な場合に AskUserQuestion で手動分類を聞き出さない。判定不能なものは常に「その他」に分類する
- Phase 4 の HTML 手作業組み立てを禁止する。`build-detail-page.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `docs_root` 配下のリリースノート.html のみ

## 予想を裏切る挙動

- 出力先は `<docs_root>` 直下（`テーブル一覧.html` のような種別専用フォルダは作らない）想定。ただし固定出力ファイル名 `リリースノート.html` は `build-detail-page.sh` の `get_page_filename` にまだ登録されておらず、エンジン拡張後に確定する
- `sourceRef` は他 5 種別のようなファイルパスではなく、コミットハッシュを使う。`validate-page-data.sh` の実在検査（`test -f`）はファイルパス形式を前提とするため、コミットハッシュ形式の sourceRef を実在検査対象外として扱うスキーマ拡張がエンジン側に必要になる
- `portal_output_dir` 未指定時は `build-portal.sh` を実行しない。生成済みリリースノート.html はそのまま残り、次回ポータル生成時に自動でカード化される想定

## 設計判断

### validate-page-data.sh / build-detail-page.sh の共用（前提: エンジン拡張待ち）

**必要性**: page-data.json の整合検証と HTML 生成は pageKind 非依存の決定的処理であり、既存 5 種別（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順）に共通する。本スキルもこの枠組みに 6 番目の種別として乗る設計とし、`shared/scripts/detail-pages/` の単一実装をそのまま共用することで、スキーマ変更時の同期漏れを防ぐ。ただし現時点でエンジン側は `release-notes` を認識しないため、本スキルは非稼働の状態でスキル定義のみ先行する。

**代替案を採用しなかった理由**:
- スキル専用の生成スクリプトを新設: pageKind 数だけ検証・生成ロジックが分岐し、他 5 種別との保守コストが二重化する
- Claude 手作業での HTML 組み立て: 検証なしのデータ混入が再発する

**保守責任者**: 人手（ユーザー）。`build-detail-page.sh` / `page-data-schema.md` / `build-portal.sh` へ `release-notes` 対応を追加する作業は本スキルのスコープ外であり、別途実施する

**廃棄条件**: page-data.json のスキーマ、またはリリースノート.html の形式が廃止された時

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-page-data.sh` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../shared/scripts/detail-pages/page-data-schema.md` — page-data.json のスキーマ定義（`release-notes` 型別スロットは未収録。エンジン拡張時に追記が必要）
- `references/generating-release-notes-for-reverse-docs-guide.html` — スキルガイド
