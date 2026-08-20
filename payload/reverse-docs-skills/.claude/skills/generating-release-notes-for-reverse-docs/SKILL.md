---
name: generating-release-notes-for-reverse-docs
日本語名: 更新履歴のページを作る
description: "対象のコードの変更履歴をもとに、更新内容をまとめたページを作る。"
invocation: generating-release-notes-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write]
---

## いつ使うか

「更新履歴のページを作りたい」「変更内容をまとめたい」と言われたとき、orchestrating-ai-development-setup の基盤ページがまだ無い状態から起動されたとき。

## いつ使わないか

変更履歴を持たない対象のとき、更新履歴のページが既に出力先にあるとき。

# 正本: reverse-docs-skills

# リリースノートページ生成スキル

工程全体は orchestrating-ai-development-setup が案内する。本スキルはポータルの将来ページ受け口のうちリリースノート（release-notes）のみを担い、単独起動できる（起動引数を渡せば動く）。

対象リポジトリの `git log` を単一の事実源としつつ、コミットを日付単位でグルーピングし、コミットメッセージから変更種別（機能追加・修正・改善・その他）を判定してリリースノートを組み立てる。**本スキルは判定・評価を一切行わない**。コミットメッセージに記載された事実の転記に徹し、種別判定は文言パターンからの機械的な分類に留める。

## 使用タイミング

- 対象リポジトリに git 履歴があり、ポータルにリリースノートカードを追加したいとき
- 起動引数: `target_repo_path`（調査対象リポジトリの絶対パス）・`output_dir`（調査書の所在かつ出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<output_dir>/project-portal/foundation/リリースノート.html` に固定する。

## 設計原則

- **転記のみ** — コミットメッセージの内容の良否・粒度の妥当性は判定しない。`git log` に記録された事実（日時・メッセージ・種別分類）のみを転記する
- **種別判定は機械的パターンのみ** — コミットメッセージの日本語角括弧プレフィックス（例: `【機能追加】` `【バグ修正】` `【改善】`）または先頭語からの文字列パターンマッチで、下記「プレフィックス対応表」に従って種別を判定する。対応表に無い件名は「その他」に分類し、恣意的な解釈を行わない
- **固定と可変の分離** — 整合検証（`validate-page-data.sh`）と HTML 生成（`build-detail-page.sh`）は決定的スクリプトに固定する。抽出（`git log` の取得・日付グルーピング・種別判定）は Claude 自身が Bash/Read/Grep で行う

## プレフィックス対応表

コミット件名先頭のプレフィックスから、コミット単位の `changes[].type`（6値）とコミット単位の暫定 `flow`（3値。日付グループへ集約する際の入力となる。集約規則は次節「グループ単位の flow 判定」）を判定する。

`changes[].type` の許容値は `feat` | `fix` | `docs` | `test` | `refactor` | `chore` の6値（定義: `page-data-schema.md` T7）。`flow` の許容値は `feature` | `maintenance` | `docs` の3値（定義: 同 T7・`delivery-payload/templates/detail-pages/detail-t7-release-notes.html` の `FLOW_LABEL`）。日本語プレフィックスは英語 type 10値（feat/fix/docs/chore/refactor/test/style/ci/perf/revert）を下表のとおり網羅し、慣習的な英語プレフィックスも行として加える。対応表に無いプレフィックスは「その他」として `flow=maintenance`・`changes.type=chore` に分類する。

英語 type 10値のうち `changes[].type` の6値に無い `style`・`ci`・`perf`・`revert` は次の理由で6値へ畳み込む。`style`（整形のみで挙動を変えない）と `ci`（CI設定の変更）はいずれも外部から見た挙動を変えない雑務であるため `chore` に畳み込む。`perf`（性能改善）は機能追加でも不具合修正でもなく、外部挙動を変えずに内部実装を変える点で `refactor` の定義に合致するため `refactor` に畳み込む。`revert`（取り消し）は取り消し対象の性質によらず「新たな価値を追加しない後始末の作業」という点で一貫させるため `chore` に畳み込む。

| プレフィックス | flow（3値） | changes.type（6値） |
|---|---|---|
| 【機能追加】 | feature | feat |
| 【バグ修正】 | maintenance | fix |
| 【ドキュメント】 | docs | docs |
| 【設定変更】 | maintenance | chore |
| 【リファクタ】 | maintenance | refactor |
| 【テスト】 | maintenance | test |
| 【スタイル】 | maintenance | chore |
| 【CI】 | maintenance | chore |
| 【パフォーマンス】 | maintenance | refactor |
| 【取り消し】 | maintenance | chore |
| feat | feature | feat |
| fix | maintenance | fix |
| docs | docs | docs |
| refactor | maintenance | refactor |
| chore | maintenance | chore |
| test | maintenance | test |

### グループ単位の flow 判定

`releases[]` は日付単位でグルーピングした1エントリだが、`flow` はエントリ単位（グループ単位）の値であり、複数コミットが混在する日付グループでは上表のコミット単位の暫定 `flow` をそのまま使えない。次の優先順位でグループの `flow` を1つに決定する。

1. グループ内のコミットに `flow=feature` が1件でもあれば、グループの `flow` を `feature` とする
2. 1に該当せず、グループ内の全コミットが `flow=docs` であれば、グループの `flow` を `docs` とする
3. 1・2のいずれにも該当しなければ、グループの `flow` を `maintenance` とする

**採用理由**: この3値は互いに排他的な優先順位を持つ（feature > docs のみ > その他）。利用者がリリースノートで最も知りたい事実は「その日に利用者向けの新機能が入ったか」であり、機能追加が1件でも含まれる日は、他に修正や雑務が混在していても `feature` の日として扱うのが読み手の関心に合う。次に、機能追加が無く全件がドキュメントのみの日は、コードへの影響が無い `docs` の日として区別する価値がある。残りは日常的な保守（修正・整理・設定変更等が混在する、またはそれのみの）日として `maintenance` に一本化する。この規則は入力コミット集合が空でない限り必ず1値に収束し、恣意的な解釈を挟まない。

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| 整合検証 | `../../../generation-engine/scripts/detail-pages/validate-page-data.sh` |
| HTML生成 | `../../../generation-engine/scripts/detail-pages/build-detail-page.sh` |
| ポータル再生成（任意） | `../../../generation-engine/scripts/build-portal.sh` |

## 実行手順

## Phase 1: git log 全件取得

## Step 1-1: git log 全件取得

**使用ツール**: Read / Bash / Write

- **Step 1** — `target_repo_path` が git リポジトリであることを確認する。`.git` が存在しなければハード停止する。この場合 git 履歴を持たないリポジトリである旨を報告して終了する。完了条件: git リポジトリの実在確認済み、または不在を報告して停止している
- **Step 2** — `git -C <target_repo_path> log --date=short --pretty=format:'%H%x1f%ad%x1f%s'` で全コミットのハッシュ・日付・件名を取得する。完了条件: 全コミットの一覧が確定済み

**完了**: git リポジトリの実在確認済み、または不在を報告して停止している

## Phase 2: 日付グルーピング + 変更種別判定

## Step 2-1: 日付グルーピング + 変更種別判定

**使用ツール**: Bash / Write

- **Step 1** — Phase 1 Step 2 で取得した全コミットを `ad`（日付）でグルーピングする。完了条件: 日付単位のコミット群が確定済み
- **Step 2** — 各コミットの件名を先頭のプレフィックスで走査し、上記「プレフィックス対応表」に従って、コミット単位の暫定 `flow`（`feature` | `maintenance` | `docs`）と `changes[].type`（`feat` | `fix` | `docs` | `test` | `refactor` | `chore`）を判定する。プレフィックスが無い、または対応表に無い件名は「その他」として `flow=maintenance`・`changes.type=chore` に分類する。完了条件: 全コミットの `flow` 暫定分類と `changes.type` 分類が確定済み
- **Step 3** — 日付グループごとに、「グループ単位の flow 判定」の優先順位（feature を含む→feature／全件 docs→docs／それ以外→maintenance）でグループの `flow` を1つに決定する。コミット一覧（ハッシュ・件名・種別）を要約したエントリを組み立て、page-data.json を構築する。`pageKind: "release-notes"`、`tiles[]`（直近の変更種別内訳などの要約タイル）を埋める。`releases[]`（`{id, date, title, pr, prUrl, flow, summary, changes, verifySteps}`。PR 単位のリリースエントリ。`flow` はグループ単位で決定した値、`changes[]` は各コミットの `changes.type` 判定結果を `{type, text}` へ格納する。コミット情報は `changes` と `summary` に要約する。`sourceRef` は使わない）も埋める。完了条件: page-data.json を一時ディレクトリへ保存済み
- **Step 4** — 機械検査: 次の2コマンドを実行し、`flow` が3値の部分集合、`changes[].type` が6値の部分集合であることを確認する（プレフィックス対応表に無い値が紛れ込んでいないことの機械的な証拠とする。専用の `--self-test` スクリプトは存在しないため、本コマンドの実行結果を完了条件の証拠として残す）。完了条件: 両出力値がそれぞれ3値・6値の部分集合のみ

  ```bash
  jq -r '[.releases[].flow] | unique[]' <page-data.json>
  jq -r '[.releases[].changes[].type] | unique[]' <page-data.json>
  ```

page-data.json の保存先は `$CLAUDE_JOB_DIR/tmp/release-notes-page-data.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

**完了**: 全コミットの日付グルーピング・種別分類を終え page-data.json を保存済み、かつ `flow` 値が3値の部分集合、`changes[].type` 値が6値の部分集合のみであることを機械検査済み

## Phase 3: 整合検証（機械実行）

## Step 3-1: 整合検証（機械実行）

**使用ツール**: Bash

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../generation-engine/scripts/detail-pages/validate-page-data.sh <page-data.json> --target-repo <target_repo_path>
  ```

- **Step 2** — FAIL 時は指摘に応じて page-data.json を修正し Step 1 を再実行する。3 回失敗したら Phase 2 Step 3（page-data 組み立て）へ差し戻す。完了条件: exit 0

**完了**: `validate-page-data.sh --target-repo` が全項目 PASS

## Phase 4: リリースノート.html 生成

## Step 4-1: リリースノート.html 生成

**使用ツール**: Bash / Write

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<output_dir>/リリースノート.html` が生成済み

  ```
  ../../../generation-engine/scripts/detail-pages/build-detail-page.sh <page-data.json> <output_dir> --page release-notes
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定（ポータル未生成環境）なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../generation-engine/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-detail-page.sh` 経由の決定的処理で行う。

**完了**: `<output_dir>/リリースノート.html` が生成され、指定時は `build-portal.sh` の再実行が完了している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | git リポジトリの実在確認済み、または不在を報告して停止している |
| Phase 2 | 全コミットの日付グルーピング・種別分類を終え page-data.json を保存済み、かつ `flow` 値が feature/maintenance/docs の3値、`changes[].type` 値が feat/fix/docs/test/refactor/chore の6値の、それぞれ部分集合のみであることを機械検査済み |
| Phase 3 | `validate-page-data.sh --target-repo` が全項目 PASS |
| Phase 4 | `<output_dir>/リリースノート.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | git log の事実のみからリリースノート.html が生成され、種別判定不能なコミットは「その他」として捏造なく分類されている |

## 返却ブロック

本スキルは orchestrating-ai-development-setup の契約に準拠する。完了時に以下を返す。

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
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `output_dir` 配下のリリースノート.html のみ

## 予想を裏切る挙動

- 出力先は `<output_dir>/project-portal/foundation` 直下（種別専用フォルダは作らない）。`build-detail-page.sh` の `--page release-notes` 固定出力名仕様に従う
- `releases[]` に `sourceRef` は持たせない。コミット情報は各リリースの `changes`・`summary` に要約して格納する（確定仕様 `page-data-schema.md` T7 準拠）
- `portal_output_dir` 未指定時は `build-portal.sh` を実行しない。生成済みリリースノート.html はそのまま残り、次回ポータル生成時に自動でカード化される

## 設計判断

### validate-page-data.sh / build-detail-page.sh の共用

**必要性**: page-data.json の整合検証と HTML 生成は pageKind 非依存の決定的処理であり、既存 5 種別（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順）に共通する。`generation-engine/scripts/detail-pages/` の単一実装をリリースノートも含め共用することで、スキーマ変更時の同期漏れを防ぐ。

**代替案を採用しなかった理由**:
- スキルフォルダ内への複製: スキーマ変更時に種別数ぶんの同期漏れリスクが生じる
- Claude 手作業での HTML 組み立て: 検証なしのデータ混入が再発する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: page-data.json のスキーマ、またはリリースノート.html の形式が廃止された時

## 完了報告

`../../../delivery-payload/references/完了報告の書き方.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-page-data.sh` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../generation-engine/scripts/detail-pages/page-data-schema.md` — page-data.json のスキーマ定義
- `references/guide.html` — スキルガイド
