# マニフェストスキーマ拡張仕様

## 目的と背景

ポータル設計基盤の 2 ページ目で「△＝マニフェスト等データ源の拡張が必要」と分類した機能は、既存マニフェスト（screen-manifest / unit-manifest）が持つ最小フィールドだけでは実現できない。本仕様は、一覧ページの△機能（設計書状態列・関連 API 列・認証要否列・スケジュール列等）と交差ビュー 4 ページ（権限×画面・権限×機能・CRUD 図・トレーサビリティ）が必要とするデータを、種別ごとの追加フィールドと新規データファイルとして定義する。

## 種別ごとの追加フィールド定義

全フィールドは各マニフェストの `screens[]` / `units[]` 要素に追加する。記入規則: 表のキーはフィールド名（意味語）とし、連番を使わない。

### screens（画面）

| フィールド名 | 型 | 必須/任意 | 説明 | 抽出元の想定 |
|---|---|---|---|---|
| permissions | string[] | 任意 | 閲覧に必要なロールの配列（例: `["admin"]`。空配列は全員閲覧可） | ルートガード・ミドルウェア・認可デコレータ |
| relatedApis | string[] | 任意 | この画面が呼ぶ API の unitKey 配列 | 画面コンポーネント内の fetch / axios / API クライアント呼び出し |
| designDocStatus | string | 任意 | 設計書の着手状態。`着手済` / `未着手` の 2 値 | 設計書リポジトリ側の該当フォルダ有無 |
| category | string | 任意 | 画面区分（`管理` / `一般` 等） | ルート prefix（`/admin` 等）とディレクトリ構成 |

### apis（API）

| フィールド名 | 型 | 必須/任意 | 説明 | 抽出元の想定 |
|---|---|---|---|---|
| method | string | 任意 | HTTP メソッド。identifier 内包から独立フィールドへ昇格し、フィルタ可能にする | ルーティング定義のデコレータ・メソッド指定 |
| authRequired | boolean | 任意 | 認証の要否 | 認可ミドルウェア・`Depends` 等の依存注入 |
| callers | string[] | 任意 | 呼び出し元画面の screenKey 配列（screens.relatedApis の逆引き） | relatedApis 抽出結果からの機械生成 |
| ioSummary | string | 任意 | 受け取る入力と返す出力の 1 行要約 | リクエスト/レスポンスの型定義・スキーマ |

### tables（テーブル）

| フィールド名 | 型 | 必須/任意 | 説明 | 抽出元の想定 |
|---|---|---|---|---|
| foreignKeys | string[] | 任意 | FK 参照先テーブルの unitKey 配列 | マイグレーション・モデルの FK 定義（ER 図生成と同一の抽出元） |
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
| operationClass | string | 任意 | 操作の強さ区分。`参照系` / `更新系` / `削除系` | 関連 API の method 集合からの機械判定 |

設計書の陳腐化検知バッジは、traceability.json の `sourceHash`（後述）と設計書側の記録ハッシュの比較で実現する。マニフェスト側への専用フィールド追加は不要。

## 交差ビュー用の新規データファイル定義

一覧フォルダと同階層に置く 3 ファイル。いずれも該当データが揃った時のみ生成する（不在時は交差ビューページを生成しない）。

### permission-matrix.json（権限×画面・権限×機能）

```json
{
  "generatedAt": "2026-07-21T00:00:00+09:00",
  "roles": ["admin", "member", "guest"],
  "screens": [
    {"screenKey": "user-admin", "access": {"admin": true, "member": false, "guest": false}}
  ],
  "features": [
    {"unitKey": "user-management", "crud": {"admin": "CRUD", "member": "R", "guest": ""}}
  ]
}
```

### crud-matrix.json（機能×テーブル）

```json
{
  "generatedAt": "2026-07-21T00:00:00+09:00",
  "rows": [
    {"featureKey": "user-management", "tables": {"users": "CRUD", "audit_logs": "C"}}
  ]
}
```

### traceability.json（画面-API-テーブル対応）

```json
{
  "generatedAt": "2026-07-21T00:00:00+09:00",
  "chains": [
    {
      "screenKey": "user-admin",
      "apis": [{"unitKey": "delete-user", "tables": ["users", "audit_logs"]}],
      "sourceHash": "sha256の先頭12桁"
    }
  ]
}
```

`sourceHash` は画面ユニットの原本ソース連結ハッシュ。設計書生成時の値と比較し、不一致なら一覧ページに陳腐化バッジを表示する。

## AI設定資産ページのデータ源

対象リポジトリ内の設定資産から次の方針で抽出する。マニフェスト形式（`unitKind: "ai-config"` の unit-manifest 互換）に正規化して他種別と同じビルド経路に載せる。

- `.claude/rules/**/rule.md`: 見出しと「機械強制」表から、注入タグ・block/advisory 区分・違反時手順の有無を抽出する
- `.claude/skills/*/SKILL.md`: frontmatter の name / description から TRIGGER・SKIP 条件とフェーズ構成（`## Phase` 見出し数）を抽出する
- `.claude/agents/*.md`: サブエージェント定義から分類（計画/実行/調査/判定）と合否宣言可否を抽出する
- `.claude/settings.json`: hooks 登録から timing × matcher × スクリプト名の対応表を抽出する
- `CLAUDE.md`・`flow-values.yml`: 設定索引として所在パスと節見出しのみ列挙する（本文は転記しない）

## 影響を受けるビルドスクリプト

build-*.sh の実在ファイルは以下の 5 本（`.claude/skills/*/scripts/` 配下に build-*.sh は存在しない）。検証系の validate-manifest.sh も追加フィールドの許容が必要なため併記する。

| スクリプト | 配置 | 影響内容 |
|---|---|---|
| build-portal.sh | shared/scripts/ | AI 設定資産ページ・交差ビュー 4 ページへの導線カード追加。件数抽出の対象拡大 |
| build-unit-list.sh | shared/scripts/unit-list/ | apis / tables / batches / reports / externals の追加フィールドを列として描画（欠落時は列非表示） |
| build-screen-list.sh | shared/scripts/unit-list/ | permissions / relatedApis / designDocStatus / category 列の追加と陳腐化バッジ表示 |
| build-feature-list.sh | shared/scripts/unit-list/ | operationClass 区分列の追加 |
| build-detail-page.sh | shared/scripts/detail-pages/ | 詳細ページへの関連エンティティ（relatedApis / callers / targetTables 等）の相互参照表示 |
| validate-manifest.sh | shared/scripts/unit-list/ | 追加フィールドの型検査（存在する場合のみ検査。不在はエラーにしない） |

## 段階的移行方針

追加フィールドはすべて任意とする。既存マニフェストは無改修のまま妥当（validate-manifest.sh の必須キー集合は変更しない）。ビルドスクリプトはフィールド欠落時に該当列を非表示にし、交差ビュー用 JSON が不在なら該当ページを生成しない。これにより、旧マニフェストのプロジェクトでも現行ポータルがそのまま成立し、フィールドを埋めたプロジェクトから順に△機能が有効になる。
