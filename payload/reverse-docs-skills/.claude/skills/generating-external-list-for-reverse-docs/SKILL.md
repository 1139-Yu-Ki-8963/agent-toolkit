---
name: generating-external-list-for-reverse-docs
description: "外部連携（unit_kind=external）専用の一覧フォルダ・外部連携一覧HTML生成。 TRIGGER when: 外部連携一覧作成、外部連携一覧生成、連携先一覧。 SKIP: 他種別の一覧（→対応する種別別一覧スキル）、往復検証/同期/実装。"
invocation: generating-external-list-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate]
---

# 外部連携一覧生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルは外部連携（`unit_kind=external` 固定）の一覧生成のみを担い、単独起動できる（起動引数 source_dir・output_dir の2つを渡せば動く）。

既存コードベースを、スタック調査→検出戦略の宣言→戦略に基づく抽出→整合検証、の順で調査し、外部連携（APIクライアント・webhookハンドラ・メッセージキュー連携等）の単位にファイルをグルーピングして **外部連携一覧.html** を作成する。**本スキルの仕事は外部連携一覧.htmlの作成のみ**であり、設計書の雛形展開・生成・記入は一切行わない。

他スキルへの依存を持たず、単独で動作する。

## 設計原則: 固定と可変の分離

マニフェストスキーマ・整合検証（`validate-manifest.sh`）・HTML生成（`build-unit-list.sh`）は決定的スクリプトに固定する。抽出（外部連携境界の検出）はプロジェクトごとに可変であり、**カスタム抽出パスのみ**を使う。外部連携には組み込み検出器が存在しないため、Claude自身が戦略宣言に沿ってプロジェクト専用の抽出手順を設計・実行し、スキーマ準拠のマニフェストJSON（配列キーは `units`）を出力する。

抽出がClaude手作業のJSON作成であっても、`validate-manifest.sh` が抽出者非依存でマニフェストの整合性を機械保証する。汎用の正規表現を無条件に当てるのではなく、対象プロジェクト固有の連携規約を先に確認してから検出することで、境界の取り違えを防ぐ。

### エンジンスクリプトの所在

エンジンスクリプトはスキルフォルダ相対で参照する（正本リポジトリと公開先はディレクトリレイアウトが同一のため、この相対パスは両環境でそのまま成立する）。

| 役割 | パス（スキルフォルダ起点） |
|---|---|
| 整合検証 | `../../../shared/scripts/unit-list/validate-manifest.sh` |
| HTML生成 | `../../../shared/scripts/unit-list/build-unit-list.sh` |

## 使用タイミング

- 既存コードベースの外部連携一覧を作りたいとき
- 起動引数: `source_dir`（ソースコードディレクトリ。探索対象）・`output_dir`（出力先ディレクトリ。外部連携一覧.htmlの書き出し先）の2つのみ。`unit_kind` 引数は持たない（external 固定）

## 出力先

`<output_dir>/外部連携一覧/外部連携一覧.html`。外部連携専用の独立フォルダを作成する。

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` でPhase 1〜4のタスクを登録する。各Phase開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 3からPhase 2へ差し戻す場合はPhase 2タスクを `in_progress` に戻す。実行環境にTaskCreate/TaskUpdateが存在しない場合は、出力先ディレクトリ内のタスク台帳ファイル（`task-ledger.md`）で同等のPhase遷移記録を代替する。

## 動作フロー（Phase 1〜4）

外部連携固有の調査項目・マニフェストスキーマは `references/external-detection.md` を参照する。

### Phase 1: スタック・連携規約の特定

- **Step 1**: `package.json`・lockファイル（`package-lock.json`/`yarn.lock`/`pnpm-lock.yaml`）等からフレームワーク・HTTPクライアント・外部サービスSDKライブラリを確定する。これらが存在しないコードベースでは import 文・API 使用形跡から推定する。完了条件: ライブラリ名とバージョンが特定済み、または特定不能の根拠（推定経路）が記録済み
- **Step 2**: 外部連携定義の所在を特定する（APIクライアントラッパー・SDK統合コード・webhookハンドラ・メッセージキューコンシューマの配置ディレクトリと定義方式）。完了条件: 連携定義を含む実ファイルパスが列挙済み
- **Step 3**: 連携先の識別パターンを調査する（接続先URL・APIキー等の環境変数名・設定ファイルの連携先定義・プロトコル種別・認証方式）。完了条件: 識別パターン候補値または「なし」が確定済み
- **Step 4**: 除外パターンを確定する。`tests`/`mocks`/`stubs` 等のノイズディレクトリを実際に `ls` で確認する。完了条件: `excludePatterns` 一覧が確定済み
- **Step 5**: 検出戦略宣言を作成し、AskUserQuestionで承認を取る。宣言JSONは一時ファイルに保存する。完了条件: 戦略JSON（`unitKind: "external"`/`extractionMethod: "custom"`/`unitIdRegex`/`excludePatterns`/`approvedByUser: true`/`notes`）が保存済み

### Phase 2: 戦略に基づく抽出

- **Step 1**: 抽出方式はカスタム抽出パスに固定される（external に組み込み検出器はない）。完了条件: `custom` で確定済み
- **Step 2**: Phase 1で宣言した手順（例: APIクライアントラッパーの走査・webhookハンドラ登録の解析・キューコンシューマ定義の収集等）をClaude自身がBash/Grep/Readで実行し、スキーマ準拠のマニフェストJSONをWriteする。**0件検出の場合はその旨をユーザーに報告してハード停止する**。連携を捏造しない。完了条件: マニフェストJSONが1件以上で生成済み、または0件を報告して停止
- **Step 3**: diagnostics相当の自己点検を行う（同一 `sourceFile` への集中・`unresolved` の多発等）。問題があれば抽出手順を見直し、Step 2をやり直す。完了条件: 点検済み、または警告を承知の上で続行と判断済み

検出結果は一時ディレクトリ（`$CLAUDE_JOB_DIR/tmp/external-manifest.json`、未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下。`${session}`はセッションIDが取得できなければ任意の一意な値でよい）に保存する。

### Phase 3: 整合検証（機械実行）

- **Step 1**: `../../../shared/scripts/unit-list/validate-manifest.sh <manifest.json> --unit-kind external` を実行する。完了条件: 全項目PASS
- **Step 2**: FAIL時は指摘に応じて修正する。修正後Step 1を再実行する。3回失敗したら抽出手順の再検討（Phase 2 Step 2）へ差し戻す。完了条件: exit 0

`validate-manifest.sh` は抽出者非依存で検証する。カスタム抽出パスであっても、この検証を通過しないマニフェストはPhase 4に進めない。

### Phase 4: 外部連携一覧.html 生成

- **Step 1**: `../../../shared/scripts/unit-list/build-unit-list.sh <manifest.json> <output_dir>/外部連携一覧/外部連携一覧.html --unit-kind external` を実行する。build側が内部でvalidateを再実行するため、検証を経ないmanifestからは生成できない。完了条件: HTML生成済み

**手作業でのプレースホルダ置換は禁止する**（過去に `entryFile=None` の混入という実害が発生している）。HTML生成は必ずスクリプト経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | Step 1〜4の調査完了（`references/external-detection.md` の調査項目に準拠）。Step 5の検出戦略宣言（`unitKind: "external"`/`unitIdRegex`/`excludePatterns`）がユーザー承認済み |
| Phase 2 | Step 2でスキーマ準拠のマニフェスト（配列キー `units`）が1件以上確定、または0件検出をユーザーに報告して停止している。Step 3で自己点検済み |
| Phase 3 | Step 1で `validate-manifest.sh --unit-kind external` が全項目PASS。Step 2のFAIL時修正ループは3回以内 |
| Phase 4 | Step 1で外部連携一覧.htmlが生成され、埋め込みJSONがマニフェストと一致している |
| **Goal** | 検証済みマニフェストのみからHTMLが生成され、未解決・警告が可視化され、設計書単位の判断材料が揃っている |

## 返却

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

- `status`: `DONE | ERROR`
- `artifacts`: 生成した外部連携一覧.htmlのパス
- `unit_list_html`: artifacts[0] の汎用名
- `embedded_json_ref`: HTML内に埋め込んだマニフェストJSONへの参照
- `unit_kind`: `external`（固定値）

## ツールリファレンス

| ツール | 用途 |
|---|---|
| Bash | `validate-manifest.sh`・`build-unit-list.sh` の実行（いずれもスキルフォルダ相対 `../../../shared/scripts/unit-list/` 配下） |
| Read | package.json・連携定義ファイル・`references/external-detection.md` の参照 |
| Grep/Glob | 連携規約（クライアントラッパー・webhookハンドラ・キューコンシューマ・識別パターン）の調査、カスタム抽出パスでの物理ファイル収集 |
| Write | 検出戦略宣言の一時保存、マニフェストJSON出力（外部連携一覧.html本体はスクリプト経由で生成） |
| AskUserQuestion | Phase 1の検出戦略宣言確認、Phase 2の0件検出時の報告 |
| TaskCreate/TaskUpdate | Phase 1〜4の進捗管理 |

## 推奨手順

- ソースディレクトリは対象プロジェクトの実コードルート（例: `backend/src`）を指定する。モノレポでアプリが複数ある場合は対象アプリのディレクトリのみを渡す（自動判別なし）
- Phase 1の調査を省略して汎用の `unitIdRegex` を当てない。プロジェクトごとに連携の実装規約・命名規約は異なる
- 連携先ごとに1ユニットとするか、プロトコル・機能ごとに分けるかは、Phase 1 Step 5の戦略宣言で明示してから抽出する

## 重要な注意事項

- 設計書の雛形展開・生成・記入は一切行わない。本スキルの成果物は外部連携一覧.htmlのみ
- Phase 4のHTML手作業組み立てを禁止する。`build-unit-list.sh` を必ず経由し、プレースホルダの手動置換による `entryFile=None` 等のデータ混入を防ぐ
- 0件検出時にAskUserQuestionで手動リストを聞き出さない。誤った境界を即興確定させない

## Gotchas

- `validate-manifest.sh`・`build-unit-list.sh` は jq に依存する。未インストール環境では事前に導入する
- カスタム抽出でソースを解析する際、コメントアウトされた連携定義・import文を除去してから抽出する（コメント内の定義を実在として誤検出した実害を防ぐ）
- モック・スタブ（テスト用の偽クライアント等）を実連携として数えない。Phase 1 Step 4の除外パターンで先に隔離する
- 自プロジェクト内の別モジュール呼び出しは外部連携ではない。境界は「プロセス外・組織外のシステムとの通信」に置く
- マニフェストの配列キーは `screens` ではなく `units` とする（`screens` は画面種別専用の後方互換キー）
- 出力先は `<output_dir>/外部連携一覧/外部連携一覧.html`。他種別と混在させない
