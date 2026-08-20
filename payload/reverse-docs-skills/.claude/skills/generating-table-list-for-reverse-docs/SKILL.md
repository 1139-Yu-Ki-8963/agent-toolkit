---
name: generating-table-list-for-reverse-docs
日本語名: テーブル一覧のとりまとめ
description: "既存のコードからテーブルの単位を見つけ出し、テーブル一覧のページを作る。"
invocation: generating-table-list-for-reverse-docs
type: transform
allowed-tools: [AskUserQuestion, Bash, Grep, Read, Write]
---

## いつ使うか

既存のコードからデータベースのテーブルの一覧を新しく作りたいとき。

## いつ使わないか

テーブル以外の種類の一覧を作るとき、原本との突き合わせや環境の同期や実装そのものを行うとき。

# 正本: reverse-docs-skills

# テーブル一覧生成スキル

工程全体は orchestrating-ai-development-setup が案内する。本スキルはテーブル種別（`unit_kind=table` 固定）の一覧生成のみを担い、単独起動できる（起動引数 source_dir・output_dir の2つを渡せば動く）。

既存コードベースを、スタック調査→検出戦略の宣言→戦略に基づく抽出→整合検証、の順で調査し、テーブル（DB テーブル・ビュー・マイグレーション）の単位にファイルをグルーピングして **テーブル一覧.html** を作成する。**本スキルの仕事はテーブル一覧.htmlの作成のみ**であり、設計書の雛形展開・生成・記入は一切行わない。

他スキルへの依存を持たず、単独で動作する。

## 設計原則: 固定と可変の分離

マニフェストスキーマ・整合検証（`validate-manifest.sh`）・HTML生成（`build-unit-list.sh`）は決定的スクリプトに固定する。抽出（テーブル境界の検出）はプロジェクトごとに可変である。

テーブル種別に組み込み検出器はない。**カスタム抽出パスのみ**を使う: Claude 自身が Phase 1 の戦略宣言に沿ってプロジェクト専用の抽出手順を設計・実行し、スキーマ準拠のマニフェストJSON（配列キーは `units`）を出力する。抽出者が誰であっても、`validate-manifest.sh` が抽出者非依存でマニフェストの整合性を機械保証する。汎用の正規表現を無条件に当てるのではなく、対象プロジェクト固有のテーブル定義規約（ORM・マイグレーションツール・SQL DDL の別）を先に確認してから検出することで、境界の取り違えを防ぐ。

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する（正本リポジトリと公開先はディレクトリレイアウトが同一のため、この相対参照は両環境で成立する）。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| 整合検証 | `../../../generation-engine/scripts/unit-list/validate-manifest.sh` |
| HTML生成 | `../../../generation-engine/scripts/unit-list/build-unit-list.sh` |

## 使用タイミング

- 既存コードベースのテーブル一覧（DB スキーマの一覧）を作りたいとき
- 起動引数: ソースコードディレクトリ（探索対象）・出力先ディレクトリ（テーブル一覧.htmlの書き出し先）の2つ

出力先は `<output_dir>/<unitListHtml>`（`unitListHtml` は output-layout の物理配置キーで {label} は「テーブル」）に固定する。永続マニフェスト（`table-manifest.json`・`table-manifest.ext.json`）は HTML と同じフォルダではなく `<output_dir>/<manifestsRoot>/` に永続化する。`manifestsRoot` は output-layout の物理配置キー（既定値 `docs/manifests`）。

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` でPhase 1〜4のタスクを登録する。各Phase開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 3からPhase 2へ差し戻す場合はPhase 2タスクを `in_progress` に戻す。実行環境にTaskCreate/TaskUpdateが存在しない場合は、出力先ディレクトリ内のタスク台帳ファイル（`task-ledger.md`）で同等のPhase遷移記録を代替する。

## 動作フロー（Phase 1〜4）

種別固有の調査項目・マニフェストスキーマの詳細は `references/table-detection.md` を参照する。

## Phase 1: スタック・テーブル規約の特定

## Step 1-1: スタック・テーブル規約の特定

**使用ツール**: AskUserQuestion / Bash / Grep / Read / Write

- **Step 1**: `package.json`・lockファイル（`package-lock.json`/`yarn.lock`/`pnpm-lock.yaml`）・`requirements.txt`/`pyproject.toml` 等から ORM・マイグレーションツール（Prisma/TypeORM/Knex/Alembic 等）を確定する。これらが存在しないコードベースでは import 文・SQL ファイルの形跡から推定する。完了条件: ツール名とバージョンが特定済み、または特定不能の根拠（推定経路）が記録済み
- **Step 2**: テーブル定義の所在を特定する。マイグレーションファイル・ORM モデル定義・SQL DDL のいずれが正本かを確定し、定義を含む実ファイルパスを列挙する。完了条件: テーブル定義を含む実ファイルパスが列挙済み
- **Step 3**: テーブル固有の識別要素を調査する（テーブル名の命名パターン・カラム/制約/インデックスの記述箇所・ビュー定義の有無）。完了条件: 識別パターン候補値または「なし」が確定済み
- **Step 4**: 除外パターンを確定する。テスト用マイグレーション・シード等のノイズを実際に `ls` で確認する。完了条件: `excludePatterns` 一覧が確定済み
- **Step 5**: 検出戦略宣言を作成し、AskUserQuestionで承認を取る。宣言JSONは一時ファイルに保存する。完了条件: 戦略JSON（`unitKind: "table"`/`extractionMethod: "custom"`/`unitIdRegex`/`excludePatterns`/`approvedByUser: true`/`notes`）が保存済み

**完了**: Step 1〜4の調査完了（`references/table-detection.md` の調査項目に準拠）。Step 5の検出戦略宣言（`unitKind: "table"`/`extractionMethod: "custom"`/`unitIdRegex`/`excludePatterns`）がユーザー承認済み

## Phase 2: 戦略に基づく抽出

## Step 2-1: 戦略に基づく抽出

- **Step 1**: 抽出方式はカスタム抽出パスに固定される（テーブル種別に組み込み検出器はない）。Phase 1で宣言した抽出手順を確認する。完了条件: 抽出手順（走査対象・グルーピング規則）が確定済み
- **Step 2**: 宣言した手順（例: マイグレーションファイルの走査・ORM モデル定義の解析・SQL DDL の `CREATE TABLE`/`CREATE VIEW` 抽出等）をClaude自身がBash/Grep/Readで実行し、スキーマ準拠のマニフェストJSONをWriteする。完了条件: マニフェストJSONが生成済み
- **Step 3**: 検出件数と内訳を確認する。0件検出は「0件時の分岐」節に従って処理する（テーブルを捏造しない）。完了条件: 1件以上の検出を確認済み、または「0件時の分岐」に従い該当なし生成による正常終了、または検出失敗の停止をしている
- **Step 4**: マニフェストへメタデータを付与する。`../../../generation-engine/scripts/extract/extract-table-metadata.sh <manifest.json> <migrations_dir> <output_dir>/<manifestsRoot>/table-manifest.ext.json` を実行し、各ユニットに `foreignKeys`・`columnCount`・`mainColumns` フィールドを追加した拡張マニフェストを一時ファイル + rename で `<output_dir>/<manifestsRoot>/table-manifest.ext.json` へ原子的に永続化する。`<migrations_dir>` はPhase 1 Step 2で特定したマイグレーション/DDLディレクトリを渡す。以降のPhaseでは永続化した `table-manifest.ext.json` を使用する。完了条件: 拡張マニフェストが `<output_dir>/<manifestsRoot>/table-manifest.ext.json` に永続化済み

**非UTF-8原本への対応**: 原本が UTF-8 以外のエンコーディングで書かれている場合、通常の文字列検索はバイナリ扱いとなりマッチ 0 件を返す。走査の前に `generation-engine/scripts/detect-encoding.sh encoding <file>` でエンコーディングを確定し、UTF-8 以外なら `detect-encoding.sh to-utf8` で変換した一時コピーに対して走査する。変換結果は永続化せず一時コピーで足りる。マッチ 0 件を「該当なし」と結論する前に、エンコーディングが原因でないことを確認する。

## 0件時の分岐

検出0件は2つの状態を区別する。アーキテクチャ調査書（`survey_doc_path`）のテーブル種別の実在判定と突合して分岐する。エンコーディング起因の0件でないことを先に確認する（上記「非UTF-8原本への対応」）。

| 調査書の判定 | 意味 | 動作 |
|---|---|---|
| テーブルは実在しない | テーブルを持たないプロジェクト | `<output_dir>/<unitListAbsentMd>`（`unitListAbsentMd` は output-layout の物理配置キー。`{label}` に「テーブル」を代入。既定値 `docs/manifests/テーブル一覧（該当なし）.md`）を判定理由の転記付きで生成し、status=`NONE` で正常終了する。呼び出し元は excluded-kinds.json の excludedKinds へ table を記録する |
| テーブルは実在する | 検出失敗（抽出パスの不適合、境界の誤り） | 停止する。headless=false なら AskUserQuestion で報告し、headless=true なら `<verification_dir>/progress.jsonl` へ記録して status=`ERROR` を返す。手動リストは聞き出さない |

`survey_doc_path` が未指定で調査書と突合できない場合は、実在判定を推測せず検出失敗として扱う（fail-closed）。

**名称（name）の作り方**: マニフェストの各ユニットに付与する名称は、実装モジュール名・サブ名・ユニットキー・実装状態マーカー等の内部識別子を機械連結して生成しない。業務語のみで名称を構成する。設定ファイルのコメント等から得た業務名がそれ単体で一意にならない場合は、実装が属する機能グループを業務語へ訳して前置きする。訳語は参照テーブル名・コード内コメント・呼び出し関数名・テンプレート名等、実装コードの根拠に基づかせ、根拠のないものは推定と明示する。業務名が「テスト用」「一覧」「トップ」のように実態を表していない場合は、実装を読んでテーブルの実態に即した名称を作る。設定ファイルのコメントが空欄でフォールバックが必要な場合も、＜系統名：ユニットキー（サブ名）＞のような内部識別子の連結を名称にしない。参照テーブル名・データ操作の種別・呼び出し関数名・テンプレート名・出力される固定文言を手がかりに実装から業務名を作る。実装からも業務名を断定できない場合は捏造せず、推定であることと手がかりを記録に残す。当該ユニットは名称を空にせず「業務名が未確定である」旨が利用者に伝わる表記にし、要確認として別掲する。要確認件数は成果物のサマリへ表示する。名称の根拠と確信度は次の列構成で記録する。

| ユニットキー | 現行の名称 | 命名 | 根拠 | 断定可否 |
|---|---|---|---|---|

検出結果は一時ディレクトリ（`$CLAUDE_JOB_DIR/tmp/table-manifest.json`、未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下。`${session}`はセッションIDが取得できなければ任意の一意な値でよい）に保存する。確定後は `<output_dir>/<manifestsRoot>/table-manifest.json` へ一時ファイル + rename で原子的に永続化する。一時ファイルを後続・再開処理の入力にしてはならない。

**完了**: Step 2でスキーマ準拠のマニフェスト（配列キー `units`）が1件以上確定、または0件検出を「0件時の分岐」に従い処理している（該当なし生成による正常終了、または検出失敗の停止）。Step 3で検出内訳を確認済み。Step 4で拡張マニフェストに種別固有フィールド（foreignKeys・columnCount・mainColumns等）が付与されている

## Phase 3: 整合検証（機械実行）

## Step 3-1: 整合検証（機械実行）

**使用ツール**: Bash

- **Step 1**: `../../../generation-engine/scripts/unit-list/validate-manifest.sh <manifest.ext.json> --unit-kind table --migrations-dir <migrations_dir>` を実行する。`<migrations_dir>` はPhase 1 Step 2で特定したマイグレーション/DDLディレクトリと同じものを渡す(渡すと、抽出結果がマイグレーション履歴からの再計算値と一致するかを追加検査する「table-メタデータ-履歴突き合わせ」項目が有効になる。渡さないと当該項目はスキップされ、列数追随漏れ・外部キーの過不足が検出できない)。完了条件: 全項目PASS
- **Step 2**: FAIL時は指摘に応じて修正する。修正後Step 1を再実行する。3回失敗したら抽出手順の再検討（Phase 2 Step 1）へ差し戻す。完了条件: exit 0

カスタム抽出パスであっても、この検証を通過しないマニフェストはPhase 4に進めない。

**完了**: Step 1で `validate-manifest.sh --unit-kind table` が全項目PASS。Step 2のFAIL時修正ループは3回以内

## Phase 4: テーブル一覧.html 生成

## Step 4-1: テーブル一覧.html 生成

**使用ツール**: Bash / Write

- **Step 1**: `../../../generation-engine/scripts/unit-list/build-unit-list.sh <manifest.ext.json> <output_dir>/<unitListHtml> --unit-kind table --portal-dir <output_dir>` を実行する。`--portal-dir` にはポータル（`index.html`）の配置先＝納品物ルート（output_dir=output_dir）を渡し、「ポータルへ戻る」リンクを実在パスに解決させる。build側が内部でvalidateを再実行するため、検証を経ないmanifestからは生成できない。完了条件: HTML生成済み

**手作業でのプレースホルダ置換は禁止する**（過去に `entryFile=None` の混入という実害が発生している）。HTML生成は必ずスクリプト経由の決定的処理で行う。

**完了**: Step 1でテーブル一覧.htmlが生成され、埋め込みJSONがマニフェストと一致している。永続マニフェストが `<output_dir>/<manifestsRoot>/table-manifest.json` に実在する

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | Step 1〜4の調査完了（`references/table-detection.md` の調査項目に準拠）。Step 5の検出戦略宣言（`unitKind: "table"`/`extractionMethod: "custom"`/`unitIdRegex`/`excludePatterns`）がユーザー承認済み |
| Phase 2 | Step 2でスキーマ準拠のマニフェスト（配列キー `units`）が1件以上確定、または0件検出を「0件時の分岐」に従い処理している（該当なし生成による正常終了、または検出失敗の停止）。Step 3で検出内訳を確認済み。Step 4で拡張マニフェストに種別固有フィールド（foreignKeys・columnCount・mainColumns等）が付与されている |
| Phase 3 | Step 1で `validate-manifest.sh --unit-kind table` が全項目PASS。Step 2のFAIL時修正ループは3回以内 |
| Phase 4 | Step 1でテーブル一覧.htmlが生成され、埋め込みJSONがマニフェストと一致している。永続マニフェストが `<output_dir>/<manifestsRoot>/table-manifest.json` に実在する |
| **Goal** | 検証済みマニフェストのみからHTMLが生成され、未解決・診断警告が可視化され、設計書単位の判断材料が揃っている |

## 返却

本スキルは orchestrating-ai-development-setup の契約に準拠する。完了時に以下を返す。

- `status`: `DONE | NONE | ERROR`
- `artifacts`: `DONE` は生成したテーブル一覧.htmlのパス。`NONE` は `<output_dir>/<unitListAbsentMd>`（既定値 `docs/manifests/テーブル一覧（該当なし）.md`）のパス
- `unit_list_html`: artifacts[0] の汎用名
- `embedded_json_ref`: HTML内に埋め込んだマニフェストJSONへの参照
- `unit_kind`: `table`（固定値）
- `table_manifest_path`: 永続生マニフェスト（`<output_dir>/<manifestsRoot>/table-manifest.json`）
- `table_manifest_ext_path`: 永続拡張マニフェスト（`<output_dir>/<manifestsRoot>/table-manifest.ext.json`）

`NONE` は調査書がテーブルの実在しないことを判定済みの場合だけ返す（「0件時の分岐」節を参照）。呼び出し元は excluded-kinds.json の excludedKinds へ table を記録する。

## ツールリファレンス

| ツール | 用途 |
|---|---|
| Bash | `validate-manifest.sh`・`build-unit-list.sh` の実行、マイグレーション/DDL ファイルの走査 |
| Read | package.json・マイグレーションファイル・ORM モデル定義・`references/table-detection.md` の参照 |
| Grep/Glob | テーブル定義規約（命名パターン・`CREATE TABLE`/`CREATE VIEW`・ORM モデル宣言）の調査、物理ファイル収集 |
| Write | 検出戦略宣言の一時保存、マニフェストJSON出力（テーブル一覧.html本体はスクリプト経由で生成） |
| AskUserQuestion | Phase 1の検出戦略宣言確認、Phase 2の0件検出時の報告 |
| TaskCreate/TaskUpdate | Phase 1〜4の進捗管理 |

## 推奨手順

- ソースディレクトリは対象プロジェクトの実コードルート（例: `backend/`）を指定する。モノレポの場合はアーキテクチャ調査書 §10 のサイト一覧で確定した当該サイトのルートディレクトリを渡す
- Phase 1の調査を省略して汎用の `unitIdRegex` を当てない。プロジェクトごとに命名規約・マイグレーション方式は異なる
- マイグレーションファイルと ORM モデル定義が両方ある場合、どちらを正本とするかを Phase 1 Step 2 で確定してから抽出する（両方を無差別に数えると同一テーブルの重複検出になる）

## 重要な注意事項

- 設計書の雛形展開・生成・記入は一切行わない。本スキルの成果物はテーブル一覧.htmlのみ
- Phase 4のHTML手作業組み立てを禁止する。`build-unit-list.sh` を必ず経由し、プレースホルダの手動置換による `entryFile=None` 等のデータ混入を防ぐ
- 0件検出時にAskUserQuestionで手動リストを聞き出さない。誤った境界を即興確定させない。該当なしの正常終了と検出失敗の停止の区別は「0件時の分岐」の表が正である
- Phase 2の抽出で全ツリーを対象とする文字列検索を行う場合は、走査範囲を対象拡張子で絞る。絞り込みなしの全ツリー再帰検索は、単一ディレクトリだけで数百メガバイト規模の対象があると実行時間の上限を超える。絞り込んだ拡張子と、走査対象外にした件数を抽出結果へ記録する

## 予想を裏切る挙動

- `validate-manifest.sh`・`build-unit-list.sh` は jq に依存する。未インストール環境では事前に導入する
- マニフェストの配列キーは `units` とする（`screens` ではない）
- 出力先は `<output_dir>/<unitListHtml>`。テーブル種別専用の独立フォルダを作成する
- カスタム抽出でソースを解析する際、コメントアウトされた定義（`-- CREATE TABLE ...`・コメント内のモデル宣言等）を除去してから抽出する（コメント内の定義を実在として誤検出した実害を防ぐ）
- マイグレーションは同一テーブルに対して複数存在しうる（create → alter の積み重ね）。テーブル単位に集約し、`files` に関連マイグレーションを列挙する。alter だけを独立テーブルとして数えない
- 設計書の雛形展開・生成は行わない（本スキルのスコープ外）

## 完了報告

`../../../delivery-payload/references/完了報告の書き方.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- validate-manifest.sh --unit-kind table が全項目 PASS・テーブル一覧.html の生成成功

## 設計判断

### エンジンスクリプトの共用（validate-manifest.sh / build-unit-list.sh）

**必要性**: マニフェストの整合検証とHTML生成は種別非依存の決定的処理であり、種別別スキルごとに複製するとスキーマ変更時に全複製の同期が必要になる。`generation-engine/scripts/unit-list/` の単一実装を全種別スキルが相対パスで共用する。

**代替案を採用しなかった理由**:
- スキルフォルダ内への複製: スキーマ変更時に種別数ぶんの同期漏れリスクが生じる
- Claude手作業でのHTML組み立て: 検証なしのデータ混入（`entryFile=None` が10件混入した実害実績）が再発する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: マニフェスト形式（JSONスキーマ）またはテーブル一覧.htmlの形式が廃止された時
