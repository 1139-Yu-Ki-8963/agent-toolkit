---
name: generating-release-notes-for-reverse-docs
description: |
  対象リポジトリの git log からリリースノート HTML を生成する。
  TRIGGER when: 「リリースノートを生成」「変更履歴を出力」と言われた時、orchestrating-reverse-docs-flow の「基盤ページ未生成（任意）」状態キーから起動された時。
  SKIP: git 履歴がないリポジトリ、リリースノートが既に docs_root に存在する時。
invocation: generating-release-notes-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Grep, Glob]
---

# リリースノートページ生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの将来ページ受け口のうちリリースノート（release-notes）のみを担い、単独起動できる（起動引数を渡せば動く）。

対象リポジトリの `git log` を単一の事実源としつつ、コミットを日付単位でグルーピングし、コミットメッセージから変更種別（機能追加・修正・改善・その他）を判定してリリースノートを組み立てる。**本スキルは判定・評価を一切行わない**。コミットメッセージに記載された事実の転記に徹し、種別判定は文言パターンからの機械的な分類に留める。

## 使用タイミング

- 対象リポジトリに git 履歴があり、ポータルにリリースノートカードを追加したいとき
- 起動引数: `target_repo_path`（調査対象リポジトリの絶対パス）・`docs_root`（調査書の所在かつ出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<docs_root>/リリースノート.html` に固定する（`build-portal.sh` の `FUTURE_FILES` と同値）。

## 設計原則

- **転記のみ** — コミットメッセージの内容の良否・粒度の妥当性は判定しない。`git log` に記録された事実（日時・メッセージ・種別分類）のみを転記する
- **種別判定は機械的パターンのみ** — コミットメッセージの日本語角括弧プレフィックス（例: `【機能追加】` `【バグ修正】` `【改善】`）または先頭語からの文字列パターンマッチで種別を判定する。プレフィックスがなく判定できないものは「その他」に分類し、恣意的な解釈を行わない
- **固定と可変の分離** — 整合検証（`validate-page-data.sh`）と HTML 生成（`build-detail-page.sh`）は決定的スクリプトに固定する。抽出（`git log` の取得・日付グルーピング・種別判定）は Claude 自身が Bash/Read/Grep で行う

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| 整合検証 | `../../../shared/scripts/detail-pages/validate-page-data.sh` |
| HTML生成 | `../../../shared/scripts/detail-pages/build-detail-page.sh` |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

## Phase 手順

### Phase 1: git log 全件取得

- **Step 1** — `target_repo_path` が git リポジトリであることを確認する。`.git` が存在しなければハード停止する。この場合 git 履歴を持たないリポジトリである旨を報告して終了する。完了条件: git リポジトリの実在確認済み、または不在を報告して停止している
- **Step 2** — `git -C <target_repo_path> log --date=short --pretty=format:'%H%x1f%ad%x1f%s'` で全コミットのハッシュ・日付・件名を取得する。完了条件: 全コミットの一覧が確定済み

### Phase 2: 日付グルーピング + 変更種別判定

- **Step 1** — Phase 1 Step 2 で取得した全コミットを `ad`（日付）でグルーピングする。完了条件: 日付単位のコミット群が確定済み
- **Step 2** — 各コミットの件名を先頭の日本語角括弧プレフィックスで走査し、変更種別（機能追加・バグ修正・改善・その他）を判定する。プレフィックスが無い、またはプレフィックス対応表に無い件名は「その他」に分類する。完了条件: 全コミットの種別分類が確定済み
- **Step 3** — 日付グループごとに、コミット一覧（ハッシュ・件名・種別）を要約したエントリを組み立て、page-data.json を構築する。`pageKind: "release-notes"`、`tiles[]`（直近の変更種別内訳などの要約タイル）を埋める。`rows[]`（`{item, value, sourceRef}`。`item` は日付、`value` は当日のコミット件名一覧、`sourceRef` はコミットハッシュ）も埋める。完了条件: page-data.json を一時ディレクトリへ保存済み

page-data.json の保存先は `$CLAUDE_JOB_DIR/tmp/release-notes-page-data.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

### Phase 3: 整合検証（機械実行）

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/detail-pages/validate-page-data.sh <page-data.json> --target-repo <target_repo_path>
  ```

- **Step 2** — FAIL 時は `sourceRef` を修正し Step 1 を再実行する。3 回失敗したら Phase 2 Step 3（page-data 組み立て）へ差し戻す。完了条件: exit 0

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
| Phase 1 | git リポジトリの実在確認済み、または不在を報告して停止している |
| Phase 2 | 全コミットの日付グルーピング・種別分類を終え page-data.json を保存済み |
| Phase 3 | `validate-page-data.sh --target-repo` が全項目 PASS |
| Phase 4 | `<docs_root>/リリースノート.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | git log の事実のみからリリースノート.html が生成され、種別判定不能なコミットは「その他」として捏造なく分類されている |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（git 履歴不在）\| `ERROR` |
| artifacts | 生成したリリースノート.html のパス（`STOPPED`/`ERROR` 時は空） |
| page_kind | `release-notes`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由（git 履歴不在）、または次工程への申し送り |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復対象 | Phase 3 Step 1 が FAIL → Step 2 で修正して再実行 |
| 上限回数 | 3 回 |
| 収束停止 | `validate-page-data.sh` が exit 0 |
| 発散検知 | 同一検査項目の同一 FAIL が 2 回連続で再発した場合は即座に Phase 2 Step 3 へ差し戻す |
| リソース上限 | 3 回失敗で Phase 2 Step 3（page-data 組み立て）へ差し戻す |

## 重要な注意事項

- 判定・評価はしない。コミット内容の良否・粒度の妥当性には一切踏み込まず、`git log` の事実とプレフィックスパターンからの機械的な種別分類のみを行う
- 種別判定不能時に AskUserQuestion で手動分類を聞き出さない。プレフィックス対応表にない件名は即座に「その他」へ分類する
- Phase 4 の HTML 手作業組み立てを禁止する。`build-detail-page.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `docs_root` 配下のリリースノート.html のみ

## 予想を裏切る挙動

- 出力先は `<docs_root>` 直下（種別専用フォルダは作らない）。`build-detail-page.sh` の `--page release-notes` 固定出力名仕様に従う
- `rows[]` の `sourceRef` はコミットハッシュを使う。ファイルパス形式ではなく、`git log` が一次ソースであることを明示する
- `portal_output_dir` 未指定時は `build-portal.sh` を実行しない。生成済みリリースノート.html はそのまま残り、次回ポータル生成時に自動でカード化される

## 設計判断

### validate-page-data.sh / build-detail-page.sh の共用

**必要性**: page-data.json の整合検証と HTML 生成は pageKind 非依存の決定的処理であり、既存 5 種別（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順）に共通する。`shared/scripts/detail-pages/` の単一実装をリリースノートも含め共用することで、スキーマ変更時の同期漏れを防ぐ。

**代替案を採用しなかった理由**:
- スキルフォルダ内への複製: スキーマ変更時に種別数ぶんの同期漏れリスクが生じる
- Claude 手作業での HTML 組み立て: 検証なしのデータ混入が再発する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: page-data.json のスキーマ、またはリリースノート.html の形式が廃止された時

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-page-data.sh` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../shared/scripts/detail-pages/page-data-schema.md` — page-data.json のスキーマ定義
- `references/generating-release-notes-for-reverse-docs-guide.html` — スキルガイド
