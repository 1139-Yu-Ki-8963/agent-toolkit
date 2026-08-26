---
name: generating-env-guide-for-reverse-docs
日本語名: 環境構築の手順書を作る
description: "調査書とローカル環境の調査結果をもとに、環境構築の手順ページを機械的に作る。"
invocation: generating-env-guide-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write]
---

## いつ使うか

アーキテクチャ調査書が確定し、入口のページに環境構築手順のカードを追加したいとき。

## いつ使わないか

アーキテクチャ調査書そのものを作るとき（→ surveying-architecture-for-reverse-docs を使う）、他の種別の詳細ページを作るとき。

# 正本: reverse-docs-skills

本スキルが生成する納品物は顧客提示の文書である。自由記述の本文（要約・説明文）は敬体（です・ます）で書く。記入規則・検証記録・作業記録は常体でもよい（`delivery-payload/references/設計書様式.md` §8）。

# 環境構築手順ページ生成スキル

工程全体は orchestrating-ai-development-setup が案内する。本スキルはポータルの将来ページ受け口のうち環境構築手順（T5）のみを担い、単独起動できる（起動引数を渡せば動く）。

アーキテクチャ調査書 §3 ビルドと起動の記載値を主データ源とする。任意で env-config.json（surveying-local-environment スキルの出力）を突き合わせて **環境構築手順.html** を書き出す。**本スキルは判定・評価を一切行わない**。事実の転記に徹し、記載値をそのまま前提ツール・実行手順・割当の 3 表へ整理する。

## 使用タイミング

- アーキテクチャ調査書が確定済みで、ポータルに環境構築手順カードを追加したいとき
- 起動引数: `target_repo_path`（調査対象リポジトリの絶対パス）・`output_dir`（調査書の所在かつ出力先）
- 任意引数: `env_config_path`（env-config.json の絶対パス。既定値: `<output_dir>/env-config.json`）
- `env_config_path` は存在しなければ無視する。`portal_output_dir` も任意引数
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

HTML出力先は`<output_dir>/project-portal/foundation/環境構築手順.html`、再生成入力は
`<output_dir>/<manifestsRoot>/detail-pages/env-page-data.json`に固定する。

## 設計原則

- **転記のみ** — 起動手順の良否・簡潔さは判定しない。調査書 §3 の記載値と env-config.json の実測値をそのまま整理して転記する
- **env-config.json は任意入力** — 不在でもハード停止しない。不在時は前提ツール表への実測反映のみを省略し、調査書 §3 だけで手順表・割当表を組み立てる
- **固定と可変の分離** — 整合検証（`validate-page-data.sh`）と HTML 生成（`build-detail-page.sh`）は決定的スクリプトに固定する。抽出（§3 表の読取・env-config.json の読取・割当の grep 抽出）は Claude 自身が Bash/Read/Grep で行う

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
- **Step 2** — `env_config_path`（既定値: `<output_dir>/env-config.json`）の実在を確認する。存在すれば内容を読み込み、存在しなければ「env-config.json 不在。前提ツール表は調査書のみから組み立てる」と記録し先へ進む（ハード停止しない）。完了条件: env-config.json の有無と内容（存在時のみ）が確定済み

**完了**: 調査書の実在確認済み、または不在を報告して停止している。env-config.json の有無が確定済み

## Phase 2: 抽出

## Step 2-1: 抽出

**使用ツール**: Read / Bash / Write

- **Step 1（prerequisites[]）** — env-config.json が存在する場合、`tools` の実測結果を `{name, note}` へ変換する。対象は cloc/node/python3/jq/git の 5 種。`note` にはインストール有無を記載し、未インストール時は `install_commands` の値も記載する。env-config.json が不在の場合、prerequisites[] は空配列のまま Phase 4 へ渡す（テンプレート側が「なし」を表示する）。完了条件: prerequisites[] を確定済み（空配列を含む）
- **Step 1b（environment[]）** — env-config.json が存在する場合、`os`・`arch`・`linux_compat_env` を `{name, value}` へ変換して environment[] に格納する。`linux_compat_env` が true の場合は「Linux 互換環境上での実行」と読み手に伝わる表記にする。env-config.json が不在の場合、environment[] は空配列のまま Phase 4 へ渡す（テンプレート側が「なし」を表示する）。完了条件: environment[] を確定済み（空配列を含む）
- **Step 2（steps[]）** — 調査書 §3 の「ビルドコマンド」「起動コマンド（開発）」「起動コマンド（本番）」の 3 行を読む。記載値が「実在しない（理由: …）」でない行だけを対象にする。対象行を、ビルド→開発起動→本番起動の順に並べたうえで **除外後の並びに `order` を 1 から連番で振り直す**（欠番を残さない。1-133: 除外前の固定番号 1/2/3 をそのまま転記しない）。各行について、§3 の「内容」列が実行可能なコマンド文字列であれば `command` へそのまま転記し、`note` には「出所: <§3 の根拠パス>」を埋め込む。「内容」列が句点「。」を含む説明文（実行できない散文）の場合は `command` を `"該当なし"` とし、その説明文は `note`（「出所: <§3 の根拠パス>」に続けて）へ回す。steps[] にはスキーマ上 sourceRef フィールドが存在しないため、根拠パスは note へテキストとして埋め込む運用にする。完了条件: steps[] の `order` が 1 から欠番なく連番になっており、`command` に句点を含む散文が無いこと
- **Step 3（allocations[]）** — 調査書 §3 の「環境変数定義の所在」行の根拠パスが指すファイルを実際に Read する。ポート番号・ホスト名等の割当を示す行（`PORT=`・`HOST=` 等の代入や設定キー）を抽出する。1 件ごとに `{target: 変数名またはキー名, value: 値, sourceRef: "<根拠パス>:<行番号>"}` を組み立てる。該当ファイルが不在の場合や、割当を示す記載が見つからない場合は、allocations[] を空配列のまま進める（捏造しない）。完了条件: allocations[] を確定済み（空配列を含む）
- **Step 4** — page-data.json を組み立てる。`pageKind: "env"`、Step 1〜3 の prerequisites[]/environment[]/steps[]/allocations[] を埋める。Write ツールで page-data.json を書き出す。完了条件: 検証候補のpage-data.jsonを一時保存済み

検証候補は`$CLAUDE_JOB_DIR/tmp/env-guide-page-data.json`へ保存する。未設定時は
`${TMPDIR:-/tmp}/claude-job-${session}/tmp/`配下に置く。未検証の候補を再生成用の正規配置へ置かない。

**完了**: prerequisites[]/environment[]/steps[]/allocations[] を確定し page-data.json を保存済み

## Phase 3: 整合検証（機械実行）

## Step 3-1: 整合検証（機械実行）

**使用ツール**: Bash

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../generation-engine/scripts/detail-pages/validate-page-data.sh <page-data.json> --target-repo <target_repo_path>
  ```

  sourceRef 実在検査の対象は `allocations[].sourceRef` のみ。加えて `validate-page-data.sh` は `steps[].order` の連番性（1..N、欠番・重複なし）と `steps[].command` の純度（句点「。」を含まないこと）を検証する（1-133）。prerequisites[] は sourceRef 検査の対象にしない（page-data-schema.md の T5 節が正）。

- **Step 2** — FAIL 時は `[FAIL]` 項目名で分岐する。「steps[].order連番性」FAIL は Phase 2 Step 2 へ差し戻し `order` を振り直す。「steps[].command純度」FAIL は該当行の `command` を `"該当なし"` にし説明を `note` へ移す。それ以外（`allocations[].sourceRef` 等）は該当箇所を修正して Step 1 を再実行する。3 回失敗したら Phase 2 Step 3（allocations 抽出）へ差し戻す。完了条件: exit 0

- **Step 3** — PASSした候補だけを永続化する。`output-layout.sh`で`manifestsRoot`を解決し、`<output_dir>/<manifestsRoot>/detail-pages/env-page-data.json`へ保存する。完了条件: 検証済みpage-dataが再生成用の正規配置に存在する

**完了**: `validate-page-data.sh --target-repo` が全項目 PASS

## Phase 4: 環境構築手順.html 生成

## Step 4-1: 環境構築手順.html 生成

**使用ツール**: Bash / Write

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<output_dir>/project-portal/foundation/環境構築手順.html` が生成済み

  ```
  ../../../generation-engine/scripts/detail-pages/build-detail-page.sh <page-data.json> <output_dir>/project-portal/foundation --page env
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定（ポータル未生成環境）なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../generation-engine/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-detail-page.sh` 経由の決定的処理で行う。

**完了**: `<output_dir>/project-portal/foundation/環境構築手順.html` が生成され、指定時は `build-portal.sh` の再実行が完了している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 調査書の実在確認済み、または不在を報告して停止している。env-config.json の有無が確定済み |
| Phase 2 | prerequisites[]/environment[]/steps[]/allocations[] を確定し検証候補を保存済み |
| Phase 3 | `validate-page-data.sh --target-repo` が全項目PASSし、検証済みpage-dataを再生成用の正規配置へ保存済み |
| Phase 4 | `<output_dir>/project-portal/foundation/環境構築手順.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | 調査書§3（および任意のenv-config.json）の記載値から検証済みpage-dataと環境構築手順.htmlが生成され、通常のポータル生成で再生成でき、割当の根拠をsourceRefで追跡できる |

## 返却ブロック

本スキルは orchestrating-ai-development-setup の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（調査書不在）\| `ERROR` |
| artifacts | 生成した環境構築手順.html と`env-page-data.json`のパス（`STOPPED`/`ERROR` 時は空） |
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
- 対象リポジトリへの書き込み・変更は一切行わない。出力は`output_dir`配下の`project-portal/foundation/環境構築手順.html`と検証済みpage-dataのみ

## 予想を裏切る挙動

- 出力先は `<output_dir>/project-portal/foundation` 直下（種別専用フォルダは作らない）。`build-detail-page.sh` の `--page env` 固定出力名仕様に従う
- `steps[]`/`prerequisites[]` には `sourceRef` フィールドが存在しない（page-data-schema.md の T5 節が正）。根拠パスは `note` へテキストとして埋め込む運用とする。`validate-page-data.sh` の sourceRef 実在検査は `allocations[].sourceRef` のみを対象にする。これは省略ではなくスキーマの確定仕様である。両フィールドに形式的な `sourceRef` を追加しても、検証・描画のどちらにも反映されない
- `env_config_path` は既定で `<output_dir>/env-config.json` を見る。ただし `surveying-local-environment` の出力先は呼び出し時の `output_dir` 引数次第で変わる。既定パスに存在しない場合は明示的に `env_config_path` を渡す
- env-config.json が存在しても `tools` に含まれないツール（§3 の起動コマンドが要求する言語ランタイム等）は prerequisites[] に自動追加しない。env-config.json の `tools` キー（cloc/node/python3/jq/git）に限定して転記する
- `os`・`arch`・`linux_compat_env` は prerequisites[]（ツールの一覧）ではなく environment[]（実行環境の実測値）へ転記する。両者は表として別に描画する
- 調査書の記載値が「実在しない（理由: …）」の行は steps[] に含めない（存在しない手順を転記しない）

## 設計判断

### validate-page-data.sh / build-detail-page.sh の共用

**必要性**: page-data.json の整合検証と HTML 生成は pageKind 非依存の決定的処理であり、5 種別（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順）に共通する。`generation-engine/scripts/detail-pages/` の単一実装を全種別スキルが相対パスで共用することで、スキーマ変更時の同期漏れを防ぐ。

**代替案を採用しなかった理由**:
- スキルフォルダ内への複製: スキーマ変更時に種別数ぶんの同期漏れリスクが生じる
- Claude 手作業での HTML 組み立て: 検証なしのデータ混入が再発する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: page-data.json のスキーマ、または環境構築手順.html の形式が廃止された時

### env-config.json を任意入力として扱う

**必要性**: `surveying-local-environment` は独立起動のスキルであり、env-config.json が事前に生成されているとは限らない。本スキルの主データ源は調査書 §3 であり、env-config.json はそれを補強する二次情報にとどまる。不在を理由に本スキルまで停止させると、調査書だけで組み立てられる手順表・割当表まで巻き添えで生成できなくなる。

**代替案を採用しなかった理由**:
- env-config.json 不在時のハード停止: 主データ源（調査書 §3）が揃っていても生成できなくなる。技術スタックスキルの「調査書不在ならハード停止」とは前提条件の性質が異なるが、それを一律に扱うことになる
- env-config.json を必須引数化: `surveying-local-environment` の単独起動という設計と矛盾する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: env-config.json のスキーマが変更され、前提ツール表の主データ源として格上げされた時

## 完了報告

`../../../delivery-payload/references/完了報告の書き方.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-page-data.sh` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../generation-engine/scripts/detail-pages/page-data-schema.md` — page-data.json のスキーマ定義
- `references/guide.html` — スキルガイド
