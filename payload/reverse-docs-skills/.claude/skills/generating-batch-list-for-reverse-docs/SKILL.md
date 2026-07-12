---
name: generating-batch-list-for-reverse-docs
description: "バッチ一覧フォルダ・バッチ一覧HTML生成。 TRIGGER when: バッチ一覧作成、バッチ一覧生成、ジョブ一覧。 SKIP: 他種別の一覧（→対応する種別別一覧スキル）、往復検証/同期/実装。"
invocation: generating-batch-list-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate]
---

# バッチ一覧生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはバッチ種別（`unit_kind=batch` 固定）の一覧生成のみを担い、単独起動できる（起動引数 source_dir・output_dir の2つを渡せば動く）。

既存コードベースを、スタック調査→検出戦略の宣言→戦略に基づく抽出→整合検証、の順で調査し、バッチ（定期実行ジョブ・トリガー起動ジョブ・CLI コマンド）の単位にファイルをグルーピングして **バッチ一覧.html** を作成する。**本スキルの仕事はバッチ一覧.htmlの作成のみ**であり、設計書の雛形展開・生成・記入は一切行わない。

他スキルへの依存を持たず、単独で動作する。

## 設計原則: 固定と可変の分離

マニフェストスキーマ・整合検証（`validate-manifest.sh`）・HTML生成（`build-unit-list.sh`）は決定的スクリプトに固定する。抽出（バッチ境界の検出）はプロジェクトごとに可変である。

バッチ種別に組み込み検出器は存在しない。抽出は常に**カスタム抽出パス**を取る: Claude自身が Phase 1 の戦略宣言に沿ってプロジェクト専用の抽出手順を設計・実行し、スキーマ準拠のJSONマニフェスト（配列キーは `units`）を出力する。抽出方式に依らず `validate-manifest.sh` が抽出者非依存でマニフェストの整合性を機械保証する。汎用の正規表現を無条件に当てるのではなく、対象プロジェクト固有のバッチ規約を先に確認してから検出することで、境界の取り違えを防ぐ。

エンジンスクリプトはスキルフォルダからの相対パスで参照する: `../../../shared/scripts/unit-list/validate-manifest.sh`・`../../../shared/scripts/unit-list/build-unit-list.sh`（正本リポジトリと公開先はディレクトリレイアウトが同一のため、この相対参照は両環境で成立する）。

## 使用タイミング

- 既存コードベースのバッチ一覧（定期実行ジョブ・トリガー起動ジョブの棚卸し）を作りたいとき
- 起動引数: `source_dir`（ソースコードディレクトリ。探索対象）・`output_dir`（出力先ディレクトリ。バッチ一覧.htmlの書き出し先）の2つのみ

## 出力仕様

| 項目 | 値 |
|---|---|
| 種別 | batch（固定） |
| ラベル | バッチ |
| 出力フォルダ | `<output_dir>/バッチ一覧/` |
| 出力ファイル名 | バッチ一覧.html |
| マニフェスト配列キー | `units` |

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` でPhase 1〜4のタスクを登録する。各Phase開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 3からPhase 2へ差し戻す場合はPhase 2タスクを `in_progress` に戻す。実行環境にTaskCreate/TaskUpdateが存在しない場合は、出力先ディレクトリ内のタスク台帳ファイル（`task-ledger.md`）で同等のPhase遷移記録を代替する。

## 動作フロー（Phase 1〜4）

### Phase 1: スタック・バッチ規約の特定

調査項目の詳細は `references/batch-detection.md` を参照する。

- **Step 1**: `package.json`・lockファイル（`package-lock.json`/`yarn.lock`/`pnpm-lock.yaml`）や依存定義（`requirements.txt`/`pyproject.toml` 等）からジョブスケジューラ・cron系ライブラリを確定する。これらが存在しないコードベースでは import 文・API 使用形跡から推定する。完了条件: ライブラリ名とバージョンが特定済み、または特定不能の根拠（推定経路）が記録済み
- **Step 2**: バッチ定義の所在と方式を特定する（cron 定義・ジョブスケジューラ設定・CLI コマンド定義。`references/batch-detection.md` の調査対象表に従う）。完了条件: バッチ定義を含む実ファイルパスが列挙済み
- **Step 3**: バッチ固有の識別要素を調査する（ジョブ名の命名パターン・実行スケジュール（cron 式・実行間隔・トリガー条件）・入出力（処理対象データソース・出力先））。完了条件: `unit-id-regex` の候補値または「なし」が確定済み
- **Step 4**: 除外パターンを確定する。ワンショットスクリプト・マイグレーション・`tests` 等のノイズを実際に `ls` で確認する。完了条件: `excludePatterns` 一覧が確定済み
- **Step 5**: 検出戦略宣言を作成し、AskUserQuestionで承認を取る。宣言JSONは一時ファイルに保存する。完了条件: 戦略JSON（`unitKind: "batch"`/`extractionMethod: "custom"`/`unitIdRegex`/`excludePatterns`/`approvedByUser: true`/`notes`）が保存済み

### Phase 2: 戦略に基づく抽出（カスタム抽出パスのみ）

- **Step 1**: Phase 1で宣言した手順（例: cron 設定ファイルのエントリ走査・ジョブ登録呼び出し（`schedule()`/`cron.schedule()` 等）の収集・CLI コマンド定義の列挙）をClaude自身がBash/Grep/Readで実行し、スキーマ準拠のマニフェストJSON（配列キー `units`）をWriteする。0件検出ならユーザーに報告してハード停止する。バッチを捏造しない。完了条件: マニフェストJSONが生成済み、または0件停止を報告済み
- **Step 2**: diagnosticsを確認する。警告が出た場合は抽出手順を見直し、見直し時はStep 1へ戻る。完了条件: diagnosticsが空、または警告を承知の上で続行と判断済み

検出結果は一時ディレクトリ（`$CLAUDE_JOB_DIR/tmp/batch-manifest.json`、未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下。`${session}`はセッションIDが取得できなければ任意の一意な値でよい）に保存する。

### Phase 3: 整合検証（機械実行）

- **Step 1**: `../../../shared/scripts/unit-list/validate-manifest.sh <manifest.json> --unit-kind batch` を実行する。完了条件: 全項目PASS
- **Step 2**: FAIL時は指摘に応じて修正する（sourceFile不在は `--fix` でunresolved降格可）。修正後Step 1を再実行する。3回失敗したら抽出手順の再検討（Phase 2 Step 1）へ差し戻す。完了条件: exit 0

`validate-manifest.sh` は抽出者非依存で同一基準の検証を行う。カスタム抽出パスであっても、この検証を通過しないマニフェストはPhase 4に進めない。

### Phase 4: バッチ一覧.html 生成

- **Step 1**: `../../../shared/scripts/unit-list/build-unit-list.sh <manifest.json> <output_dir>/バッチ一覧/バッチ一覧.html --unit-kind batch` を実行する。build側が内部でvalidateを再実行するため、検証を経ないmanifestからは生成できない。完了条件: HTML生成済み

**手作業でのプレースホルダ置換は禁止する**（過去に `entryFile=None` の混入という実害が発生している）。HTML生成は必ずスクリプト経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | Step 1〜4の調査完了（`references/batch-detection.md` の調査項目に準拠）。Step 5の検出戦略宣言（`unitKind`/`extractionMethod`/`unitIdRegex`/`excludePatterns`）がユーザー承認済み |
| Phase 2 | Step 1でスキーマ準拠のマニフェストが1件以上確定、または0件検出をユーザーに報告して停止している。Step 2でdiagnosticsを確認済み |
| Phase 3 | Step 1で `validate-manifest.sh --unit-kind batch` が全項目PASS。Step 2のFAIL時修正ループは3回以内 |
| Phase 4 | Step 1でバッチ一覧.htmlが生成され、埋め込みJSONがマニフェストと一致している |
| **Goal** | 検証済みマニフェストのみからHTMLが生成され、未解決・診断警告が可視化され、設計書単位の判断材料が揃っている |

## 返却

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に status（`DONE | ERROR`）と artifacts（生成したバッチ一覧.htmlのパス）を返す。artifacts[0] を汎用名 unit_list_html として返し、`unit_kind: batch`（固定値）を返却ブロックに含める。HTML内に埋め込んだマニフェストJSONへの参照を embedded_json_ref として併せて返す。

## ツールリファレンス

| ツール | 用途 |
|---|---|
| Bash | `validate-manifest.sh`・`build-unit-list.sh` の実行（スキルフォルダ相対 `../../../shared/scripts/unit-list/` 配下） |
| Read | package.json・cron/スケジューラ設定・`references/batch-detection.md` の参照 |
| Grep/Glob | バッチ規約（ジョブ名命名パターン・ジョブ登録呼び出し）・バッチ定義の調査、カスタム抽出パスでの物理ファイル収集 |
| Write | 検出戦略宣言の一時保存、マニフェストJSON出力（バッチ一覧.html本体はスクリプト経由で生成） |
| AskUserQuestion | Phase 1の検出戦略宣言確認、Phase 2の0件検出時の報告 |
| TaskCreate/TaskUpdate | Phase 1〜4の進捗管理 |

## 推奨手順

- ソースディレクトリは対象プロジェクトの実コードルート（例: `backend/src`）を指定する。モノレポでアプリが複数ある場合は対象アプリのディレクトリのみを渡す（自動判別なし）
- Phase 1の調査を省略して汎用の `unit-id-regex` を当てない。プロジェクトごとにジョブ命名規約・スケジューラ方式は異なる
- 定期実行（`kind: scheduled`）とトリガー起動（`kind: triggered`）の区別はPhase 1で確定させてから抽出する。区別が付かないものは `unresolved` に隔離する

## 重要な注意事項

- 設計書の雛形展開・生成・記入は一切行わない。本スキルの成果物はバッチ一覧.htmlのみ
- Phase 4のHTML手作業組み立てを禁止する。`build-unit-list.sh` を必ず経由し、プレースホルダの手動置換によるデータ混入を防ぐ
- 0件検出時にAskUserQuestionで手動リストを聞き出さない。誤った境界を即興確定させない

## 予想を裏切る挙動

- `validate-manifest.sh`・`build-unit-list.sh` は jq に依存する。未インストール環境では事前に導入する
- カスタム抽出でソースを解析する際、コメントアウトされたジョブ定義・import文を除去してから抽出する（コメント内の定義を実在として誤検出した実害を防ぐ）
- 動的に構築されるジョブ名・cron 式（変数結合等）は静的走査では確定できない。確定できないものは `confidence: low` または `unresolved` として可視化し、実在するかのように断定しない
- マニフェストの配列キーは `screens` ではなく `units` とする
- 出力先は `<output_dir>/バッチ一覧/バッチ一覧.html`。種別ごとに独立したフォルダを作成する
- 設計書の雛形展開・生成は行わない（本スキルのスコープ外）

## 設計判断

### build-unit-list.sh（共有エンジン）

**必要性**: 一覧HTML生成をClaude手作業（プレースホルダ置換）で行うと、検証なしのデータ混入が発生する（画面種別で `entryFile=None` が10件混入した実例）。JSONマニフェストからHTMLへの変換を決定的スクリプトに固定化し、手作業経路を根絶する。

**代替案を採用しなかった理由**:
- Bashツール直叩き: 毎回30行超のjq+ヒアドキュメントを手書きし、エスケープ事故が再発する
- バッチ専用ビルダーの新設: テンプレート・カラム構成は種別間で共通化されており、種別引数で吸収できる

**保守責任者**: 人手（ユーザー）

**廃棄条件**: 一覧HTMLの形式が廃止された時

### validate-manifest.sh（共有エンジン）

**必要性**: 抽出がカスタムパス（Claude手書きJSON）であるため、品質を機械保証する独立検証が必須。マニフェストスキーマ・重複キー・unresolved隔離を抽出者非依存の同一基準で検査する。Phase 1で承認した検出戦略宣言（`approvedByUser: true`）の機械的な存在確認も本スクリプトが担う。

**代替案を採用しなかった理由**:
- Claude自己申告（検証コマンドを介さない目視確認）: 自己申告のみでの品質保証はデータ混入の実害実績があり信頼できない

**保守責任者**: 人手（ユーザー）

**廃棄条件**: マニフェスト形式（JSONスキーマ）が廃止された時
