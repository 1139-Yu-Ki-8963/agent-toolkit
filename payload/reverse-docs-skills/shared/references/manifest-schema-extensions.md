# マニフェストスキーマ拡張仕様

## 目的と背景

ポータル設計基盤の 2 ページ目で「△＝マニフェスト等データ源の拡張が必要」と分類した機能は、既存マニフェスト（screen-manifest / unit-manifest）が持つ最小フィールドだけでは実現できない。本仕様は、一覧ページの△機能（設計書状態列・関連 API 列・認証要否列・スケジュール列等）とマトリクス・対応表 4 ページ（権限×画面・権限×機能・CRUD 図・追跡可能性）が必要とするデータを、種別ごとの追加フィールドと新規データファイルとして定義する。

## 種別ごとの追加フィールド定義

## 画面manifestの正本・派生契約

- `<output-root>/一覧/画面一覧/screen-manifest.json`だけを人が編集するraw正本とし、`manifestContentHash`を持たせない。
- `screen-manifest.ext.json`はrawからのみ再生成する。rawの順序と既存fieldを保持し、トップレベルへ`generatedAt`と`manifestContentHash`、各画面へ本節の抽出fieldだけを追加できる。
- `manifestContentHash`は`jq -cjS '.' screen-manifest.json`の末尾改行なしbytesをSHA-256化した64桁lowercase hexとする。`screens[].sourceHash`は別概念（個別ソースの先頭12桁）であり、rawに既存なら上書きしない。
- 画面一覧、画面遷移、matrix 4 JSON/HTML、portalには同じ`manifestContentHash`を伝播し、`check-screen-manifest-consistency.sh`で埋め込みJSONまで照合する。
- 全派生の再生成は`rebuild-screen-derived-pages.sh`だけを入口とする。同一filesystemのsibling transactionで全検査を終え、管理対象13fileをcommitする。child失敗またはcommit途中失敗では開始前のtreeへrollbackする。

全フィールドは各マニフェストの `screens[]` / `units[]` 要素に追加する。記入規則: 表のキーはフィールド名（意味語）とし、連番を使わない。

### 全種別共通

| フィールド名 | 型 | 必須/任意 | 説明 | 抽出元の想定 |
|---|---|---|---|---|
| nameScope | string | 任意 | `validate-manifest.sh` 検査9（名称-一意性）の判定範囲を限定するスコープ識別子（例: screenはサイトキー、batchは配置ディレクトリ）。未指定の要素は既定スコープ（空文字列）に属し、マニフェスト全体で一意性判定される。異なるnameScope間の同名は許容し、同一nameScope内の重複だけをFAILとする（1-124） | 複数サイト・複数配置ディレクトリを横断するリポジトリで、業務名が同一コードベース内で正当に重複する場合の判定範囲。自動判定は行わず、マニフェスト生成側が該当スコープの識別子をそのまま設定する |

### 全種別共通（値の出所区分）

| フィールド名 | 型 | 必須/任意 | 説明 | 抽出元の想定 |
|---|---|---|---|---|
| valueProvenance | object | 任意 | 表示値の出所区分。フィールド名をキーとし、値は `measured`（実測。コード・設定から機械的に検出した値）/ `inferred`（推定。他の値からのヒューリスティック推定）/ `confirmed`（人間確認済み）の3値のみ。キー・値ともに検出できたフィールドだけを持つ（欠落=出所未記録） | 各抽出スクリプト（extract-screen-metadata.sh の permissions、extract-batch-metadata.sh の schedule 等）が値付与と同じ箇所で設定する |
| confirmedPermissions | string[] | 任意 | 人間確定済みの権限ロール配列。表示時は `permissions` より優先する | 設計書・ヒアリングでの人手上書き（自動生成する仕組みは無い） |
| confirmedSchedule | object | 任意 | 人間確定済みのスケジュール（`{"cron": "...", "readable": "..."}`）。表示時は `schedule` より優先する | 設計書・ヒアリングでの人手上書き（自動生成する仕組みは無い） |

`permissions` の出所対応（extract-screen-metadata.sh が付与）:
- 認可イディオム検出（`requireRole` 等の実コード検出）= `measured`
- 管理画面区分からの `["admin"]` 推定 = `inferred`
- 管理画面区分でない場合の `[]` 推定 = `inferred`
- `permissions` 自体が欠落する場合は `valueProvenance` も付与しない

`schedule` の出所対応（extract-batch-metadata.sh が付与）:
- cron 検出 = `measured`
- `confirmed` を生産する抽出処理は現状無く、`confirmedSchedule` は人手上書き用の解決口としてのみ定義する

### screens（画面）

| フィールド名 | 型 | 必須/任意 | 説明 | 抽出元の想定 |
|---|---|---|---|---|
| permissions | string[] | 任意 | 閲覧に必要なロールの配列（例: `["admin"]`。空配列は全員閲覧可） | ルートガード・ミドルウェア・認可デコレータ |
| relatedApis | string[] | 任意 | この画面が呼ぶ API の unitKey 配列 | 画面コンポーネント内の fetch / axios / API クライアント呼び出し |
| designDocStatus | string | 任意 | 設計書の着手状態。`着手済` / `未着手` の 2 値 | 設計書リポジトリ側の該当フォルダ有無 |
| category | string | 任意 | 画面区分（`管理` / `一般` 等） | ルート prefix（`/admin` 等）とディレクトリ構成 |
| confirmedScreenName | string | 任意 | 設計書で確定した画面名。表示時は推定値 `screenNameGuess` より優先する | 画面基本設計書または画面詳細設計書の先頭見出し |
| designDocPath | string | 任意 | 画面一覧HTMLから基本設計書への相対パス。ファイル実在時だけ付与する | 設計書リポジトリの該当フォルダ |
| detailDocPath | string | 任意 | 画面一覧HTMLから詳細設計書への相対パス。ファイル実在時だけ付与する | 設計書リポジトリの該当フォルダ |
| sequencePath | string | 任意 | 画面一覧HTMLからシーケンス図への相対パス。ファイル実在時だけ付与する | 設計書リポジトリの該当フォルダ |
| testCasePath | string | 任意 | 画面一覧HTMLから単体テスト仕様書への相対パス。ファイル実在時だけ付与する | 設計書リポジトリの該当フォルダ |
| unitTestViewpointPath | string | 任意 | 画面一覧HTMLから単体テスト観点表への相対パス。ファイル実在時だけ付与する | 設計書リポジトリの該当フォルダ |
| integrationTestViewpointPath | string | 任意 | 画面一覧HTMLから結合テスト観点表への相対パス。ファイル実在時だけ付与する | 設計書リポジトリの該当フォルダ |
| integrationTestCasePath | string | 任意 | 画面一覧HTMLから結合テスト仕様書への相対パス。ファイル実在時だけ付与する | 設計書リポジトリの該当フォルダ |
| scenarioPath | string | 任意 | 画面一覧HTMLから操作シナリオ仕様書への相対パス。ファイル実在時だけ付与する | 設計書リポジトリの該当フォルダ |
| sourceHash | string | 任意 | 画面ユニットの原本ソース連結ハッシュ（sha256 先頭12桁） | 原本コードの走査 |
| designDocSourceHash | string | 任意 | 設計書生成時に記録した sourceHash。sourceHash と不一致なら一覧に陳腐化バッジを表示 | 設計書生成工程の記録 |
| screenType | string | 必須 | 画面種別（Level 3 分類。8 種: top/list/detail/form/confirm/complete/error/processing_endpoint） | entryFile と幅優先探索（BFS）で解決した関連ファイルのDOM構造・テンプレート有無で判定 |
| accountGroup | string | 任意 | システム区分（Level 1 分類。許可値は `user` / `admin` / `editor` / `report` / `common`。明示mapを優先し、無効なmap値は `common`） | route prefix・detectionMethod・明示mapから正規化 |
| accountSubType | string | 任意 | 利用者権限区分（Level 2 分類。権限チェック条件分岐の有無で判定。該当なしは `common`） | entryFileとBFSで解決した関連ファイルの権限チェック |
| hasTemplate | boolean | 任意 | テンプレート実体の有無。分離テンプレートや副作用importで解決した関連ファイルも含める | entryFileとBFSで解決した関連ファイルの拡張子・テンプレート呼出し |
| parentScreen | string | 任意 | 親画面の実在するscreenKey（モーダル・ポップアップの呼出し元。該当なしは null） | モーダル候補と同階層の非モーダル親候補をscreenKey対応表で解決 |
| childComponents | object[] | 任意 | 紐づくコンポーネントの配列。各要素は `{"screenKey":"子画面キー","componentType":"modal\|popup\|iframe"}`。該当なしは `[]` | parentScreen の逆引き。統合前のモーダル候補から集約するため候補を失わない |
| isProcessingEndpoint | boolean | 任意 | 処理エンドポイント（UI を持たない）か否か（hasTemplate=false かつ screenType=processing_endpoint で判定） | テンプレート不在かつリダイレクトのみ |

値域の定義先は `shared/references/unit-axes.json` の `axes[].values` である。対象は screenType・accountGroup・accountSubType の3フィールドである。accountSubType は `valuePolicy: identifier` のため識別子形式で検査する。`validate-manifest.sh` は宣言を読んで検査し、宣言が読めない場合に限り本文書に記載の値でフォールバックする。

designDocStatus（着手済/未着手）・trigger（画面/バッチ）・direction（送信/受信）の2値制約は上記の宣言化の対象外である。引き続き検査項目8（任意フィールド-型）内のハードコード制約として、本文書の記載値がそのまま定義となる。

### apis（API）

| フィールド名 | 型 | 必須/任意 | 説明 | 抽出元の想定 |
|---|---|---|---|---|
| method | string | 任意 | HTTP メソッド。identifier の先頭語を優先する。無い場合は、framework factory（ルーティングを登録する router / app 等を生成する関数）の結果を receiver（`receiver.get(...)` の左辺オブジェクト）へ一意に静的束縛したルート呼出しだけから補完する。shadowing（内側の範囲等で同名変数・`function`・`class` を宣言し、外側の束縛を隠すこと）はreceiverだけでなくfactory識別子にも適用し、factory識別子の別値への`const`束縛・引数・`function`・`class`によるshadowing、未束縛receiver・receiver自身の再代入・送信クライアント・正規表現リテラル内の疑似ルートも根拠外 | ルーティング定義のメソッド指定 |
| authRequired | boolean | 任意 | 認証の要否 | 認可ミドルウェア・`Depends` 等の依存注入 |
| callers | string[] | 任意 | 呼び出し元画面の screenKey 配列（screens.relatedApis の逆引き） | relatedApis 抽出結果からの機械生成 |
| targetTables | string[] | 任意 | 読み書きするテーブルの unitKey 配列。空配列は調査済みゼロを表す | エンドポイント実装のクエリ・モデル操作 |
| ioSummary | string | 任意 | 受け取る入力と返す出力の 1 行要約 | リクエスト/レスポンスの型定義・スキーマ |

`build-matrix-data.sh` は、存在する `method` / `targetTables` の値を全 API units で検査する。
この値検査には `kind: "unresolved"` も含む。
「解決済み `relatedApis`」は、参照値と API の `unitKey` が一致し、API が unresolved でない状態を指す。
feature-manifest がある場合、解決済み参照 API の `method` は permission 導出用に必須である。
同じ場合でも、`targetTables` 欠落または `[]` は非 CRUD として許容する。
feature-manifest がない場合、`targetTables` キー欠落と `targetTables: []` の API はどちらも CRUD 候補にしないため、`method` 欠落を許容する。
キー欠落から CRUD を推測しない。
欠落 `method` の必須判定は、この CRUD / permission 対象 API だけに適用する。
存在する `method` は、`GET` / `POST` / `PUT` / `PATCH` / `DELETE` の文字列に限る。
存在する `targetTables` は、空白トリム後に非空の文字列だけから成る配列に限る。
引数解析の直後に、既存出力ディレクトリ内の旧3成果物だけを除去する。したがって、依存関係・入力JSON・フィールド値の検査（検査Bを含む）で停止した場合も、対象3成果物は残さない。無関係ファイルは除去しない。
検査を通過した後、3成果物は出力先と同じ親ディレクトリ内の隠し兄弟ディレクトリ（hidden sibling）に生成する。
3件の生成完了後に同じ親配下で順に移動する。公開完了前に `mv` を含む処理が非ゼロ終了した場合は EXIT cleanup が最終出力の対象3ファイル（すでに移動済みの1件を含む）をrollbackし、staging siblingも除去する。公開完了後はcleanupを解除する。

### tables（テーブル）

| フィールド名 | 型 | 必須/任意 | 説明 | 抽出元の想定 |
|---|---|---|---|---|
| foreignKeys | string[] | 任意 | FK 参照先テーブルの unitKey 配列。空配列 [] は「REFERENCES を走査した結果 FK ゼロ件」という正の観測を意味し、フィールド欠落は「走査自体ができなかった（sourceFile 不在等）」を意味する | マイグレーション・モデルの FK 定義（ER 図生成と同一の抽出元） |
| columnCount | number | 任意 | カラム数 | マイグレーション・スキーマ定義 |
| mainColumns | string[] | 任意 | 主要カラム名の配列（PK・業務キー中心に 5 個程度） | 同上 |

### batches（バッチ）

| フィールド名 | 型 | 必須/任意 | 説明 | 抽出元の想定 |
|---|---|---|---|---|
| schedule | object | 任意 | `{"cron": "0 3 * * *", "readable": "毎日 3:00"}` の 2 表記 | crontab・スケジューラ設定・ワークフロー定義 |
| targetTables | string[] | 任意 | 読み書きするテーブルの unitKey 配列 | バッチ本体のクエリ・モデル操作 |
| downstreamJobs | string[] | 任意 | 後続ジョブの unitKey 配列（失敗時の影響範囲提示用） | ジョブ依存定義・パイプライン設定 |
| execMethod | string | 任意 | 手動実行の手順（コマンド例 1 行） | README・運用手順・エントリポイント定義 |

### reports（帳票）

| フィールド名 | 型 | 必須/任意 | 説明 | 抽出元の想定 |
|---|---|---|---|---|
| format | string | 任意 | 出力形式（`PDF` / `CSV` / `Excel` 等） | 帳票生成ライブラリの呼び出し |
| trigger | string | 任意 | 出力契機。`画面` / `バッチ` の 2 値 | 呼び出し元コードの所在（画面ハンドラかジョブか） |

### externals（外部連携）

| フィールド名 | 型 | 必須/任意 | 説明 | 抽出元の想定 |
|---|---|---|---|---|
| direction | string | 任意 | `送信` / `受信` の 2 値 | クライアント実装（送信）か受け口エンドポイント（受信）か |
| protocol | string | 任意 | 通信方式（`REST` / `SFTP` / `Webhook` 等） | 接続ライブラリ・設定ファイル |
| authMethod | string | 任意 | 認証方式（`APIキー` / `OAuth2` / `Basic` 等） | 認証ヘッダ組み立て・資格情報設定 |

### features（機能・補足）

| フィールド名 | 型 | 必須/任意 | 説明 | 抽出元の想定 |
|---|---|---|---|---|
| operationClass | string | 任意 | 操作区分。`照会` / `登録` / `更新` / `削除` / `承認` / `その他` の6値 | `extract-feature-metadata.sh` による unitKey・identifier・unitNameGuess のキーワード判定 |

設計書の陳腐化検知バッジは、traceability.json の `sourceHash`（後述）と設計書側の記録ハッシュの比較で実現する。マニフェスト側への専用フィールド追加は不要。

## マトリクス・対応表用の新規データファイル定義

一覧フォルダと同階層に置く 3 ファイル。いずれも該当データが揃った時のみ生成する（不在時はマトリクス・対応表ページを生成しない）。フィールド名は shared/templates/matrix/ の各テンプレート内 JS が参照する名前と一致させる（描画側との二重管理・ドリフト禁止。build-matrix-pages.sh の必須トップレベルキー検査も本定義と同一）。`dataSource` は導出に使った入力マニフェストのパス（メタ表示用）。

### permission-matrix.json（権限×画面・権限×機能）

```json
{
  "generatedAt": "2026-07-21T00:00:00+09:00",
  "dataSource": "screen-manifest.json + api-manifest.json + feature-manifest.json",
  "roles": ["admin", "member", "guest"],
  "screens": [
    {"screenId": "user-admin", "screenName": "user-admin", "route": "/admin/users",
     "permissions": {"admin": true, "member": false, "guest": false}},
    {"screenId": "legacy-report", "screenName": "legacy-report", "route": "/legacy/report",
     "permissions": null}
  ],
  "features": [
    {"unitKey": "user-management", "crud": {"admin": "CRUD", "member": "R", "guest": ""}}
  ]
}
```

- `screenId` / `screenName` は screen-manifest の screenKey。`permissions` が `null` の画面は permissions 未抽出（権限未設定として警告表示。誤った全許可を出さない fail-safe）

### crud-matrix.json（機能×テーブル）

```json
{
  "generatedAt": "2026-07-21T00:00:00+09:00",
  "dataSource": "api-manifest.json + feature-manifest.json + table-manifest.json",
  "tables": [
    {"physicalName": "users", "logicalName": "ユーザー"},
    {"physicalName": "audit_logs"}
  ],
  "features": [
    {"featureId": "user-management", "featureName": "user-management",
     "cells": {"users": "CRUD", "audit_logs": "C"}}
  ]
}
```

- `tables[]` は table-manifest の全 units（physicalName=identifier。logicalName はあれば転記）。table-manifest 不在時は cells に現れるテーブル名の集合。`cells` のキーは physicalName
- feature-manifest 不在時は API 単位で集約し（featureId=API の unitKey）、その旨をトップレベル `note` に記録する

### traceability.json（画面-API-テーブル対応）

```json
{
  "generatedAt": "2026-07-21T00:00:00+09:00",
  "dataSource": "screen-manifest.json + api-manifest.json + table-manifest.json",
  "screens": [
    {"screenId": "user-admin", "screenName": "user-admin", "route": "/admin/users",
     "apis": ["delete-user"], "sourceHash": "sha256の先頭12桁"}
  ],
  "apis": [
    {"apiId": "delete-user", "apiName": "delete-user",
     "endpoint": "DELETE /api/users/:id", "tables": ["users", "audit-logs"]}
  ],
  "tables": [
    {"tableId": "users", "tableName": "users", "logicalName": "ユーザー"},
    {"tableId": "audit-logs", "tableName": "audit_logs"}
  ]
}
```

- 画面→テーブルの対応は `screens[].apis` と `apis[].tables` からテンプレート JS が導出する（二重データ禁止）。`tables[]` は table-manifest の全 units（不在時は apis[].tables に現れる unitKey の集合）。どの画面からも使われないテーブルは描画側で「孤立」バッジになるため、全テーブルの収載が前提
- `sourceHash` は画面ユニットの原本ソース連結ハッシュ。設計書生成時の値と比較し、不一致なら一覧ページに陳腐化バッジを表示する

### confirmation-survey.json（横断確認事項質問票）

```json
{
  "generatedAt": "2026-08-01T00:00:00+09:00",
  "dataSource": "screen-manifest.json + permission-matrix.json",
  "questions": [
    {"questionKey": "batch-0042-業務名未確定", "targetUnit": "batch-0042",
     "question": "業務名を確定してください（現在の推定名: 日次集計）",
     "evidence": "batch-manifest.json: nameConfidence=inferred", "answerTarget": ""}
  ]
}
```

- 推定名称（unit-manifestの`nameConfidence == "inferred"`）・要手動確認（`kind == "unresolved"`）・権限未設定（permission-matrix.jsonの`permissions == null`）・要確認事項（画面詳細設計書の要確認事項一覧）の4系統を横断集約する
- `questionKey` は `<対象unitKey>-<欠落種別>` 形式（連番禁止。内容要約キー規約に従う）
- `answerTarget` は現状は常に空文字列（ヒアリング回答の取り込み自動化は対象外）
- `questions` が空配列でもページ自体は生成し、確認事項が無い旨の空状態表示にする（他3スキーマの「該当データが揃った時のみ生成」という契約の例外）
- `mergedCount`（任意・整数）・`mergedQuestions`（任意・文字列配列）: 「要確認事項」系統は入力の質問文の先頭16文字由来スラッグで`questionKey`を生成するため、異なる質問文が同一スラッグに衝突し得る。衝突時は代表項目（初出）にこの2フィールドを付与する。`mergedCount`に集約件数、`mergedQuestions`に集約された全質問文を記録する。衝突が無い項目には付与しない

## AI設定資産ページのデータ源

対象リポジトリ内の設定資産から次の方針で抽出する。マニフェスト形式（`unitKind: "ai-config"` の unit-manifest 互換）に正規化して他種別と同じビルド経路に載せる。

- `.claude/rules/**/rule.md`: 見出しと「機械強制」表から、注入タグ・block/advisory 区分・違反時手順の有無を抽出する
- `.claude/skills/*/SKILL.md`: frontmatter の name / description から TRIGGER・SKIP 条件とフェーズ構成（`## Phase` 見出し数）を抽出する
- `.claude/agents/*.md`: サブエージェント定義から分類（計画/実行/調査/判定）と合否宣言可否を抽出する
- `.claude/settings.json`: hooks 登録から timing × matcher × スクリプト名の対応表を抽出する
- `CLAUDE.md`・`flow-values.yml`: 抽出対象外（AI設定資産ページには rules / skills / サブエージェント / hooks の4セクションのみを載せる）

## 抽出工程の実装

スキーマ拡張フィールドとマトリクス・対応表用 JSON は、shared/scripts/extract/ 配下の抽出・導出スクリプトが機械生成する。対応は下表のとおり。

| スクリプト名 | 入力 | 出力 | 抽出・導出の方式 |
|---|---|---|---|
| extract-screen-metadata.sh | screen-manifest.json + 原本ソース（任意: api-manifest / 設計書ディレクトリ） | 拡張画面マニフェスト | route prefix 判定と構成ファイル内のロール指定・fetch パス grep で category / permissions / relatedApis / designDocStatus / sourceHash を追加 |
| extract-api-metadata.sh | api-manifest.json + 原本ソース（任意: 拡張画面マニフェスト / table-manifest） | 拡張 API マニフェスト | identifier 先頭語を優先する。無い場合はframework factoryへの唯一の静的束縛を探す。receiverの全使用が束縛とroute callだけで、factory識別子も別値束縛・引数・`function`・`class`によるshadowingがなければmethodを補完する。コメント・文字列・正規表現リテラル内の疑似ルート、他使用・再代入・shadowingは根拠外。認証・呼出元・テーブル・I/Oも抽出する |
| extract-table-metadata.sh | table-manifest.json + マイグレーション SQL ディレクトリ | 拡張テーブルマニフェスト | CREATE TABLE ブロックの切り出しと REFERENCES 採取・unitKey 突合で foreignKeys / columnCount / mainColumns を追加 |
| extract-batch-metadata.sh・extract-report-metadata.sh・extract-external-metadata.sh | 各種別マニフェスト + 原本ソース（batch のみ任意: cron ファイル / table-manifest） | 各種別の拡張マニフェスト | cron 式・帳票ライブラリ・送受信/認証パターンの grep で schedule / format / direction 等の種別別フィールドを追加 |
| build-matrix-data.sh | 拡張済みマニフェスト群（screen / api 必須、table / feature 任意） | permission-matrix.json・crud-matrix.json・traceability.json | ソースコードは読まず、拡張フィールド（permissions / method / relatedApis / targetTables）から jq 導出する。引数解析後に旧3成果物だけを除去してから、存在値を全 API で検査する。欠落methodの必須判定は feature 有無に応じた CRUD / permission 対象だけに適用し、`targetTables` 欠落から CRUD を推測しない。不足・不正は名前を報告して非ゼロ終了する。検査通過後はhidden siblingで3件を生成し、公開途中の失敗なら対象3成果物とstaging siblingを除去する |
| extract-ai-assets.sh | リポジトリの `.claude/` 配下（rules / skills / agents / settings.json）と CLAUDE.md・flow-values.yml | AI設定資産ページ用 JSON（rules / skills / subagents / hooks + 設定索引） | rule.md の機械強制表・SKILL.md frontmatter・hooks 登録の grep/sed 抽出でマニフェスト形式に正規化 |

いずれも検出根拠が弱い値は出力しない fail-safe 方針で、抽出できないフィールドは任意フィールドの欠落として扱う。推定・検出ルールは次節「抽出の推定・検出ルール（仕様）」に仕様として記載し、スクリプト実装と同時更新で一致を保つ。本表は索引のみを担う。

## 抽出の推定・検出ルール（仕様）

本節は ground-truth 作成者が抽出スクリプト本体を読まずに期待値を書けるようにするための仕様である。スクリプトのパターンを変更した場合は本節を同時更新する。記載対象は期待値の正誤判定に直結するルールに限り、フィールドの全量は「種別ごとの追加フィールド定義」を参照する。キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

### screens（画面）

| ルールキー | 対象フィールド | 仕様 |
|---|---|---|
| category-ルートprefix判定 | category | route が `/admin` そのもの、または `/admin/...` 始まりなら「管理」。それ以外の非空 route なら「一般」。route 不在（unresolved 等）なら欠落 |
| permissions-認可イディオム検出 | permissions | 構成ファイル（files[] があればそれ、無ければ entryFile / sourceFile / mainFile）内から次のイディオムに一致する箇所のロール名を収集する: `requireRole('x')` / `requireRole("x")`、`hasRole('x')` / `hasRole("x")`、`roles: ['x', 'y']` / `roles: ["x"]`、`@RolesAllowed("x")` / `@RolesAllowed({"x","y"})` |
| permissions-管理画面admin推定 | permissions | ロール検出なし ∧ category=管理 → `["admin"]` を推定値として付与する |
| permissions-一般画面空配列 | permissions | category=一般 ∧ ロール検出なし → `[]`（全員可）を付与する。category 不明 ∧ 検出なしなら欠落 |
| relatedApis-パス一致限界 | relatedApis | 構成ファイル内の fetch パス文字列と api-manifest のパス部の一致で紐付ける。パス一致ベースであり HTTP method は判別しない。同一パスで method 違いの API が複数ある場合は全て付与される（過剰付与側に倒れる）。GET しか呼ばない画面に同パスの POST API も紐付く点は既知の限界として期待値作成時に考慮する |

### apis（API）

| ルールキー | 対象フィールド | 仕様 |
|---|---|---|
| method-識別子先頭語・静的ルート判定 | method | identifier 先頭の有効HTTP動詞を優先する。無い場合はframework factoryへの唯一の静的束縛を探す。receiver tokenの全使用が束縛とroute callだけで、factory識別子が別値への`const`束縛・引数・`function`・`class`でshadowingされていなければ採用する。コメント・文字列・正規表現リテラル内の疑似ルート、receiverの他使用・再代入・shadowingは根拠外。候補が0件または複数種類でも欠落させる |
| authRequired-判定窓 | authRequired | identifier のパス部（先頭メソッド語を除去した残り）を sourceFile 内で固定文字列検索し、最初のヒット行の前 3 行〜後 20 行を「エンドポイント近傍窓」として判定する |
| authRequired-肯定パターン | authRequired | 窓内に `Depends(get_current_user` / `@login_required` / `requireAuth` / `verify_token` / `IsAuthenticated` のいずれかがあれば true |
| authRequired-否定パターン | authRequired | 窓内に単語境界付きで `AllowAny` / `public` のいずれかがあれば false |
| authRequired-検出不能時欠落 | authRequired | パス部がソースにヒットしない、または肯定・否定のどちらのパターンも無い場合はフィールド自体を付けない（false と推定しない） |

### tables（テーブル）

| ルールキー | 対象フィールド | 仕様 |
|---|---|---|
| fk-references採取 | foreignKeys | CREATE TABLE ブロック内の `REFERENCES <table>`（カラムインライン・FOREIGN KEY 句の両方）と、sourceFile 内の同一行完結 `ALTER TABLE <対象テーブル> ... REFERENCES <table>` 行から参照先物理名を採取する |
| fk-unitKey解決 | foreignKeys | 採取した参照先物理名をマニフェスト内 identifier と大文字小文字無視で突合して unitKey へ解決する。解決できない参照先は捨てる。走査できたユニットには解決結果が 0 件でも foreignKeys: [] を明示出力する（空配列=FK なし観測済み、欠落=走査不能） |

### batches（バッチ）

| ルールキー | 対象フィールド | 仕様 |
|---|---|---|
| cron-式抽出 | schedule.cron | --cron-file 内で identifier（不在時は unitKey）を含む行から、5 フィールドの cron 式（パターン `[0-9*,/-]+` がスペース区切りで 5 連続）を抽出する。ヒットしなければ schedule 自体が欠落 |
| cron-平易表記変換 | schedule.readable | 基本パターンのみ変換する: 分・時が数値 ∧ 日=月=曜=`*` → 「毎日 H:MM」、曜日 0-6 → 「毎週X曜 H:MM」、日が数値 → 「毎月D日 H:MM」、分=`*/N` ∧ 他=`*` → 「N分ごと」。変換不能なら cron 式をそのまま readable に入れる |

### reports（帳票）

| ルールキー | 対象フィールド | 仕様 |
|---|---|---|
| format-ライブラリ検出 | format | sourceFile 内を grep する: `reportlab` / `fpdf` / `pdf`（大文字小文字無視）→ PDF、`csv.writer` / `to_csv` → CSV、`openpyxl` / `xlsxwriter`（大文字小文字無視）→ Excel |
| format-単一形式限定 | format | ちょうど 1 形式にヒットした場合のみ出力する。複数形式に同時ヒット・0 件はどちらも欠落 |

### externals（外部連携）

| ルールキー | 対象フィールド | 仕様 |
|---|---|---|
| direction-送信パターン | direction | `requests.(get\|post\|put\|patch\|delete)` / `httpx` / `fetch(` / `axios` / `paramiko` / `SFTPClient` のいずれかにヒットで送信候補 |
| direction-受信パターン | direction | `@app.(get\|post\|put\|patch\|delete)` / `@router.(get\|post\|put\|patch\|delete)` / `@app.route` のいずれかにヒットで受信候補 |
| direction-片側ヒット限定 | direction | 送信のみヒット → 送信、受信のみヒット → 受信。両方ヒット・どちらも 0 件は欠落 |
| protocol-優先順判定 | protocol | 先勝ちで判定する: `paramiko` / `sftp`（大文字小文字無視）→ SFTP、`webhook`（大文字小文字無視）→ Webhook、`requests.` / `httpx` / `fetch(` / `axios` / `urllib` → REST。どれにもヒットしなければ欠落 |
| protocol-webhook文字列必須 | protocol | protocol=Webhook の判定にはソース内の `webhook` 文字列一致が必要である。受信方向の REST エンドポイントというだけでは Webhook と判定しない |
| authMethod-優先順判定 | authMethod | 先勝ちで判定する: `Authorization.*Bearer` / `OAuth` → OAuth2、`api_key` / `X-API-Key` / `apikey`（大文字小文字無視）→ APIキー、`HTTPBasicAuth` / `basic_auth`（大文字小文字無視）→ Basic。どれにもヒットしなければ欠落 |

## 影響を受けるビルドスクリプト

build-*.sh の実在ファイルは以下の 5 本（`.claude/skills/*/scripts/` 配下に build-*.sh は存在しない）。検証系の validate-manifest.sh も追加フィールドの許容が必要なため併記する。

| スクリプト | 配置 | 影響内容 |
|---|---|---|
| build-portal.sh | shared/scripts/ | マトリクス・対応表・AI設定資産への導線カードを実装済み（ファイル不在時は非表示） |
| build-unit-list.sh | shared/scripts/unit-list/ | 行生成は無改修。任意列はテンプレート内 JS が埋め込みマニフェストから描画する（欠落時は列非表示） |
| build-screen-list.sh | shared/scripts/unit-list/ | 行生成は無改修。任意列はテンプレート内 JS が埋め込みマニフェストから描画する（欠落時は列非表示） |
| build-feature-list.sh | shared/scripts/unit-list/ | 行生成は無改修。任意列はテンプレート内 JS が埋め込みマニフェストから描画する（欠落時は列非表示） |
| build-detail-page.sh | shared/scripts/detail-pages/ | 関連エンティティ相互参照を実装済み（フィールド不在時は現行出力と一致） |
| validate-manifest.sh | shared/scripts/unit-list/ | 追加フィールドの型検査を実装済み（存在する場合のみ検査） |
| build-matrix-pages.sh | shared/scripts/matrix/ | 新設。マトリクス・対応表4ページ + AI設定資産ページの生成（テンプレートへの JSON 埋め込みとメタ置換） |

## 段階的移行方針

screenType を除く追加フィールドは任意とする。screenType は画面種別の整合検証に必要なため、validate-manifest.sh で必須とする。ビルドスクリプトは任意フィールドが欠落した場合に該当列を非表示にし、マトリクス・対応表用 JSON が不在なら該当ページを生成しない。抽出スクリプトは検出根拠が弱い値を出力しない fail-safe 方針のため、任意フィールドの抽出漏れは列非表示として現れる（誤表示より欠落を優先）。

## 設計判断

### shared/scripts/extract/ 配下の抽出スクリプト群（6本）

- 必要性: スキーマ拡張フィールドとマトリクス・対応表用 JSON は実プロジェクトのコードから機械抽出しない限り恒常運用できない。検出ヒューリスティック（認可デコレータ・fetch パス・FK 定義・cron 定義等の grep）は種別ごとに分岐が多く、hook や手作業では再現不能
- 代替案を採用しなかった理由:
  - Bash 直叩き: 種別×フィールドで 20 超のヒューリスティックを毎回組み立てるのは非現実的
  - 既存 detect-screens.sh への統合: 検出と拡張抽出は実行タイミングが異なり、2455 行の既存スクリプトへの追記は保守性を損なう
  - Makefile 追加: 本リポジトリにビルド設定なし
- 保守責任者: 人手（ユーザー）。対象プロジェクトのフレームワークが検出パターンに合わない場合は各スクリプトのヒューリスティックへ追記する
- 廃棄条件: マニフェスト拡張フィールドが上流の検出工程（detect-screens.sh 等）に統合された時

### extract-table-metadata.sh

- 配置: shared/scripts/extract/extract-table-metadata.sh
- 必要性: 本仕様「tables（テーブル）」表の任意フィールド（foreignKeys / columnCount / mainColumns）をマイグレーション SQL から既存 table マニフェストへ決定的に追加する抽出エンジン。CREATE TABLE ブロックの切り出し・制約行の除外・REFERENCES 参照先と identifier の unitKey 突合という多段の分岐を持ち、一行コマンドでは再現できない。fail-safe（根拠が弱い値は欠落させる）の判定を毎回手書きで再現することは非現実的
- 代替案を採用しなかった理由:
  - Bash ツール直叩き: テーブルごとの grep/sed 収集 → jq 合成 → validate-manifest.sh 検証の一連を都度組み立てるとトークンを浪費し、抽出条件の再現性も保てない
  - 既存 Makefile 拡張 / package.json scripts 追加: 本リポジトリにビルド設定が存在せず、新規導入は本抽出専用の依存を増やすだけになる
  - build-unit-list.sh への統合: 一覧 HTML 生成（表示側）とメタデータ抽出（データ生成側）は工程が別であり、混在は複雑度を上げる
- 保守責任者: 人手（ユーザー）。本仕様の「tables（テーブル）」表のフィールドを増減する場合は本スクリプトのヘッダのヒューリスティック一覧と --self-test のフィクスチャを同時に更新する
- 廃棄条件: tables の追加フィールドが廃止された時、または抽出が単一エンジンに統合された時

### extract-screen-metadata.sh

- 配置: shared/scripts/extract/extract-screen-metadata.sh
- 必要性: 本仕様「screens（画面）」表の任意フィールド（category / permissions / relatedApis / designDocStatus / sourceHash）を既存 screen-manifest へ決定的に追加する抽出エンジン。grep ベースの複数ヒューリスティック・api-manifest との unitKey 突合・sha256 連結ハッシュという多段の分岐を持ち、画面数分の反復実行が前提のためスクリプト化が必要。fail-safe（根拠が弱い値は欠落させる）の判定を毎回手書きで再現することは非現実的
- 代替案を採用しなかった理由:
  - Bash ツール直叩き: 画面ごとの grep 収集 → jq 合成 → validate-manifest.sh 検証の一連を都度組み立てるとトークンを浪費し、抽出条件の再現性も保てない
  - 既存 Makefile 拡張 / package.json scripts 追加: 本リポジトリにビルド設定が存在せず、新規導入は本抽出専用の依存を増やすだけになる
  - build-unit-list.sh への統合: 一覧 HTML 生成（表示側）とメタデータ抽出（データ生成側）は工程が別であり、混在は複雑度を上げる
- 保守責任者: 人手（ユーザー）。本仕様の「screens（画面）」表のフィールドを増減する場合は本スクリプトの抽出ヒューリスティックと self-test を同時に更新する
- 廃棄条件: screens の追加フィールドが廃止された時、または抽出が単一エンジンに統合された時

### extract-ai-assets.sh

- 配置: shared/scripts/extract/extract-ai-assets.sh
- 必要性: 本仕様「AI設定資産ページのデータ源」の 5 系統（rules / skills / subagents / hooks / 設定索引）を横断する grep/sed/jq ヒューリスティックの組合せであり、都度手書きすると抽出規則が実行ごとにぶれて決定的生成が成立しない。サンプルページの埋め込みマニフェストとキー構成を一致させる契約検証（--self-test）ごとスクリプトに封じ込める必要がある
- 代替案を採用しなかった理由:
  - Bash ツール直叩き: 5 系統 × 各数フィールドの抽出規則を毎回再現するのは非現実的で、fail-safe（根拠が弱い値は欠落させる）の判定が属人化する
  - build-unit-list.sh への統合: unit-manifest 契約と AI設定資産スキーマは別物で、検証ロジックの混在は複雑度を上げる（build-matrix-pages.sh と同じ判断）
  - 既存 Makefile 拡張 / package.json scripts 追加: 本リポジトリにビルド設定が存在しない
- 保守責任者: 人手（ユーザー）。本仕様「AI設定資産ページのデータ源」の抽出方針を増減する場合は本スクリプトのヘッダのヒューリスティック一覧と --self-test のフィクスチャを同時に更新する
- 廃棄条件: AI設定資産ページが廃止された時、またはポータル生成が単一エンジンに統合された時

### extract-api-metadata.sh

- 配置: shared/scripts/extract/extract-api-metadata.sh
- 必要性: 本仕様「apis（API）」表の任意フィールド（method / authRequired / callers / targetTables / ioSummary）を既存 api-manifest へ決定的に追加する抽出エンジン。エンドポイント近傍窓の切り出し・認証/認証除外パターンの grep・拡張画面マニフェストの relatedApis 逆引き・テーブル物理名の交差 grep という多段のヒューリスティックを持ち、抽出できない値は付けない fail-safe（誤った値より欠落を優先）の判定を毎回手書きで再現することは非現実的
- 代替案を採用しなかった理由:
  - Bash ツール直叩き: エンドポイントごとの近傍窓抽出 → パターン判定 → jq 合成 → validate-manifest.sh 検証の一連を都度組み立てるとトークンを浪費し、抽出条件の再現性も保てない
  - 既存 Makefile 拡張 / package.json scripts 追加: 本リポジトリにビルド設定が存在せず、新規導入は本抽出専用の依存を増やすだけになる
  - build-unit-list.sh への統合: 一覧 HTML 生成（表示側）とメタデータ抽出（データ生成側）は工程が別であり、混在は複雑度を上げる
- 保守責任者: 人手（ユーザー）。本仕様の「apis（API）」表のフィールド、または検出パターン（認証/認証除外・モデル名接尾辞）を増減する場合は本スクリプトのヘッダコメントのヒューリスティック一覧と self-test を同時に更新する
- 廃棄条件: apis の追加フィールドが廃止された時、または抽出が単一エンジンに統合された時

### extract-batch-metadata.sh

- 配置: shared/scripts/extract/extract-batch-metadata.sh
- 必要性: 本仕様「batches（バッチ）」表の任意フィールド（schedule / targetTables / downstreamJobs / execMethod）を既存 batch マニフェストへ決定的に追加する抽出エンジン。cron ファイルからの 5 フィールド cron 式抽出と平易表記変換・テーブルマニフェスト identifier の交差 grep・shebang/`__main__` ガードからのコマンド生成・呼び出し/enqueue 系キーワード行と他バッチ identifier の突合という多段のヒューリスティックを持ち、抽出できない値は付けない fail-safe（誤った値より欠落を優先）の判定を毎回手書きで再現することは非現実的
- 代替案を採用しなかった理由:
  - Bash ツール直叩き: バッチごとの grep 収集 → 平易表記変換 → jq 合成 → validate-manifest.sh 検証の一連を都度組み立てるとトークンを浪費し、抽出条件の再現性も保てない
  - 既存 Makefile 拡張 / package.json scripts 追加: 本リポジトリにビルド設定が存在せず、新規導入は本抽出専用の依存を増やすだけになる
  - build-unit-list.sh への統合: 一覧 HTML 生成（表示側）とメタデータ抽出（データ生成側）は工程が別であり、混在は複雑度を上げる
- 保守責任者: 人手（ユーザー）。本仕様の「batches（バッチ）」表のフィールド、または検出パターン（cron 平易表記の基本パターン・呼び出し系キーワード）を増減する場合は本スクリプトのヘッダのヒューリスティック一覧と --self-test のフィクスチャを同時に更新する
- 廃棄条件: batches の追加フィールドが廃止された時、または抽出が単一エンジンに統合された時

### extract-report-metadata.sh

- 配置: shared/scripts/extract/extract-report-metadata.sh
- 必要性: 本仕様「reports（帳票）」表の任意フィールド（format / trigger）を既存 report マニフェストへ決定的に追加する抽出エンジン。帳票ライブラリ 3 系統（PDF/CSV/Excel）の grep 判定は「ちょうど 1 形式ヒット時のみ出力」という fail-safe 分岐を持ち、trigger の 2 値（画面/バッチ）は validate-manifest.sh の値域制約と一致させる必要がある。この契約を毎回手書きで再現することは非現実的
- 代替案を採用しなかった理由:
  - Bash ツール直叩き: 帳票ごとの grep 収集 → jq 合成 → validate-manifest.sh 検証の一連を都度組み立てるとトークンを浪費し、抽出条件の再現性も保てない
  - 既存 Makefile 拡張 / package.json scripts 追加: 本リポジトリにビルド設定が存在せず、新規導入は本抽出専用の依存を増やすだけになる
  - build-unit-list.sh への統合: 一覧 HTML 生成（表示側）とメタデータ抽出（データ生成側）は工程が別であり、混在は複雑度を上げる
- 保守責任者: 人手（ユーザー）。本仕様の「reports（帳票）」表のフィールド、または形式検出パターン（帳票ライブラリ名）を増減する場合は本スクリプトのヘッダのヒューリスティック一覧と --self-test のフィクスチャを同時に更新する
- 廃棄条件: reports の追加フィールドが廃止された時、または抽出が単一エンジンに統合された時

### extract-external-metadata.sh

- 配置: shared/scripts/extract/extract-external-metadata.sh
- 必要性: 本仕様「externals（外部連携）」表の任意フィールド（direction / protocol / authMethod）を既存 external マニフェストへ決定的に追加する抽出エンジン。送信クライアント記述と受け口定義の排他判定（両ヒット時は付けない fail-safe）・SFTP > Webhook > REST / OAuth2 > APIキー > Basic の優先順判定という多段のヒューリスティックを持ち、direction の 2 値（送信/受信）は validate-manifest.sh の値域制約と一致させる必要がある。この契約を毎回手書きで再現することは非現実的
- 代替案を採用しなかった理由:
  - Bash ツール直叩き: 連携ごとの grep 収集 → 排他/優先順判定 → jq 合成 → validate-manifest.sh 検証の一連を都度組み立てるとトークンを浪費し、抽出条件の再現性も保てない
  - 既存 Makefile 拡張 / package.json scripts 追加: 本リポジトリにビルド設定が存在せず、新規導入は本抽出専用の依存を増やすだけになる
  - build-unit-list.sh への統合: 一覧 HTML 生成（表示側）とメタデータ抽出（データ生成側）は工程が別であり、混在は複雑度を上げる
- 保守責任者: 人手（ユーザー）。本仕様の「externals（外部連携）」表のフィールド、または検出パターン（送受信クライアント・プロトコル・認証方式）を増減する場合は本スクリプトのヘッダのヒューリスティック一覧と --self-test のフィクスチャを同時に更新する
- 廃棄条件: externals の追加フィールドが廃止された時、または抽出が単一エンジンに統合された時

### build-matrix-data.sh

- 配置: shared/scripts/extract/build-matrix-data.sh
- 必要性: マトリクス・対応表 3 ファイル（permission-matrix.json・crud-matrix.json・traceability.json）は、拡張済みマニフェスト群からの純粋な導出（ロール集合の合成・method→CRUD 文字の合成・relatedApis→targetTables の連結）であり、同一入力から同一出力を再現する決定的エンジンが必要。存在する method / targetTables は unresolved を含む全 API で検査する。欠落methodの必須判定では unresolved を除外し、feature 有無ごとの CRUD / permission 対象だけに限定する。`targetTables` 欠落から CRUD を推測せず、不足・不正は名前付きで出力前に停止し、空配列は許容する多段の jq 変換を持つ。公開はhidden siblingから3件を順に移動し、途中失敗時は対象3成果物とstaging siblingを除去する。--self-test がフィクスチャ生成 → 導出 → jq 検証 → validate-manifest.sh 突合に加え、2件目の公開 `mv` をtmp内のshimで失敗させるrollback回帰まで自動検証する
- 代替案を採用しなかった理由:
  - Bash ツール直叩き: 3 ファイル分の jq 導出と fail-safe 分岐を都度組み立てるとトークンを浪費し、決定的生成が成立しない
  - build-matrix-pages.sh への統合: あちらはテンプレート置換（表示側）担当。データ導出と表示生成を分離しないと、マニフェスト更新時にデータだけ再生成したい場面でページ生成まで巻き込まれる
  - 既存 Makefile 拡張 / package.json scripts 追加: 本リポジトリにビルド設定が存在しない
- 保守責任者: 人手（ユーザー）。本仕様「マトリクス・対応表用の新規データファイル定義」のスキーマを増減する場合は本スクリプトの導出規則・--self-test を同時に更新する
- 廃棄条件: マトリクス・対応表ページが廃止された時、またはポータル生成が単一エンジンに統合された時

### build-matrix-pages.sh

- 必要性: マトリクス・対応表 4 ページと AI 設定資産ページのテンプレートはプレースホルダマーカーを持ち、決定的生成には既存一覧と同じマーカー置換エンジンが必要。5 ページ分の生成をページ種別引数で束ねることで、既存 build-unit-list.sh のディスパッチャ方式と対称になる
- 代替案を採用しなかった理由:
  - Bash ツール直叩き: マーカー置換の誤爆対策と検証を毎回手書きするのは非現実的
  - build-unit-list.sh への統合: unit-manifest 契約とマトリクス・対応表 JSON はスキーマが別物で、検証ロジックの混在は複雑度を上げる
  - Makefile 追加: 本リポジトリにビルド設定が存在しない
- 保守責任者: 人手（ユーザー）
- 廃棄条件: マトリクス・対応表ページが廃止された時、またはポータル生成が単一エンジンに統合された時

### aggregate-test-viewpoints.sh

- 配置: shared/scripts/extract/aggregate-test-viewpoints.sh
- 必要性: 画面ごとに分散した単体テスト観点表・結合テスト観点表（`<output_dir>/<screenUnitRoot>/screen-*/詳細設計/{単体テスト観点表.md,結合テスト観点表.md}`。`screenUnitRoot` は output-layout.json で解決）を横断集約し、章見出し（カテゴリ）単位・観点列を決定的に抽出して 1 つの JSON（unitKind: test_viewpoint）にまとめるエンジン。Markdown テーブルのヘッダ行/セパレータ行判定・観点列の位置解決（列名一致→部分一致のフォールバック）・プレースホルダ例示行の除外という多段の状態遷移を伴い、画面数×テスト種別数ぶん繰り返し実行される前提のため、手書き grep では再現性が保てない
- 代替案を採用しなかった理由:
  - Bash ツール直叩き: ファイルごとのテーブル境界判定・列解決・jq 合成を都度組み立てるとトークンを浪費し、抽出条件（ヘッダ判定・プレースホルダ除外）の再現性も保てない
  - 既存 Makefile 拡張 / package.json scripts 追加: 本リポジトリにビルド設定が存在せず、新規導入は本抽出専用の依存を増やすだけになる
  - convert-message-doc-to-manifest.sh への統合: あちらは固定 5 列テーブル（メッセージ定義書）専用パーサであり、本スクリプトは章見出し追跡とヘッダ列動的解決を要する別形式のテーブルを扱う。契約（入力形式・出力スキーマ）が異なるため統合すると分岐が複雑化する
- 保守責任者: 人手（ユーザー）。単体テスト観点表・結合テスト観点表のテーブル列構成（`キー | 対象 | 観点 | ...`）を変更する場合は本スクリプトの観点列解決ロジック（完全一致「観点」→部分一致フォールバック）を同時に更新する
- 廃棄条件: テスト観点表の横断集約が rebuilding-code-from-docs 系スキルの単一抽出エンジンに統合された時、またはテスト観点表フォーマット自体が廃止された時
