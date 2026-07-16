---
name: generating-env-guide-for-reverse-docs
description: "環境実行手順.html を調査書とローカル環境調査結果から機械生成する。 TRIGGER when: 環境実行手順ページ生成、env guide HTML作成。 SKIP: アーキテクチャ調査書自体の作成（→surveying-architecture-for-reverse-docs）、他種別詳細ページ生成。"
invocation: generating-env-guide-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Grep]
---

# 環境実行手順ページ生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの将来ページ受け口のうち環境実行手順（T5）のみを担い、単独起動できる（起動引数を渡せば動く）。

アーキテクチャ調査書 §3 ビルドと起動の記載値を主データ源とする。任意で env-config.json（surveying-local-environment スキルの出力）を突き合わせて **環境実行手順.html** を書き出す。**本スキルは判定・評価を一切行わない**。事実の転記に徹し、記載値をそのまま前提ツール・実行手順・割当の 3 表へ整理する。

## 使用タイミング

- アーキテクチャ調査書が確定済みで、ポータルに環境実行手順カードを追加したいとき
- 起動引数: `target_repo_path`（調査対象リポジトリの絶対パス）・`docs_root`（調査書の所在かつ出力先）
- 任意引数: `env_config_path`（env-config.json の絶対パス。既定値: `<docs_root>/env-config.json`）
- `env_config_path` は存在しなければ無視する。`portal_output_dir` も任意引数
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<docs_root>/環境実行手順.html` に固定する（`build-portal.sh` の `FUTURE_FILES` と同値）。

## 設計原則

- **転記のみ** — 起動手順の良否・簡潔さは判定しない。調査書 §3 の記載値と env-config.json の実測値をそのまま整理して転記する
- **env-config.json は任意入力** — 不在でもハード停止しない。不在時は前提ツール表への実測反映のみを省略し、調査書 §3 だけで手順表・割当表を組み立てる
- **固定と可変の分離** — 整合検証（`validate-page-data.sh`）と HTML 生成（`build-detail-page.sh`）は決定的スクリプトに固定する。抽出（§3 表の読取・env-config.json の読取・割当の grep 抽出）は Claude 自身が Bash/Read/Grep で行う

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
- **Step 2** — `env_config_path`（既定値: `<docs_root>/env-config.json`）の実在を確認する。存在すれば内容を読み込み、存在しなければ「env-config.json 不在。前提ツール表は調査書のみから組み立てる」と記録し先へ進む（ハード停止しない）。完了条件: env-config.json の有無と内容（存在時のみ）が確定済み

### Phase 2: 抽出

- **Step 1（prerequisites[]）** — env-config.json が存在する場合、`tools` の実測結果を `{name, note}` へ変換する。対象は cloc/node/python3/jq/git の 5 種。`note` にはインストール有無を記載し、未インストール時は `install_commands` の値も記載する。env-config.json が不在の場合、prerequisites[] は空配列のまま Phase 4 へ渡す（テンプレート側が「なし」を表示する）。完了条件: prerequisites[] を確定済み（空配列を含む）
- **Step 2（steps[]）** — 調査書 §3 の「ビルドコマンド」「起動コマンド（開発）」「起動コマンド（本番）」の 3 行を読む。記載値が「実在しない（理由: …）」でない行だけを対象にする。対象行を `order` 昇順（ビルド=1、開発起動=2、本番起動=3。欠番があれば詰めずそのまま欠落させる）で `steps[]` に変換する。`command` には §3 の「内容」列をそのまま転記する。`note` には「出所: <§3 の根拠パス>」の形式で根拠パスを埋め込む。steps[] にはスキーマ上 sourceRef フィールドが存在しないため、根拠パスは note へテキストとして埋め込む運用にする。完了条件: steps[] を確定済み
- **Step 3（allocations[]）** — 調査書 §3 の「環境変数定義の所在」行の根拠パスが指すファイルを実際に Read する。ポート番号・ホスト名等の割当を示す行（`PORT=`・`HOST=` 等の代入や設定キー）を抽出する。1 件ごとに `{target: 変数名またはキー名, value: 値, sourceRef: "<根拠パス>:<行番号>"}` を組み立てる。該当ファイルが不在の場合や、割当を示す記載が見つからない場合は、allocations[] を空配列のまま進める（捏造しない）。完了条件: allocations[] を確定済み（空配列を含む）
- **Step 4** — page-data.json を組み立てる。`pageKind: "env"`、Step 1〜3 の prerequisites[]/steps[]/allocations[] を埋める。Write ツールで page-data.json を書き出す。完了条件: page-data.json を一時ディレクトリへ保存済み

page-data.json の保存先は `$CLAUDE_JOB_DIR/tmp/env-guide-page-data.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

### Phase 3: 整合検証（機械実行）

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/detail-pages/validate-page-data.sh <page-data.json> --target-repo <target_repo_path>
  ```

  検証対象は `allocations[].sourceRef` のみ。`validate-page-data.sh` は steps[]/prerequisites[] を sourceRef 検査の対象にしない（page-data-schema.md の T5 節が正）。

- **Step 2** — FAIL 時は `allocations[].sourceRef` を修正し Step 1 を再実行する。3 回失敗したら Phase 2 Step 3（allocations 抽出）へ差し戻す。完了条件: exit 0

### Phase 4: 環境実行手順.html 生成

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<docs_root>/環境実行手順.html` が生成済み

  ```
  ../../../shared/scripts/detail-pages/build-detail-page.sh <page-data.json> <docs_root> --page env
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定（ポータル未生成環境）なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../shared/scripts/build-portal.sh <target_repo_path> <docs_root> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-detail-page.sh` 経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 調査書の実在確認済み、または不在を報告して停止している。env-config.json の有無が確定済み |
| Phase 2 | prerequisites[]/steps[]/allocations[] を確定し page-data.json を保存済み |
| Phase 3 | `validate-page-data.sh --target-repo` が全項目 PASS |
| Phase 4 | `<docs_root>/環境実行手順.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | 調査書 §3（および任意で env-config.json）の記載値のみから環境実行手順.html が生成され、割当の根拠が sourceRef で追跡できる |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（調査書不在）\| `ERROR` |
| artifacts | 生成した環境実行手順.html のパス（`STOPPED`/`ERROR` 時は空） |
| page_kind | `env`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由（調査書不在パス）、env-config.json 有無の注記、または次工程への申し送り |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復対象 | Phase 3 Step 1 が FAIL → Step 2 で修正して再実行 |
| 上限回数 | 3 回 |
| 収束停止 | `validate-page-data.sh` が exit 0 |
| 発散検知 | 同一検査項目の同一 FAIL が 2 回連続で再発した場合は即座に Phase 2 Step 3（allocations 抽出）へ差し戻す |
| リソース上限 | 3 回失敗で Phase 2 Step 3 へ差し戻す |

## 重要な注意事項

- 判定・評価はしない。起動手順の良否・簡潔さ・改善提案には一切踏み込まず、調査書と env-config.json の記載事実のみを転記する
- env-config.json 不在を理由にハード停止しない。調査書 §3 だけでも steps[] は組み立てられるため、前提ツール表のみ空欄で進める
- allocations[] を推測・捏造しない。環境変数定義ファイルに割当を示す記載が見つからない場合は空配列のまま進める
- Phase 4 の HTML 手作業組み立てを禁止する。`build-detail-page.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `docs_root` 配下の環境実行手順.html のみ

## 予想を裏切る挙動

- 出力先は `<docs_root>` 直下（種別専用フォルダは作らない）。`build-detail-page.sh` の `--page env` 固定出力名仕様に従う
- `steps[]`/`prerequisites[]` には `sourceRef` フィールドが存在しない（page-data-schema.md の T5 節が正）。根拠パスは `note` へテキストとして埋め込む運用とする。`validate-page-data.sh` の sourceRef 実在検査は `allocations[].sourceRef` のみを対象にする。これは省略ではなくスキーマの確定仕様である。両フィールドに形式的な `sourceRef` を追加しても、検証・描画のどちらにも反映されない
- `env_config_path` は既定で `<docs_root>/env-config.json` を見る。ただし `surveying-local-environment` の出力先は呼び出し時の `output_dir` 引数次第で変わる。既定パスに存在しない場合は明示的に `env_config_path` を渡す
- env-config.json が存在しても `tools` に含まれないツール（§3 の起動コマンドが要求する言語ランタイム等）は prerequisites[] に自動追加しない。env-config.json の `tools` キー（cloc/node/python3/jq/git）に限定して転記する
- 調査書の記載値が「実在しない（理由: …）」の行は steps[] に含めない（存在しない手順を転記しない）

## 設計判断

### validate-page-data.sh / build-detail-page.sh の共用

**必要性**: page-data.json の整合検証と HTML 生成は pageKind 非依存の決定的処理であり、5 種別（用語辞書・技術スタック・画面遷移図・ER図・環境実行手順）に共通する。`shared/scripts/detail-pages/` の単一実装を全種別スキルが相対パスで共用することで、スキーマ変更時の同期漏れを防ぐ。

**代替案を採用しなかった理由**:
- スキルフォルダ内への複製: スキーマ変更時に種別数ぶんの同期漏れリスクが生じる
- Claude 手作業での HTML 組み立て: 検証なしのデータ混入が再発する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: page-data.json のスキーマ、または環境実行手順.html の形式が廃止された時

### env-config.json を任意入力として扱う

**必要性**: `surveying-local-environment` は独立起動のスキルであり、env-config.json が事前に生成されているとは限らない。本スキルの主データ源は調査書 §3 であり、env-config.json はそれを補強する二次情報にとどまる。不在を理由に本スキルまで停止させると、調査書だけで組み立てられる手順表・割当表まで巻き添えで生成できなくなる。

**代替案を採用しなかった理由**:
- env-config.json 不在時のハード停止: 主データ源（調査書 §3）が揃っていても生成できなくなる。技術スタックスキルの「調査書不在ならハード停止」とは前提条件の性質が異なるが、それを一律に扱うことになる
- env-config.json を必須引数化: `surveying-local-environment` の単独起動という設計と矛盾する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: env-config.json のスキーマが変更され、前提ツール表の主データ源として格上げされた時

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-page-data.sh` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../shared/scripts/detail-pages/page-data-schema.md` — page-data.json のスキーマ定義
- `references/generating-env-guide-for-reverse-docs-guide.html` — スキルガイド
